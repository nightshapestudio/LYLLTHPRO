// LUNATK realtime core. See LYSynthCore.h for the contract.

#include "LYSynthCore.h"
#include "LYSynthFX.hpp"

#include <Accelerate/Accelerate.h>
#include <mach/mach_time.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <vector>

namespace {

constexpr int kSize = LY_WT_SIZE;
constexpr int kLevels = 11;          // octave mipmaps: 1023 harmonics down to 1
constexpr int kMaxVoices = 16;
constexpr int kMaxUnison = 16;
constexpr int kChunk = 16;           // modulation is recomputed every 16 samples at most
constexpr int kQueue = 1024;
constexpr int kPending = 1024;
constexpr int kScope = 2048;
constexpr int kCombSize = 4096;      // voice comb filter: down to ~11 Hz at 44.1 kHz
constexpr int kHeldNotes = 32;
constexpr int kInsertComb = 2048;   // voice insert comb: down to ~22 Hz at 44.1 kHz
constexpr double kTwoPi = 6.283185307179586476925286766559;

// MARK: - Small helpers

inline float clamp01(float v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
inline float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline float flushf(float v) { return std::fabs(v) < 1e-15f ? 0.f : v; }
inline float fastTanh(float x) {
    x = clampf(x, -3.f, 3.f);
    const float x2 = x * x;
    return x * (27.f + x2) / (27.f + 9.f * x2);
}
inline double envelopeTime(float p) { return 0.0005 * std::pow(20000.0, (double)clamp01(p)); }
inline int lfoBase(int l) { return LY_LFO1_SHAPE + l * LY_LFO_STRIDE; }

struct Random {
    uint32_t state = 0x9E3779B9u;
    inline uint32_t next() {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5;
        return state;
    }
    inline float bipolar() { return (float)((int32_t)next()) / 2147483648.0f; }
    inline float unit() { return (float)(next() >> 8) / 16777216.0f; }
};

// Tempo divisions, in beats. The order is stored in patches: append only.
const double kSyncBeats[] = { 16, 8, 4, 3, 2, 1.5, 1, 0.75, 0.5, 0.375, 0.25, 0.1875, 0.125, 1.0 / 12.0, 0.0625 };
constexpr int kSyncCount = sizeof(kSyncBeats) / sizeof(kSyncBeats[0]);
inline double syncBeats(float normalized) {
    const int index = std::max(0, std::min(kSyncCount - 1, (int)std::lround(normalized * (kSyncCount - 1))));
    return kSyncBeats[index];
}

// MARK: - Wavetables

struct Wavetable {
    int frames = 1;
    std::vector<float> data;   // [level][frame][kSize + 1], last sample repeats the first
    inline const float *frame(int level, int f) const {
        return data.data() + ((size_t)level * frames + (size_t)f) * (kSize + 1);
    }
};

std::shared_ptr<Wavetable> buildWavetable(const float *source, int frameCount) {
    const int frames = std::max(1, std::min(frameCount, (int)LY_WT_MAX_FRAMES));
    auto table = std::make_shared<Wavetable>();
    table->frames = frames;
    table->data.assign((size_t)kLevels * frames * (kSize + 1), 0.f);

    const vDSP_Length log2n = 11;
    FFTSetup setup = vDSP_create_fftsetup(log2n, kFFTRadix2);
    std::vector<float> re(kSize / 2), im(kSize / 2), lre(kSize / 2), lim(kSize / 2), time(kSize);

    for (int f = 0; f < frames; ++f) {
        DSPSplitComplex spectrum { re.data(), im.data() };
        vDSP_ctoz((const DSPComplex *)(source + (size_t)f * kSize), 2, &spectrum, 1, kSize / 2);
        vDSP_fft_zrip(setup, &spectrum, 1, log2n, kFFTDirection_Forward);

        for (int level = 0; level < kLevels; ++level) {
            const int limit = (kSize / 2) >> level;   // keep harmonics below this
            std::copy(re.begin(), re.end(), lre.begin());
            std::copy(im.begin(), im.end(), lim.begin());
            lre[0] = 0; lim[0] = 0;                   // no DC, no Nyquist
            for (int bin = std::max(1, limit); bin < kSize / 2; ++bin) { lre[bin] = 0; lim[bin] = 0; }
            DSPSplitComplex band { lre.data(), lim.data() };
            vDSP_fft_zrip(setup, &band, 1, log2n, kFFTDirection_Inverse);
            vDSP_ztoc(&band, 1, (DSPComplex *)time.data(), 2, kSize / 2);
            float *out = table->data.data() + ((size_t)level * frames + f) * (kSize + 1);
            const float scale = 1.f / (2.f * kSize);
            for (int i = 0; i < kSize; ++i) out[i] = time[i] * scale;
            out[kSize] = out[0];
        }
    }
    vDSP_destroy_fftsetup(setup);

    float peak = 0;
    for (int f = 0; f < frames; ++f) {
        const float *level0 = table->frame(0, f);
        for (int i = 0; i < kSize; ++i) peak = std::max(peak, std::fabs(level0[i]));
    }
    if (peak > 1e-6f) {
        const float gain = 1.f / peak;
        for (float &value : table->data) value *= gain;
    }
    return table;
}

// MARK: - Modulation building blocks

/// Shapes a 0…1 ramp. Negative curves start fast (the analogue feel),
/// positive start slow, 0 is straight.
inline float curveShape(float p, float curve) {
    if (std::fabs(curve) < 0.01f) return p;
    const float k = curve * 5.f;
    return (std::exp(k * p) - 1.f) / (std::exp(k) - 1.f);
}

struct Envelope {
    int stage = 0;    // 0 idle, 1 attack, 5 hold, 2 decay, 3 sustain, 4 release
    float value = 0;
    float progress = 0;
    float from = 0;
    inline void gateOn() { stage = 1; progress = 0; from = value; }
    inline void gateOff() { if (stage != 0) { stage = 4; progress = 0; from = value; } }
    inline void reset() { stage = 0; value = 0; progress = 0; from = 0; }
    inline void advance(int n, double sampleRate, float a, float h, float d, float s, float r, float ca, float cd, float cr) {
        switch (stage) {
        case 1:
            progress += (float)(n / (envelopeTime(a) * sampleRate));
            if (progress >= 1.f) { value = 1.f; stage = h > 0.0005f ? 5 : 2; progress = 0; break; }
            value = from + (1.f - from) * curveShape(progress, ca);
            break;
        case 5:
            value = 1.f;
            progress += (float)(n / (envelopeTime(h) * sampleRate));
            if (progress >= 1.f) { stage = 2; progress = 0; }
            break;
        case 2:
            progress += (float)(n / (envelopeTime(d) * sampleRate));
            if (progress >= 1.f) { value = s; stage = 3; break; }
            value = s + (1.f - s) * (1.f - curveShape(progress, cd));
            break;
        case 3: value = s; break;
        case 4:
            progress += (float)(n / (envelopeTime(r) * sampleRate));
            if (progress >= 1.f) { value = 0; stage = 0; break; }
            value = from * (1.f - curveShape(progress, cr));
            break;
        default: break;
        }
    }
};

struct LFOState {
    double phase = 0;
    float held = 0, previous = 0, next = 0;
    float value = 0;
    bool finished = false;      // ENV mode: ran its one cycle
    inline void retrigger(Random &random, float startPhase) {
        phase = startPhase; finished = false;
        previous = next; next = random.bipolar(); held = next;
    }
    /// The shape at phase `p` (0…1).
    inline float shapeAt(int shape, float p, const float *points, bool smooth) const {
        switch (shape) {
        case LY_LFO_SINE: return std::sin((float)kTwoPi * p);
        case LY_LFO_TRIANGLE: return 1.f - 4.f * std::fabs(p - 0.5f);
        case LY_LFO_SAW_UP: return 2.f * p - 1.f;
        case LY_LFO_SAW_DOWN: return 1.f - 2.f * p;
        case LY_LFO_SQUARE: return p < 0.5f ? 1.f : -1.f;
        case LY_LFO_SAMPLE_HOLD: return held;
        case LY_LFO_CUSTOM: {
            const float position = p * LY_LFO_POINTS;
            const int i = std::min((int)position, LY_LFO_POINTS - 1);
            if (!smooth) return points[i];
            const float t = position - i;
            const float eased = 0.5f - 0.5f * std::cos((float)M_PI * t);
            return points[i] + (points[(i + 1) % LY_LFO_POINTS] - points[i]) * eased;
        }
        default: {
            const float t = 0.5f - 0.5f * std::cos((float)M_PI * p);
            return previous + (next - previous) * t;
        }
        }
    }
    inline void advance(double increment, int shape, Random &random, const float *points, bool smooth, bool oneShot, float offset) {
        if (!finished) {
            phase += increment;
            if (phase >= 1.0) {
                if (oneShot) { phase = 1.0; finished = true; }
                else {
                    phase -= std::floor(phase);
                    previous = next; next = random.bipolar(); held = next;
                }
            }
        }
        float p = (float)(oneShot ? std::min(phase, 0.99999) : phase) + offset;
        p -= std::floor(p);
        value = shapeAt(shape, p, points, smooth);
    }
};

// MARK: - Voice filter

/// Coefficients for one filter at one moment, shared by both channels.
struct FilterSetup {
    int type = LY_FILTER_LP24;
    float a1 = 0, a2 = 0, a3 = 0, k = 2;       // SVF stage 1
    float b1 = 0, b2 = 0, b3 = 0, k2 = 2;      // SVF stage 2 (24 dB types)
    float ladderG = 0, ladderFeedback = 0, res = 0;
    float combDelay = 100, combFeedback = 0;
    float formant[3][4] = {};                  // a1 a2 a3 k per formant band
    float formantGain[3] = {1, 0.6f, 0.25f};
    float allpass = 0;
    float drive = 0, preGain = 1, postGain = 1, mix = 1;
};

inline void svfCoefficients(double hz, double sampleRate, float k, float &a1, float &a2, float &a3) {
    const float g = (float)std::tan(M_PI * std::min(hz, sampleRate * 0.45) / sampleRate);
    a1 = 1.f / (1.f + g * (g + k)); a2 = g * a1; a3 = g * a2;
}

FilterSetup makeFilter(int type, double hz, float res, float drive, float mix, double sampleRate) {
    FilterSetup f;
    f.type = type; f.res = res; f.drive = drive; f.mix = mix;
    f.preGain = 1.f + drive * 9.f;
    f.postGain = 1.f / std::sqrt(f.preGain);
    hz = std::min(std::max(hz, 10.0), sampleRate * 0.45);
    switch (type) {
    case LY_FILTER_LADDER:
        f.ladderG = (float)(1.0 - std::exp(-kTwoPi * hz / sampleRate));
        f.ladderFeedback = res * 3.9f;
        break;
    case LY_FILTER_COMB_POS: case LY_FILTER_COMB_NEG:
        f.combDelay = (float)std::min(sampleRate / hz, (double)kCombSize - 4);
        f.combFeedback = (type == LY_FILTER_COMB_POS ? 1.f : -1.f) * res * 0.96f;
        break;
    case LY_FILTER_FORMANT: {
        // Cutoff sweeps A E I O U; resonance narrows the formants.
        static const float vowels[5][3] = { {800, 1150, 2900}, {400, 1700, 2600}, {350, 1900, 2800}, {450, 800, 2830}, {325, 700, 2530} };
        const float position = clamp01((float)(std::log(hz / 20.0) / std::log(1000.0))) * 4.f;
        const int a = std::min(3, (int)position);
        const float t = position - a;
        const float k = 0.9f - res * 0.8f;
        for (int b = 0; b < 3; ++b) {
            const double centre = vowels[a][b] + (vowels[a + 1][b] - vowels[a][b]) * t;
            svfCoefficients(centre, sampleRate, k, f.formant[b][0], f.formant[b][1], f.formant[b][2]);
            f.formant[b][3] = k;
        }
        break;
    }
    case LY_FILTER_PHASER: {
        const double t = std::tan(M_PI * hz / sampleRate);
        f.allpass = (float)((t - 1) / (t + 1));
        break;
    }
    default: {
        f.k = 2.f - 1.97f * res;
        svfCoefficients(hz, sampleRate, f.k, f.a1, f.a2, f.a3);
        const bool stacked = type == LY_FILTER_LP24 || type == LY_FILTER_HP24 || type == LY_FILTER_BP24;
        f.k2 = stacked ? 2.f - 1.2f * res : f.k;
        svfCoefficients(hz, sampleRate, f.k2, f.b1, f.b2, f.b3);
        break;
    }
    }
    return f;
}

struct SVFState {
    float ic1 = 0, ic2 = 0;
    inline void reset() { ic1 = ic2 = 0; }
    inline void process(float x, float a1, float a2, float a3, float k, float &lp, float &bp, float &hp) {
        const float v3 = x - ic2;
        const float v1 = a1 * ic1 + a2 * v3;
        const float v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = flushf(2.f * v1 - ic1);
        ic2 = flushf(2.f * v2 - ic2);
        lp = v2; bp = v1; hp = x - k * v1 - v2;
    }
};

/// One channel of one voice filter: state for every type, so switching type
/// never needs allocation.
struct FilterChannel {
    SVFState svf[2];
    SVFState formant[3];
    float ladder[4] = {};
    float allpass[6] = {};
    float phaserFeedback = 0;
    float comb[kCombSize] = {};
    int combWrite = 0;
    void reset() {
        svf[0].reset(); svf[1].reset();
        for (auto &f : formant) f.reset();
        std::memset(ladder, 0, sizeof(ladder));
        std::memset(allpass, 0, sizeof(allpass));
        phaserFeedback = 0;
        std::memset(comb, 0, sizeof(comb));
        combWrite = 0;
    }
    inline float process(const FilterSetup &f, float input) {
        const float x = f.drive > 0.001f ? fastTanh(input * f.preGain) * f.postGain * 1.4f : input;
        float y;
        switch (f.type) {
        case LY_FILTER_LADDER: {
            const float in = fastTanh(x * (f.drive > 0.001f ? 1.f : 1.f) - f.ladderFeedback * ladder[3]);
            ladder[0] = flushf(ladder[0] + f.ladderG * (in - fastTanh(ladder[0])));
            ladder[1] = flushf(ladder[1] + f.ladderG * (fastTanh(ladder[0]) - fastTanh(ladder[1])));
            ladder[2] = flushf(ladder[2] + f.ladderG * (fastTanh(ladder[1]) - fastTanh(ladder[2])));
            ladder[3] = flushf(ladder[3] + f.ladderG * (fastTanh(ladder[2]) - fastTanh(ladder[3])));
            y = ladder[3] * (1.f + f.res * 0.8f);
            break;
        }
        case LY_FILTER_COMB_POS: case LY_FILTER_COMB_NEG: {
            float position = (float)combWrite - f.combDelay;
            if (position < 0) position += kCombSize;
            const int i = (int)position;
            const float frac = position - i;
            const float delayed = comb[i % kCombSize] + (comb[(i + 1) % kCombSize] - comb[i % kCombSize]) * frac;
            const float out = x + delayed * f.combFeedback;
            comb[combWrite] = flushf(fastTanh(out));
            combWrite = (combWrite + 1) % kCombSize;
            y = out * (1.f - std::fabs(f.combFeedback) * 0.5f);
            break;
        }
        case LY_FILTER_FORMANT: {
            y = 0;
            for (int b = 0; b < 3; ++b) {
                float lp, bp, hp;
                formant[b].process(x, f.formant[b][0], f.formant[b][1], f.formant[b][2], f.formant[b][3], lp, bp, hp);
                y += bp * f.formant[b][3] * f.formantGain[b] * 2.2f;
            }
            break;
        }
        case LY_FILTER_PHASER: {
            float s = x + phaserFeedback * f.res * 0.9f;
            for (int k = 0; k < 6; ++k) {
                const float out = f.allpass * s + allpass[k];
                allpass[k] = flushf(s - f.allpass * out);
                s = out;
            }
            phaserFeedback = flushf(s);
            y = 0.5f * (x + s);
            break;
        }
        default: {
            float lp, bp, hp;
            svf[0].process(x, f.a1, f.a2, f.a3, f.k, lp, bp, hp);
            switch (f.type) {
            case LY_FILTER_LP12: y = lp; break;
            case LY_FILTER_HP12: y = hp; break;
            case LY_FILTER_BP: y = bp * f.k; break;
            case LY_FILTER_NOTCH: y = lp + hp; break;
            case LY_FILTER_LP24: svf[1].process(lp, f.b1, f.b2, f.b3, f.k2, lp, bp, hp); y = lp; break;
            case LY_FILTER_BP24: svf[1].process(bp * f.k, f.b1, f.b2, f.b3, f.k2, lp, bp, hp); y = bp * f.k2; break;
            default: svf[1].process(hp, f.b1, f.b2, f.b3, f.k2, lp, bp, hp); y = hp; break;
            }
            break;
        }
        }
        return input + (y - input) * f.mix;
    }
};

// MARK: - Noise

/// The noise oscillator's state. WHITE, PINK and BROWN are coloured noise;
/// CRACKLE and VINYL are sparse clicks; DIGITAL, METAL and BREATH are
/// pitched and can follow the keyboard.
struct NoiseState {
    float pink[7] = {};
    float brown = 0;
    float click = 0;
    float held = 0;
    double holdPhase = 0;
    double metalPhase[6] = {};
    SVFState breath;
    float tone = 0;
    void reset() {
        std::memset(pink, 0, sizeof(pink)); brown = 0; click = 0; held = 0; holdPhase = 0;
        std::memset(metalPhase, 0, sizeof(metalPhase)); breath.reset(); tone = 0;
    }
    inline float next(int type, Random &random, double rateHz, double sampleRate, float breathA1, float breathA2, float breathA3) {
        const float w = random.bipolar();
        switch (type) {
        case LY_NOISE_PINK: {
            pink[0] = 0.99886f * pink[0] + w * 0.0555179f; pink[1] = 0.99332f * pink[1] + w * 0.0750759f;
            pink[2] = 0.96900f * pink[2] + w * 0.1538520f; pink[3] = 0.86650f * pink[3] + w * 0.3104856f;
            pink[4] = 0.55000f * pink[4] + w * 0.5329522f; pink[5] = -0.7616f * pink[5] - w * 0.0168980f;
            const float out = pink[0] + pink[1] + pink[2] + pink[3] + pink[4] + pink[5] + pink[6] + w * 0.5362f;
            pink[6] = w * 0.115926f;
            return out * 0.22f;
        }
        case LY_NOISE_BROWN:
            brown = flushf((brown + 0.02f * w) / 1.02f);
            return brown * 3.5f;
        case LY_NOISE_CRACKLE: {
            const float density = (float)(rateHz / sampleRate);
            if (random.unit() < density) click = w > 0 ? 1.f : -1.f;
            click = flushf(click * 0.82f);
            return click;
        }
        case LY_NOISE_VINYL: {
            const float density = (float)(std::min(rateHz, 60.0) * 0.25 / sampleRate);
            if (random.unit() < density) click = w * 1.5f;
            click = flushf(click * 0.9f);
            pink[0] = 0.97f * pink[0] + w * 0.03f;
            return click + pink[0] * 0.35f;
        }
        case LY_NOISE_DIGITAL: {
            holdPhase += rateHz / sampleRate;
            if (holdPhase >= 1.0) { holdPhase -= std::floor(holdPhase); held = std::round(w * 7.f) / 7.f; }
            return held;
        }
        case LY_NOISE_METAL: {
            static const double ratios[6] = { 1.0, 1.4471, 1.6170, 1.9265, 2.5028, 2.6637 };
            float sum = 0;
            for (int k = 0; k < 6; ++k) {
                metalPhase[k] += rateHz * ratios[k] / sampleRate;
                metalPhase[k] -= std::floor(metalPhase[k]);
                sum += metalPhase[k] < 0.5 ? 1.f : -1.f;
            }
            return sum / 6.f * 0.8f + w * 0.1f;
        }
        case LY_NOISE_BREATH: {
            float lp, bp, hp;
            breath.process(w, breathA1, breathA2, breathA3, 0.35f, lp, bp, hp);
            return bp * 1.6f;
        }
        default: return w * 0.6f;
        }
    }
};

// MARK: - Voice inserts

/// One insert slot's memory, per voice.
struct InsertState {
    float hold[2];
    float holdPhase;
    double carrier;                      // ring modulator / frequency shifter oscillator
    float dcX[2], dcY[2];
    float hilbert[2][8][4];              // [channel][stage][x1 x2 y1 y2]
    float hilbertDelay[2];
    float comb[2][kInsertComb];
    int combWrite;
    void reset() { std::memset(this, 0, sizeof(*this)); holdPhase = 1; }
};

// Two 4-stage allpass chains 90° apart across the audio band (Olli Niemitalo's
// coefficients), for the frequency shifter.
const float kHilbertA[4] = { 0.6923878f, 0.9360654322959f, 0.9882295226860f, 0.9987488452737f };
const float kHilbertB[4] = { 0.4021921162426f, 0.8561710882420f, 0.9722909545651f, 0.9952884791278f };

inline float hilbertChain(float (*stages)[4], const float *coefficients, float x) {
    for (int k = 0; k < 4; ++k) {
        float *st = stages[k];
        const float a2 = coefficients[k] * coefficients[k];
        const float y = a2 * (x + st[3]) - st[1];
        st[1] = st[0]; st[0] = x;
        st[3] = st[2]; st[2] = y;
        x = y;
    }
    return x;
}

/// One insert over a chunk, in place. `noteHz` is the voice's pitch.
void processInsert(InsertState &st, int type, float *L, float *R, int n, float amount, float freq, float mix,
                   double noteHz, double sampleRate) {
    if (type <= LY_INS_OFF || type >= LY_INS_COUNT || mix <= 0.0005f) return;
    float *ch[2] = { L, R };
    switch (type) {
    case LY_INS_BITCRUSH: {
        const float steps = std::exp2(15.f - amount * 13.f);
        for (int c = 0; c < 2; ++c) for (int i = 0; i < n; ++i) {
            const float x = ch[c][i];
            ch[c][i] = x + (std::round(x * steps) / steps - x) * mix;
        }
        break;
    }
    case LY_INS_DECIMATE: {
        const float step = 1.f / (1.f + amount * amount * 63.f);
        for (int i = 0; i < n; ++i) {
            st.holdPhase += step;
            if (st.holdPhase >= 1.f) { st.holdPhase -= std::floor(st.holdPhase); st.hold[0] = L[i]; st.hold[1] = R[i]; }
            L[i] += (st.hold[0] - L[i]) * mix;
            R[i] += (st.hold[1] - R[i]) * mix;
        }
        break;
    }
    case LY_INS_SINE: {
        const float drive = (1.f + amount * 11.f) * 1.5707963f;
        for (int c = 0; c < 2; ++c) for (int i = 0; i < n; ++i) {
            const float x = ch[c][i];
            ch[c][i] = x + (std::sin(clampf(x * drive, -40.f, 40.f)) - x) * mix;
        }
        break;
    }
    case LY_INS_FOLD: {
        const float drive = 1.f + amount * 7.f;
        for (int c = 0; c < 2; ++c) for (int i = 0; i < n; ++i) {
            const float x = ch[c][i];
            const float u = clampf(x * drive, -64.f, 64.f) * 0.25f + 0.25f;
            const float y = 1.f - 4.f * std::fabs(u - std::floor(u) - 0.5f);
            ch[c][i] = x + (y - x) * mix;
        }
        break;
    }
    case LY_INS_RECTIFY: {
        // Rectifying makes DC; a blocker takes it back out.
        for (int c = 0; c < 2; ++c) for (int i = 0; i < n; ++i) {
            const float x = ch[c][i];
            const float y = x + (std::fabs(x) - x) * amount;
            const float out = y - st.dcX[c] + 0.995f * st.dcY[c];
            st.dcX[c] = y; st.dcY[c] = flushf(out);
            ch[c][i] = x + (out - x) * mix;
        }
        break;
    }
    case LY_INS_RING: {
        const double hz = std::min(noteHz * std::pow(2.0, (freq - 0.5) * 8.0), sampleRate * 0.45);
        const double increment = hz / sampleRate;
        for (int i = 0; i < n; ++i) {
            st.carrier += increment; st.carrier -= std::floor(st.carrier);
            const float c = std::sin((float)kTwoPi * (float)st.carrier);
            const float g = (1.f - amount) + amount * c;
            L[i] += (L[i] * g - L[i]) * mix;
            R[i] += (R[i] * g - R[i]) * mix;
        }
        break;
    }
    case LY_INS_SHIFT: {
        // Up to ±2 kHz, finer near the middle.
        const float f = (freq - 0.5f) * 2.f;
        const double hz = (f < 0 ? -1.0 : 1.0) * f * f * 2000.0;
        const double increment = hz / sampleRate;
        for (int i = 0; i < n; ++i) {
            st.carrier += increment; st.carrier -= std::floor(st.carrier);
            const float cs = std::cos((float)kTwoPi * (float)st.carrier), sn = std::sin((float)kTwoPi * (float)st.carrier);
            for (int c = 0; c < 2; ++c) {
                const float x = ch[c][i];
                const float re = st.hilbertDelay[c];
                st.hilbertDelay[c] = hilbertChain(st.hilbert[c], kHilbertA, x);
                const float im = hilbertChain(st.hilbert[c] + 4, kHilbertB, x);
                const float shifted = re * cs - im * sn;
                const float y = x + (shifted - x) * amount;
                ch[c][i] = x + (y - x) * mix;
            }
        }
        for (int c = 0; c < 2; ++c) for (auto &stage : st.hilbert[c]) for (auto &v : stage) v = flushf(v);
        break;
    }
    case LY_INS_COMB: {
        const double hz = std::max(25.0, noteHz * std::pow(2.0, (freq - 0.5) * 4.0));
        const float delay = (float)std::min((double)kInsertComb - 2, std::max(2.0, sampleRate / hz));
        const float feedback = amount * 0.95f;
        const float gain = std::sqrt(1.f - feedback * feedback);
        for (int i = 0; i < n; ++i) {
            float read = (float)st.combWrite - delay;
            if (read < 0) read += kInsertComb;
            const int r0 = (int)read;
            const float t = read - r0;
            const int r1 = (r0 + 1) % kInsertComb;
            for (int c = 0; c < 2; ++c) {
                const float delayed = st.comb[c][r0] + (st.comb[c][r1] - st.comb[c][r0]) * t;
                const float x = ch[c][i];
                const float y = x + feedback * delayed;
                st.comb[c][st.combWrite] = flushf(fastTanh(y));
                ch[c][i] = x + (y * gain - x) * mix;
            }
            st.combWrite = (st.combWrite + 1) % kInsertComb;
        }
        break;
    }
    default: break;
    }
}

// MARK: - Voices, events

struct Voice {
    bool active = false;
    bool gate = false;
    int note = 60;
    float velocity = 1;
    uint64_t age = 0;
    double frequency = 261.6;
    double targetFrequency = 261.6;
    double phase[2][kMaxUnison] = {};
    float uniRandom[2][kMaxUnison] = {};
    double subPhase = 0;
    float lastA[kChunk] = {};            // oscillator A's last chunk, B's FM source
    float noiseColor = 0;
    NoiseState noise;
    float random = 0;
    float stepCutoff = 1, stepResonance = 0;
    int channel = 0;
    float pressure = 0;
    bool sustained = false;
    bool fromArp = false;
    float bendSemis = 0;
    float amp = 0;
    double elapsed = 0;                  // seconds since the note began, for LFO delay and rise
    Envelope envelope[4];
    LFOState lfo[4];
    FilterChannel filter[2][2];          // [filter][channel]
    float modulation[LY_DST_COUNT] = {};
    float wavetablePosition[2] = {0, 0};
    float cutoffHz = 1000, cutoff2Hz = 1000;
    InsertState insert[2];
    float feedback[2] = {}, feedbackLow[2] = {}, feedbackDCX[2] = {}, feedbackDCY[2] = {};
};

struct Event {
    int type;       // 0 on, 1 off, 2 all off, 3 MIDI message (note = status, velocity = data1 | data2 << 8)
    int note;
    int velocity;
    uint64_t hostTime;
    float cutoff;
    float resonance;
};

struct HeldNote { int note; int velocity; uint32_t order; };

double hostTicksPerSecond() {
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    return 1e9 * (double)info.denom / (double)info.numer;
}

} // namespace

// MARK: - Synth

struct LYSynth {
    double sampleRate;
    double ticksPerSecond = hostTicksPerSecond();
    std::array<std::atomic<float>, LY_PARAM_COUNT> parameters;
    float smoothed[LY_PARAM_COUNT];
    float raw[LY_PARAM_COUNT];
    bool smooths[LY_PARAM_COUNT];

    // Wavetables: the audio thread reads `live`; `owned` keeps them alive.
    std::atomic<const Wavetable *> live[2] = { {nullptr}, {nullptr} };
    std::shared_ptr<Wavetable> owned[2];
    std::vector<std::shared_ptr<Wavetable>> retired;
    std::mutex tableMutex;

    // Multi-producer event queue; producers serialise on a spin flag, the
    // audio thread is the only consumer.
    Event queue[kQueue];
    std::atomic<uint32_t> writeIndex { 0 };
    std::atomic<uint32_t> readIndex { 0 };
    std::atomic_flag producerLock = ATOMIC_FLAG_INIT;

    Event pending[kPending];
    int pendingCount = 0;

    Voice voices[kMaxVoices];
    Voice idle;                         // neutral voice: modulation with nothing playing
    uint64_t voiceClock = 0;
    int newestVoice = -1;
    double lastFrequency = 261.6;
    LFOState globalLFO[4];
    Random random;

    // MIDI state, audio thread only.
    float masterBend = 0;
    float channelBend[16] = {};
    float channelPressure[16] = {};
    float channelTimbre[16] = {};
    bool sustainPedal = false;

    // Arpeggiator, audio thread only.
    HeldNote held[kHeldNotes];
    int heldCount = 0;
    int keysDown = 0;
    uint32_t heldOrder = 0;
    double arpCountdown = 0;          // samples to the next step
    double arpGateLeft = 0;           // samples until the sounding step is released
    int arpStep = -1;
    int arpIndex = 0;
    int arpDirection = 1;
    int arpSounding[kHeldNotes * 4];
    int arpSoundingCount = 0;
    bool arpWasOn = false;
    bool arpFresh = false;            // grid mode: a new chord waits for (or lands on) a grid line
    long arpNextStep = 0;             // grid mode: the grid step that fires next

    // Song position. `beat` runs on its own at the tempo when no transport
    // drives it; a host's position locks it (and so the synced LFOs, the
    // arpeggiator and the performers) to the bar.
    double beat = 0;
    bool songLocked = false;
    bool blockPositionValid = false;
    double blockBeat = 0;
    bool blockPlaying = false;
    std::atomic<uint32_t> anchorVersion { 0 };
    std::atomic<uint64_t> anchorHost { 0 };
    std::atomic<double> anchorBeat { 0 };
    std::atomic<int> anchorPlaying { 0 };

    // Performers: the pattern a switch key picked (-1: the patch's own).
    int perfOverride = -1;
    int perfPatternParam[2] = { -1, -1 };
    int perfPattern[2] = { 0, 0 };

    // Effects.
    lyfx::Hyper hyper;
    lyfx::Distortion distortion;
    lyfx::Flanger flanger;
    lyfx::Phaser phaser;
    lyfx::Chorus chorus;
    lyfx::Delay delay;
    lyfx::Compressor compressor;
    lyfx::EQ eq;
    lyfx::FXFilter fxFilter;
    lyfx::Reverb reverb;
    lyfx::Meter meters[LY_FX_COUNT];
    bool fxWasOn[LY_FX_COUNT] = {};
    float fxMod[LY_DST_COUNT] = {};

    float scope[kScope] = {};
    std::atomic<uint32_t> scopeWrite { 0 };
    std::atomic<float> display[40 + LY_DST_COUNT + 10];

    float mixL[kChunk], mixR[kChunk];
    float busL[kChunk], busR[kChunk];
    float oscL[2][kChunk], oscR[2][kChunk], oscMono[2][kChunk];
};

namespace {

const int kDefaultFXOrder[LY_FX_COUNT] = {
    LY_FX_HYPER, LY_FX_DIST, LY_FX_FLANGER, LY_FX_PHASER, LY_FX_CHORUS,
    LY_FX_DELAY, LY_FX_COMP, LY_FX_REVERB, LY_FX_EQ, LY_FX_FILTER
};

void setDefaults(LYSynth *s) {
    auto set = [s](int id, float v) { s->parameters[id].store(v, std::memory_order_relaxed); };
    for (int i = 0; i < LY_PARAM_COUNT; ++i) set(i, 0);
    for (int o = 0; o < 2; ++o) {
        const int b = o == 0 ? LY_OSCA_BASE : LY_OSCB_BASE;
        set(b + LY_OSC_ON, o == 0 ? 1 : 0);
        set(b + LY_OSC_LEVEL, 0.75f);
        set(b + LY_OSC_UNISON, 1);
        set(b + LY_OSC_DETUNE, 0.25f);
        set(b + LY_OSC_BLEND, 0.75f);
        set(b + LY_OSC_WIDTH, 0.8f);
        set(b + LY_OSC_RANDPHASE, 1.0f);
    }
    set(LY_SUB_LEVEL, 0.6f); set(LY_SUB_OCTAVE, 1);
    set(LY_NOISE_LEVEL, 0.3f); set(LY_NOISE_PITCH, 0.5f); set(LY_NOISE_KEYTRACK, 1);
    set(LY_FILTER_ON, 1); set(LY_FILTER_TYPE, LY_FILTER_LP24);
    set(LY_FILTER_CUTOFF, 0.8f); set(LY_FILTER_RES, 0.15f); set(LY_FILTER_MIX, 1);
    set(LY_FILTER_ROUTE_A, 1); set(LY_FILTER_ROUTE_B, 1); set(LY_FILTER_ROUTE_SUB, 1); set(LY_FILTER_ROUTE_NOISE, 1);
    set(LY_F2_TYPE, LY_FILTER_HP12); set(LY_F2_CUTOFF, 0.15f); set(LY_F2_RES, 0.1f); set(LY_F2_MIX, 1);
    const float env[4][4] = { {0.05f, 0.4f, 0.8f, 0.35f}, {0.02f, 0.42f, 0.3f, 0.4f}, {0.02f, 0.42f, 0.3f, 0.4f}, {0.02f, 0.42f, 0.3f, 0.4f} };
    for (int e = 0; e < 4; ++e) for (int k = 0; k < 4; ++k) set(LY_ENV1_A + e * 4 + k, env[e][k]);
    for (int e = 0; e < 4; ++e) { set(LY_ENV1_DCURVE + e * 3, -0.55f); set(LY_ENV1_RCURVE + e * 3, -0.55f); }
    for (int l = 0; l < 4; ++l) {
        const int b = lfoBase(l);
        set(b + (LY_LFO1_RATE - LY_LFO1_SHAPE), 0.4f);
        set(b + (LY_LFO1_SMOOTH - LY_LFO1_SHAPE), 1);
        for (int i = 0; i < LY_LFO_POINTS; ++i)
            set(LY_LFO_POINTS_BASE + l * LY_LFO_POINTS + i, std::sin((float)kTwoPi * i / LY_LFO_POINTS));
    }
    set(LY_VOICES, 8); set(LY_MASTER, 0.8f); set(LY_BPM, 120);
    set(LY_GLIDE_ALWAYS, 1); set(LY_VEL_SENS, 0.8f);
    set(LY_BEND_RANGE, 2);
    set(LY_ARP_RATE, 10.f / 14.f); set(LY_ARP_OCTAVES, 1); set(LY_ARP_GATE, 0.6f);

    set(LY_FB_DRIVE, 0.3f); set(LY_FB_TONE, 0.7f);
    for (int k = 0; k < 2; ++k) {
        const int b = LY_INS1_TYPE + k * LY_INS_STRIDE;
        set(b + (LY_INS1_AMOUNT - LY_INS1_TYPE), 0.5f);
        set(b + (LY_INS1_FREQ - LY_INS1_TYPE), 0.5f);
        set(b + (LY_INS1_MIX - LY_INS1_TYPE), 1);
    }
    // Performers start with four useful patterns: sixteenth pulses, a
    // syncopated rhythm, a one-bar rise and a stepped line.
    const char *rhythm = "x..x..x...x.x...";
    const float line[16] = { 1, -0.5f, 0.5f, -1, 0.75f, -0.25f, 0.25f, -0.75f, 1, -0.5f, 0.5f, -1, 0.75f, 0, 0.5f, -0.5f };
    for (int k = 0; k < 2; ++k) {
        const int b = LY_PERF1_MODE + k * LY_PERF_STRIDE;
        set(b + (LY_PERF1_RATE - LY_PERF1_MODE), 10.f / 14.f);
        set(b + (LY_PERF1_STEPS - LY_PERF1_MODE), 16);
        for (int i = 0; i < LY_PERF_MAX_STEPS; ++i) {
            auto at = [&](int pattern) { return (k * LY_PERF_PATTERNS + pattern) * LY_PERF_MAX_STEPS + i; };
            set(LY_PERF_VALUES_BASE + at(0), 1); set(LY_PERF_SHAPES_BASE + at(0), LY_PSTEP_DECAY);
            set(LY_PERF_VALUES_BASE + at(1), rhythm[i] == 'x' ? 1.f : 0.f); set(LY_PERF_SHAPES_BASE + at(1), LY_PSTEP_DECAY);
            set(LY_PERF_VALUES_BASE + at(2), -1.f + 2.f * i / 15.f); set(LY_PERF_SHAPES_BASE + at(2), LY_PSTEP_GLIDE);
            set(LY_PERF_VALUES_BASE + at(3), line[i]); set(LY_PERF_SHAPES_BASE + at(3), LY_PSTEP_HOLD);
        }
    }
    set(LY_PERF_KEYROOT, 24);
    set(LY_TRACK1_SOURCE, LY_SRC_NOTE); set(LY_TRACK2_SOURCE, LY_SRC_VELOCITY);
    for (int t = 0; t < 2; ++t)
        for (int i = 0; i < LY_TRACK_POINTS; ++i) set(LY_TRACK_POINTS_BASE + t * LY_TRACK_POINTS + i, -1.f + 2.f * i / (float)(LY_TRACK_POINTS - 1));

    for (int i = 0; i < LY_FX_COUNT; ++i) set(LY_FX_ORDER + i, kDefaultFXOrder[i]);
    set(LY_HYPER_RATE, 0.4f); set(LY_HYPER_DETUNE, 0.25f); set(LY_HYPER_VOICES, 0.5f); set(LY_HYPER_MIX, 0.5f);
    set(LY_HYPER_DIM_SIZE, 0.5f);
    set(LY_DIST_DRIVE, 0.25f); set(LY_DIST_TONE, 1); set(LY_DIST_MIX, 1);
    set(LY_FLANGER_RATE, 0.3f); set(LY_FLANGER_DEPTH, 0.6f); set(LY_FLANGER_FEEDBACK, 0.7f); set(LY_FLANGER_MIX, 0.5f);
    set(LY_PHASER_RATE, 0.3f); set(LY_PHASER_DEPTH, 0.6f); set(LY_PHASER_FREQ, 0.45f); set(LY_PHASER_FEEDBACK, 0.4f); set(LY_PHASER_MIX, 0.6f);
    set(LY_CHORUS_RATE, 0.3f); set(LY_CHORUS_DELAY, 0.35f); set(LY_CHORUS_DEPTH, 0.5f); set(LY_CHORUS_TONE, 0.8f); set(LY_CHORUS_MIX, 0.5f);
    set(LY_DELAY_TIME, 8.f / 14.f); set(LY_DELAY_FEEDBACK, 0.4f); set(LY_DELAY_LOWCUT, 0.1f); set(LY_DELAY_HIGHCUT, 0.7f); set(LY_DELAY_MIX, 0.3f);
    set(LY_COMP_THRESHOLD, 0.6f); set(LY_COMP_RATIO, 0.4f); set(LY_COMP_ATTACK, 0.3f); set(LY_COMP_RELEASE, 0.4f);
    set(LY_COMP_DEPTH, 0.7f); set(LY_COMP_MIX, 1);
    set(LY_EQ_LOW_FREQ, 0.4f); set(LY_EQ_MID_FREQ, 0.5f); set(LY_EQ_MID_Q, 0.4f); set(LY_EQ_HIGH_FREQ, 0.6f);
    set(LY_FXF_CUTOFF, 0.7f); set(LY_FXF_RES, 0.2f); set(LY_FXF_MIX, 1);
    set(LY_REVERB_SIZE, 0.5f); set(LY_REVERB_DECAY, 0.4f); set(LY_REVERB_DAMP, 0.4f); set(LY_REVERB_WIDTH, 1);
    set(LY_REVERB_PREDELAY, 0.1f); set(LY_REVERB_MIX, 0.3f);
}

/// Which parameters glide between blocks: the continuous ones. Switches,
/// choices, counts and drawn points jump.
void buildSmoothing(LYSynth *s) {
    for (int i = 0; i < LY_PARAM_COUNT; ++i) s->smooths[i] = false;
    auto on = [s](int id) { s->smooths[id] = true; };
    for (int o = 0; o < 2; ++o) {
        const int b = o == 0 ? LY_OSCA_BASE : LY_OSCB_BASE;
        for (int local : { LY_OSC_LEVEL, LY_OSC_PAN, LY_OSC_FINE, LY_OSC_WTPOS, LY_OSC_DETUNE, LY_OSC_BLEND,
                           LY_OSC_WIDTH, LY_OSC_WARPAMT, LY_OSC_WARPAMT2 }) on(b + local);
    }
    for (int id : { LY_SUB_LEVEL, LY_SUB_PAN, LY_NOISE_LEVEL, LY_NOISE_COLOR, LY_NOISE_PITCH, LY_NOISE_PAN,
                    LY_FILTER_CUTOFF, LY_FILTER_RES, LY_FILTER_DRIVE, LY_FILTER_KEYTRACK, LY_FILTER_ENVAMT, LY_FILTER_MIX,
                    LY_FILTER_PAN, LY_F2_CUTOFF, LY_F2_RES, LY_F2_DRIVE, LY_F2_KEYTRACK, LY_F2_ENVAMT, LY_F2_MIX,
                    LY_MACRO1, LY_MACRO2, LY_MACRO3, LY_MACRO4, LY_MODWHEEL, LY_MASTER, LY_TUNE }) on(id);
    for (int id : { (int)LY_MACRO5, (int)LY_MACRO6, (int)LY_MACRO7, (int)LY_MACRO8,
                    (int)LY_FB_AMOUNT, (int)LY_FB_DRIVE, (int)LY_FB_TONE }) on(id);
    for (int k = 0; k < 2; ++k) {
        const int b = LY_INS1_TYPE + k * LY_INS_STRIDE;
        for (int f : { LY_INS1_AMOUNT, LY_INS1_FREQ, LY_INS1_MIX }) on(b + (f - LY_INS1_TYPE));
    }
    for (int l = 0; l < 4; ++l) on(lfoBase(l) + (LY_LFO1_RATE - LY_LFO1_SHAPE));
    for (int id = LY_HYPER_ON; id < LY_MATRIX_BASE; ++id) on(id);
    for (int id : { LY_HYPER_ON, LY_DIST_ON, LY_DIST_MODE, LY_FLANGER_ON, LY_PHASER_ON, LY_CHORUS_ON, LY_DELAY_ON,
                    LY_DELAY_TIME, LY_DELAY_PINGPONG, LY_COMP_ON, LY_COMP_MODE, LY_EQ_ON, LY_FXF_ON, LY_FXF_TYPE,
                    LY_REVERB_ON, LY_REVERB_MODE }) s->smooths[id] = false;
    for (int slot = 0; slot < LY_MATRIX_SLOTS; ++slot) on(LY_MATRIX_BASE + slot * LY_MATRIX_STRIDE + LY_MX_AMOUNT);
}

inline float readWavetable(const float *table, double phase) {
    const double index = phase * kSize;
    const int i = (int)index;
    const float frac = (float)(index - i);
    return table[i] + (table[i + 1] - table[i]) * frac;
}

inline bool isPhaseWarp(int mode) {
    switch (mode) {
    case LY_WARP_SYNC: case LY_WARP_BEND_POS: case LY_WARP_BEND_NEG: case LY_WARP_MIRROR:
    case LY_WARP_PWM: case LY_WARP_ASYM_POS: case LY_WARP_ASYM_NEG: case LY_WARP_FM:
        return true;
    default: return false;
    }
}

inline double warpPhase(int mode, double p, float amount, float mod) {
    switch (mode) {
    case LY_WARP_SYNC: {
        const double stretched = p * (1.0 + amount * 7.0);
        return stretched - std::floor(stretched);
    }
    // Bends as rational curves: the shape of a power curve at a few
    // multiplies per sample instead of a pow() per unison voice.
    case LY_WARP_BEND_POS: { const double k = amount * 6.0; return p * (1.0 + k) / (1.0 + k * p); }
    case LY_WARP_BEND_NEG: { const double k = amount * 6.0; return p / (1.0 + k * (1.0 - p)); }
    case LY_WARP_MIRROR: {
        const double mirrored = p < 0.5 ? 2 * p : 2 * (1 - p);
        return p + (mirrored * 0.999 - p) * amount;
    }
    case LY_WARP_PWM: {
        const double w = 0.5 - 0.49 * amount;
        return p < w ? p * 0.5 / w : 0.5 + (p - w) * 0.5 / (1 - w);
    }
    case LY_WARP_ASYM_POS: case LY_WARP_ASYM_NEG: {
        // Pushes the cycle's middle forward or back while the ends stay put.
        const double s = 4.0 * p * (1.0 - p);   // sin(πp), near enough
        return p + (mode == LY_WARP_ASYM_POS ? 1 : -1) * amount * 0.3 * s * s;
    }
    case LY_WARP_FM: {
        const double read = p + mod * amount * 1.5;
        return read - std::floor(read);
    }
    default: return p;
    }
}

inline float warpSample(int mode, float value, float amount, float mod, double phase) {
    switch (mode) {
    case LY_WARP_RM: return value * (1.f + (mod - 1.f) * amount);
    case LY_WARP_AM: return value * ((1.f - amount) + amount * (0.5f + 0.5f * mod));
    case LY_WARP_QUANTIZE: {
        if (amount <= 0.001f) return value;
        const float steps = std::exp2(1.f + (1.f - amount) * 7.f);
        return std::round(value * steps) / steps;
    }
    case LY_WARP_FLIP: return phase > 1.0 - amount ? -value : value;
    case LY_WARP_FOLD: {
        float y = value * (1.f + amount * 6.f);
        for (int k = 0; k < 8 && std::fabs(y) > 1.f; ++k) y = y > 1.f ? 2.f - y : -2.f - y;
        return y;
    }
    default: return value;
    }
}

const float kStacks[LY_STACK_COUNT][3] = { {0, 0, 0}, {0, 12, 0}, {-12, 0, 12}, {0, 7, 12}, {0, 7, 0} };
const int kStackLength[LY_STACK_COUNT] = { 1, 2, 3, 3, 2 };

void renderOscillator(LYSynth *s, Voice &v, int o, int n, const float *m, const float *modulator) {
    const Wavetable *table = s->live[o].load(std::memory_order_acquire);
    float *outL = s->oscL[o], *outR = s->oscR[o], *mono = s->oscMono[o];
    std::memset(outL, 0, sizeof(float) * n);
    std::memset(outR, 0, sizeof(float) * n);
    std::memset(mono, 0, sizeof(float) * n);
    const int b = o == 0 ? LY_OSCA_BASE : LY_OSCB_BASE;
    const float *p = s->smoothed;
    if (s->raw[b + LY_OSC_ON] < 0.5f || table == nullptr) return;

    const int dOffset = o == 0 ? 0 : (LY_DST_B_LEVEL - LY_DST_A_LEVEL);
    const int d2 = o == 0 ? 0 : (LY_DST_B_WARP2 - LY_DST_A_WARP2);
    const float level = clamp01(p[b + LY_OSC_LEVEL] + m[LY_DST_A_LEVEL + dOffset]);
    if (level <= 0.0001f) return;
    const float pan = clampf(p[b + LY_OSC_PAN] + m[LY_DST_A_PAN + dOffset] + m[LY_DST_PAN], -1, 1);
    const float position = clamp01(p[b + LY_OSC_WTPOS] + m[LY_DST_A_WTPOS + dOffset]);
    const float detune = clamp01(p[b + LY_OSC_DETUNE] + m[LY_DST_A_DETUNE + dOffset]);
    const float blend = clamp01(p[b + LY_OSC_BLEND] + m[LY_DST_A_BLEND + dOffset]);
    const float width = clamp01(p[b + LY_OSC_WIDTH] + m[LY_DST_A_WIDTH + d2]);
    const float warp1 = clamp01(p[b + LY_OSC_WARPAMT] + m[LY_DST_A_WARP + dOffset]);
    const float warp2 = clamp01(p[b + LY_OSC_WARPAMT2] + m[LY_DST_A_WARP2 + d2]);
    const int mode1 = (int)std::lround(s->raw[b + LY_OSC_WARPMODE]);
    const int mode2 = (int)std::lround(s->raw[b + LY_OSC_WARPMODE2]);
    const int uniMode = std::max(0, std::min(LY_UNI_COUNT - 1, (int)std::lround(s->raw[b + LY_OSC_UNIMODE])));
    const int stack = std::max(0, std::min(LY_STACK_COUNT - 1, (int)std::lround(s->raw[b + LY_OSC_STACK])));
    const int unison = std::max(1, std::min(kMaxUnison, (int)std::lround(s->raw[b + LY_OSC_UNISON])));
    v.wavetablePosition[o] = position;

    const float semis = 12.f * std::round(s->raw[b + LY_OSC_OCTAVE]) + std::round(s->raw[b + LY_OSC_SEMI])
        + (p[b + LY_OSC_FINE] + m[LY_DST_A_FINE + d2] * 100.f) / 100.f + p[LY_TUNE] / 100.f
        + m[LY_DST_A_PITCH + dOffset] * 24.f + m[LY_DST_PITCH] * 24.f + v.bendSemis;
    const double frequency = v.frequency * std::pow(2.0, semis / 12.0);
    const double baseIncrement = frequency / s->sampleRate;
    if (baseIncrement >= 0.5) return;

    const double framePosition = position * (table->frames - 1);
    const int f0 = (int)framePosition;
    const int f1 = std::min(table->frames - 1, f0 + 1);
    const float ff = (float)(framePosition - f0);

    float gainL[kMaxUnison], gainR[kMaxUnison];
    double increment[kMaxUnison];
    const float *t0[kMaxUnison], *t1[kMaxUnison];
    float gainSum = 0;
    for (int j = 0; j < unison; ++j) {
        const float t = unison == 1 ? 0.f : -1.f + 2.f * j / (unison - 1);
        float spread;
        switch (uniMode) {
        case LY_UNI_SUPER: spread = t * (0.35f + 0.65f * std::fabs(t)); break;   // outer voices far, inner close
        case LY_UNI_EXP: spread = t * std::fabs(t) * std::fabs(t); break;          // a tight core with a few wide
        case LY_UNI_RANDOM: spread = unison == 1 ? 0.f : v.uniRandom[o][j]; break;
        default: spread = t; break;
        }
        const float stackSemis = unison > 1 ? kStacks[stack][j % kStackLength[stack]] : 0.f;
        const float cents = spread * detune * detune * 100.f + stackSemis * 100.f;
        increment[j] = baseIncrement * std::pow(2.0, cents / 1200.0);
        if (increment[j] >= 0.5) increment[j] = 0;
        int level = (int)std::ceil(std::log2(std::max(1.0, increment[j] * kSize)));
        level = std::max(0, std::min(kLevels - 1, level));
        t0[j] = table->frame(level, f0);
        t1[j] = table->frame(level, f1);
        const float g = unison == 1 ? 1.f : 1.f + ((0.15f + 0.85f * blend) - 1.f) * std::fabs(t);
        const float voicePan = clampf(pan + t * width, -1, 1);
        const float angle = (voicePan + 1.f) * 0.25f * (float)M_PI;
        gainL[j] = g * std::cos(angle);
        gainR[j] = g * std::sin(angle);
        gainSum += g * g;
    }
    const float normal = level / std::sqrt(std::max(gainSum, 1e-6f));
    const bool phase1 = isPhaseWarp(mode1), phase2 = isPhaseWarp(mode2);

    for (int i = 0; i < n; ++i) {
        float sumL = 0, sumR = 0, sumMono = 0;
        const float mod = modulator ? modulator[i] : 0.f;
        for (int j = 0; j < unison; ++j) {
            double ph = v.phase[o][j] + increment[j];
            ph -= std::floor(ph);
            v.phase[o][j] = ph;
            double read = ph;
            if (phase1) read = warpPhase(mode1, read, warp1, mod);
            if (phase2) read = warpPhase(mode2, read, warp2, mod);
            read = std::min(std::max(read, 0.0), 0.9999999);
            float value = readWavetable(t0[j], read);
            if (f1 != f0) value += (readWavetable(t1[j], read) - value) * ff;
            if (!phase1) value = warpSample(mode1, value, warp1, mod, ph);
            if (!phase2) value = warpSample(mode2, value, warp2, mod, ph);
            sumL += value * gainL[j];
            sumR += value * gainR[j];
            sumMono += value;
        }
        outL[i] = sumL * normal;
        outR[i] = sumR * normal;
        mono[i] = sumMono / unison;
    }
}

inline bool isUnipolar(int source) {
    switch (source) {
    case LY_SRC_LFO1: case LY_SRC_LFO2: case LY_SRC_LFO3: case LY_SRC_LFO4:
    case LY_SRC_NOTE: case LY_SRC_RANDOM: case LY_SRC_PITCHBEND:
    case LY_SRC_PERF1: case LY_SRC_PERF2: case LY_SRC_TRACK1: case LY_SRC_TRACK2:
        return false;
    default: return true;
    }
}

inline float lfoValue(const LYSynth *s, const Voice &v, int l) {
    const int b = lfoBase(l);
    const int mode = (int)std::lround(s->raw[b + (LY_LFO1_RETRIG - LY_LFO1_SHAPE)]);
    float value = mode == LY_LFOMODE_FREE ? s->globalLFO[l].value : v.lfo[l].value;
    // DELAY then RISE, per note.
    const float delay = s->raw[b + (LY_LFO1_DELAY - LY_LFO1_SHAPE)] * 4.f;
    const float rise = s->raw[b + (LY_LFO1_RISE - LY_LFO1_SHAPE)] * 4.f;
    if (delay > 0.001f || rise > 0.001f) {
        const double t = v.elapsed - delay;
        if (t <= 0) return 0;
        if (rise > 0.001f && t < rise) value *= (float)(t / rise);
    }
    return value;
}

/// Where a performer reads its pattern: the song's beat (SONG), or beats
/// since this voice's note began (TRIG).
inline double performerBeat(const LYSynth *s, const Voice &v, int k) {
    const int mode = (int)std::lround(s->raw[LY_PERF1_MODE + k * LY_PERF_STRIDE]);
    if (mode == LY_PERFMODE_TRIG) return v.elapsed * std::max(20.f, s->raw[LY_BPM]) / 60.0;
    return s->beat;
}

/// A performer's output at `beat`: the step it is on, shaped across the step.
float performerValue(const LYSynth *s, int k, double beat, int *stepOut = nullptr) {
    const int b = LY_PERF1_MODE + k * LY_PERF_STRIDE;
    const int steps = std::max(1, std::min((int)LY_PERF_MAX_STEPS, (int)std::lround(s->raw[b + (LY_PERF1_STEPS - LY_PERF1_MODE)])));
    const double stepBeats = syncBeats(s->raw[b + (LY_PERF1_RATE - LY_PERF1_MODE)]);
    double position = std::fmod(beat / stepBeats, (double)steps);
    if (position < 0) position += steps;
    const int i = std::min(steps - 1, (int)position);
    const float t = (float)(position - i);
    const int row = (k * LY_PERF_PATTERNS + s->perfPattern[k]) * LY_PERF_MAX_STEPS;
    const float value = s->raw[LY_PERF_VALUES_BASE + row + i];
    const int shape = (int)std::lround(s->raw[LY_PERF_SHAPES_BASE + row + i]);
    if (stepOut) *stepOut = i;
    switch (shape) {
    case LY_PSTEP_RAMP_UP: return value * t;
    case LY_PSTEP_RAMP_DOWN: return value * (1.f - t);
    case LY_PSTEP_TRIANGLE: return value * (1.f - std::fabs(2.f * t - 1.f));
    case LY_PSTEP_DECAY: return value * std::exp(-5.f * t);
    case LY_PSTEP_RISE: return value * (std::exp(3.f * t) - 1.f) / (std::exp(3.f) - 1.f);
    case LY_PSTEP_PULSE: return t < 0.5f ? value : 0.f;
    case LY_PSTEP_GLIDE: {
        const float previous = s->raw[LY_PERF_VALUES_BASE + row + (i + steps - 1) % steps];
        return previous + (value - previous) * (0.5f - 0.5f * std::cos((float)M_PI * t));
    }
    default: return value;
    }
}

inline float sourceValue(const LYSynth *s, const Voice &v, int source);

/// Where a tracker reads its curve (0…1) for this voice's source.
float trackerInput(const LYSynth *s, const Voice &v, int t) {
    const int source = (int)std::lround(s->raw[LY_TRACK1_SOURCE + t]);
    if (source <= LY_SRC_NONE || source >= LY_SRC_COUNT || source == LY_SRC_TRACK1 || source == LY_SRC_TRACK2) return 0;
    const float x = sourceValue(s, v, source);
    return clamp01(isUnipolar(source) ? x : 0.5f + 0.5f * x);
}

float trackerValue(const LYSynth *s, const Voice &v, int t) {
    const float position = trackerInput(s, v, t) * (LY_TRACK_POINTS - 1);
    const int i = std::min(LY_TRACK_POINTS - 2, (int)position);
    const float f = position - i;
    const float *points = s->raw + LY_TRACK_POINTS_BASE + t * LY_TRACK_POINTS;
    return points[i] + (points[i + 1] - points[i]) * f;
}

inline float sourceValue(const LYSynth *s, const Voice &v, int source) {
    switch (source) {
    case LY_SRC_ENV1: return v.envelope[0].value;
    case LY_SRC_ENV2: return v.envelope[1].value;
    case LY_SRC_ENV3: return v.envelope[2].value;
    case LY_SRC_ENV4: return v.envelope[3].value;
    case LY_SRC_LFO1: case LY_SRC_LFO2: case LY_SRC_LFO3: case LY_SRC_LFO4:
        return lfoValue(s, v, source - LY_SRC_LFO1);
    case LY_SRC_VELOCITY: return v.velocity;
    case LY_SRC_NOTE: return (v.note - 60) / 60.f;
    case LY_SRC_MODWHEEL: return s->smoothed[LY_MODWHEEL];
    case LY_SRC_MACRO1: case LY_SRC_MACRO2: case LY_SRC_MACRO3: case LY_SRC_MACRO4:
        return s->smoothed[LY_MACRO1 + (source - LY_SRC_MACRO1)];
    case LY_SRC_RANDOM: return v.random;
    case LY_SRC_STEP_CUTOFF: return v.stepCutoff;
    case LY_SRC_STEP_RES: return v.stepResonance;
    case LY_SRC_PRESSURE: return v.pressure;
    case LY_SRC_TIMBRE: return s->raw[LY_MPE] > 0.5f ? s->channelTimbre[v.channel & 15] : s->channelTimbre[0];
    case LY_SRC_PITCHBEND: return s->masterBend;
    case LY_SRC_MACRO5: case LY_SRC_MACRO6: case LY_SRC_MACRO7: case LY_SRC_MACRO8:
        return s->smoothed[LY_MACRO5 + (source - LY_SRC_MACRO5)];
    case LY_SRC_PERF1: case LY_SRC_PERF2: {
        const int k = source - LY_SRC_PERF1;
        return performerValue(s, k, performerBeat(s, v, k));
    }
    case LY_SRC_TRACK1: case LY_SRC_TRACK2: return trackerValue(s, v, source - LY_SRC_TRACK1);
    default: return 0;
    }
}

/// Every matrix route evaluated for one voice.
void evaluateMatrix(const LYSynth *s, const Voice &v, float *m) {
    std::memset(m, 0, sizeof(float) * LY_DST_COUNT);
    const float *r = s->raw;
    for (int slot = 0; slot < LY_MATRIX_SLOTS; ++slot) {
        const int base = LY_MATRIX_BASE + slot * LY_MATRIX_STRIDE;
        const int source = (int)std::lround(r[base + LY_MX_SOURCE]);
        const int destination = (int)std::lround(r[base + LY_MX_DEST]);
        if (source <= LY_SRC_NONE || source >= LY_SRC_COUNT || destination <= LY_DST_NONE || destination >= LY_DST_COUNT) continue;
        float x = sourceValue(s, v, source);
        if (r[base + LY_MX_BIPOLAR] > 0.5f && isUnipolar(source)) x = x * 2.f - 1.f;
        const float curve = r[base + LY_MX_CURVE];
        if (std::fabs(curve) > 0.01f) x = (x < 0 ? -1.f : 1.f) * curveShape(std::min(std::fabs(x), 1.f), curve);
        const int aux = (int)std::lround(r[base + LY_MX_AUX]);
        if (aux > LY_SRC_NONE && aux < LY_SRC_COUNT) {
            const float a = sourceValue(s, v, aux);
            x *= isUnipolar(aux) ? a : 0.5f + 0.5f * a;
        }
        m[destination] += s->smoothed[base + LY_MX_AMOUNT] * x;
    }
}

double lfoIncrement(const LYSynth *s, int l, const float *m, int n) {
    const int b = lfoBase(l);
    double hz;
    if (s->raw[b + (LY_LFO1_SYNC - LY_LFO1_SHAPE)] > 0.5f) {
        hz = (std::max(20.f, s->raw[LY_BPM]) / 60.0) / syncBeats(s->raw[b + (LY_LFO1_RATE - LY_LFO1_SHAPE)]);
    } else {
        hz = 0.02 * std::pow(1500.0, (double)s->smoothed[b + (LY_LFO1_RATE - LY_LFO1_SHAPE)]);
    }
    if (m) hz *= std::pow(4.0, (double)m[LY_DST_LFO1_RATE + l]);
    return hz * n / s->sampleRate;
}

void renderVoice(LYSynth *s, Voice &v, int n) {
    const float *p = s->smoothed;
    const float *r = s->raw;

    // Modulation for this chunk, from where every source is now.
    float m[LY_DST_COUNT];
    evaluateMatrix(s, v, m);
    std::memcpy(v.modulation, m, sizeof(m));
    const bool mpe = r[LY_MPE] > 0.5f;
    v.bendSemis = s->masterBend * r[LY_BEND_RANGE] + (mpe && v.channel != 0 ? s->channelBend[v.channel & 15] * 48.f : 0.f);
    if (mpe) v.pressure = s->channelPressure[v.channel & 15];

    // Glide.
    const float glide = r[LY_GLIDE];
    if (glide > 0.001f) {
        const double k = std::exp(-(double)n / (glide * s->sampleRate * 0.25));
        v.frequency = v.targetFrequency + (v.frequency - v.targetFrequency) * k;
    } else {
        v.frequency = v.targetFrequency;
    }

    // B first so A can use it as its FM / ring / AM source; B uses A's
    // previous chunk, one chunk late, which FM cannot hear.
    renderOscillator(s, v, 1, n, m, v.lastA);
    renderOscillator(s, v, 0, n, m, s->oscMono[1]);
    std::memcpy(v.lastA, s->oscMono[0], sizeof(float) * n);
    for (int i = n; i < kChunk; ++i) v.lastA[i] = 0;

    const bool f1On = r[LY_FILTER_ON] > 0.5f;
    const bool f2On = r[LY_F2_ON] > 0.5f;
    const bool anyFilter = f1On || f2On;
    float *wetL = s->mixL, *wetR = s->mixR;
    float dryL[kChunk] = {}, dryR[kChunk] = {};
    std::memset(wetL, 0, sizeof(float) * n);
    std::memset(wetR, 0, sizeof(float) * n);
    auto route = [&](const float *l, const float *rr, bool toFilter) {
        float *dl = (toFilter && anyFilter) ? wetL : dryL;
        float *dr = (toFilter && anyFilter) ? wetR : dryR;
        for (int i = 0; i < n; ++i) { dl[i] += l[i]; dr[i] += rr[i]; }
    };
    route(s->oscL[0], s->oscR[0], r[LY_FILTER_ROUTE_A] > 0.5f);
    route(s->oscL[1], s->oscR[1], r[LY_FILTER_ROUTE_B] > 0.5f);

    // Sub and noise, each with its own pan.
    float extraL[kChunk], extraR[kChunk];
    auto panGains = [](float pan, float &gl, float &gr) {
        const float angle = (clampf(pan, -1, 1) + 1.f) * 0.25f * (float)M_PI;
        gl = std::cos(angle) * 1.41421f * 0.7071f; gr = std::sin(angle) * 1.41421f * 0.7071f;
    };
    if (r[LY_SUB_ON] > 0.5f) {
        const float level = clamp01(p[LY_SUB_LEVEL] + m[LY_DST_SUB_LEVEL]);
        float gl, gr; panGains(p[LY_SUB_PAN] + m[LY_DST_SUB_PAN], gl, gr);
        const double increment = v.frequency * std::pow(2.0, (v.bendSemis + p[LY_TUNE] / 100.0 + m[LY_DST_PITCH] * 24.0) / 12.0)
            / std::exp2(std::max(1.f, std::round(r[LY_SUB_OCTAVE]))) / s->sampleRate;
        const int shape = (int)std::lround(r[LY_SUB_SHAPE]);
        const float dt = (float)increment;
        auto blep = [dt](float t) {
            if (t < dt) { t /= dt; return t + t - t * t - 1.f; }
            if (t > 1.f - dt) { t = (t - 1.f) / dt; return t * t + t + t + 1.f; }
            return 0.f;
        };
        for (int i = 0; i < n; ++i) {
            v.subPhase += increment; v.subPhase -= std::floor(v.subPhase);
            const float ph = (float)v.subPhase;
            float value;
            if (shape == 0) value = std::sin((float)kTwoPi * ph);
            else if (shape == 1) value = 1.f - 4.f * std::fabs(ph - 0.5f);
            else if (shape == 2) {
                value = ph < 0.5f ? 1.f : -1.f;
                value += blep(ph);
                float shifted = ph + 0.5f; shifted -= std::floor(shifted);
                value -= blep(shifted);
            } else {
                value = 1.f - 2.f * ph + blep(ph);
            }
            extraL[i] = value * level * gl;
            extraR[i] = value * level * gr;
        }
        route(extraL, extraR, r[LY_FILTER_ROUTE_SUB] > 0.5f);
    }
    if (r[LY_NOISE_ON] > 0.5f) {
        const float level = clamp01(p[LY_NOISE_LEVEL] + m[LY_DST_NOISE_LEVEL]);
        const float color = clamp01(p[LY_NOISE_COLOR] + m[LY_DST_NOISE_COLOR]);
        const int type = std::max(0, std::min(LY_NOISE_COUNT - 1, (int)std::lround(r[LY_NOISE_TYPE])));
        float gl, gr; panGains(p[LY_NOISE_PAN] + m[LY_DST_NOISE_PAN], gl, gr);
        const double keyHz = r[LY_NOISE_KEYTRACK] > 0.5f ? v.frequency : 261.6;
        const double rateHz = keyHz * std::pow(2.0, (clamp01(p[LY_NOISE_PITCH] + m[LY_DST_NOISE_PITCH]) - 0.5) * 8.0)
            * (type == LY_NOISE_CRACKLE ? 4.0 : type == LY_NOISE_DIGITAL ? 16.0 : type == LY_NOISE_METAL ? 12.0 : 1.0);
        float ba1 = 0, ba2 = 0, ba3 = 0;
        if (type == LY_NOISE_BREATH) svfCoefficients(std::min(rateHz * 2.0, s->sampleRate * 0.4), s->sampleRate, 0.35f, ba1, ba2, ba3);
        const float k = 1.f - color * 0.97f;
        for (int i = 0; i < n; ++i) {
            const float raw = v.noise.next(type, s->random, rateHz, s->sampleRate, ba1, ba2, ba3);
            v.noiseColor = flushf(v.noiseColor + (raw - v.noiseColor) * k);
            const float value = v.noiseColor * level * (0.6f + color * 0.8f);
            extraL[i] = value * gl;
            extraR[i] = value * gr;
        }
        route(extraL, extraR, r[LY_FILTER_ROUTE_NOISE] > 0.5f);
    }

    // Voice inserts, per slot, before or after the filters.
    auto runInserts = [&](int position, float *L, float *R) {
        for (int k = 0; k < 2; ++k) {
            const int b = LY_INS1_TYPE + k * LY_INS_STRIDE;
            const int type = (int)std::lround(r[b]);
            if (type <= LY_INS_OFF || type >= LY_INS_COUNT) continue;
            if ((r[b + (LY_INS1_POSITION - LY_INS1_TYPE)] > 0.5f ? 1 : 0) != position) continue;
            const int d = k == 0 ? LY_DST_INS1_AMOUNT : LY_DST_INS2_AMOUNT;
            processInsert(v.insert[k], type, L, R, n,
                          clamp01(p[b + (LY_INS1_AMOUNT - LY_INS1_TYPE)] + m[d]),
                          clamp01(p[b + (LY_INS1_FREQ - LY_INS1_TYPE)] + m[d + 1]),
                          clamp01(p[b + (LY_INS1_MIX - LY_INS1_TYPE)]), v.frequency, s->sampleRate);
        }
    };
    auto anyInsertAt = [&](int position) {
        for (int k = 0; k < 2; ++k) {
            const int b = LY_INS1_TYPE + k * LY_INS_STRIDE;
            const int type = (int)std::lround(r[b]);
            if (type > LY_INS_OFF && type < LY_INS_COUNT && (r[b + (LY_INS1_POSITION - LY_INS1_TYPE)] > 0.5f ? 1 : 0) == position) return true;
        }
        return false;
    };
    // Before the filters they work on what goes into them (everything, with
    // no filter on).
    if (anyInsertAt(0)) {
        if (anyFilter) runInserts(0, wetL, wetR); else runInserts(0, dryL, dryR);
    }

    // Filters: 1 then 2 (serial), or both from the same input (parallel).
    if (anyFilter) {
        auto cutoffHz = [&](float cutoff, float keytrack, float envAmount, float env, float mod) {
            const float value = clamp01(cutoff + mod + envAmount * env + keytrack * (v.note - 60) / 120.f);
            return 20.0 * std::pow(1000.0, (double)value);
        };
        FilterSetup one, two;
        if (f1On) {
            const double hz = cutoffHz(p[LY_FILTER_CUTOFF], p[LY_FILTER_KEYTRACK], p[LY_FILTER_ENVAMT], v.envelope[1].value, m[LY_DST_CUTOFF]);
            v.cutoffHz = (float)std::min(hz, s->sampleRate * 0.45);
            one = makeFilter((int)std::lround(r[LY_FILTER_TYPE]), hz, clamp01(p[LY_FILTER_RES] + m[LY_DST_RES]),
                             clamp01(p[LY_FILTER_DRIVE] + m[LY_DST_DRIVE]), clamp01(p[LY_FILTER_MIX] + m[LY_DST_FILTER_MIX]), s->sampleRate);
        }
        if (f2On) {
            const double hz = cutoffHz(p[LY_F2_CUTOFF], p[LY_F2_KEYTRACK], p[LY_F2_ENVAMT], v.envelope[2].value, m[LY_DST_F2_CUTOFF]);
            v.cutoff2Hz = (float)std::min(hz, s->sampleRate * 0.45);
            two = makeFilter((int)std::lround(r[LY_F2_TYPE]), hz, clamp01(p[LY_F2_RES] + m[LY_DST_F2_RES]),
                             clamp01(p[LY_F2_DRIVE] + m[LY_DST_F2_DRIVE]), clamp01(p[LY_F2_MIX] + m[LY_DST_F2_MIX]), s->sampleRate);
        }
        const bool parallel = r[LY_FILTER_ROUTING] > 0.5f && f1On && f2On;
        float gl = 1, gr = 1;
        const float fpan = clampf(p[LY_FILTER_PAN] + m[LY_DST_FILTER_PAN], -1, 1);
        if (std::fabs(fpan) > 0.001f) { gl = fpan > 0 ? 1.f - fpan : 1.f; gr = fpan < 0 ? 1.f + fpan : 1.f; }
        // FEEDBACK: the filters' output, darkened, saturated and DC-free,
        // back into their input on the next sample.
        const float fbAmount = clamp01(p[LY_FB_AMOUNT] + m[LY_DST_FEEDBACK]);
        const bool fbOn = fbAmount > 0.0005f;
        const float fbGain = fbAmount * 1.25f;
        const float fbDrive = 1.f + p[LY_FB_DRIVE] * 7.f;
        const float fbHz = 150.f * std::pow(100.f, clamp01(p[LY_FB_TONE] + m[LY_DST_FB_TONE]));
        const float fbCoef = 1.f - std::exp(-(float)kTwoPi * std::min(fbHz, (float)s->sampleRate * 0.45f) / (float)s->sampleRate);
        for (int i = 0; i < n; ++i) {
            float in[2] = { wetL[i], wetR[i] };
            for (int c = 0; c < 2; ++c) {
                float x = in[c];
                if (fbOn) x += fbGain * v.feedback[c];
                if (parallel) {
                    x = 0.5f * (v.filter[0][c].process(one, x) + v.filter[1][c].process(two, x)) * 1.4f;
                } else {
                    if (f1On) x = v.filter[0][c].process(one, x);
                    if (f2On) x = v.filter[1][c].process(two, x);
                }
                if (fbOn) {
                    v.feedbackLow[c] += (x - v.feedbackLow[c]) * fbCoef;
                    const float dc = v.feedbackLow[c] - v.feedbackDCX[c] + 0.995f * v.feedbackDCY[c];
                    v.feedbackDCX[c] = v.feedbackLow[c];
                    v.feedbackDCY[c] = flushf(dc);
                    v.feedback[c] = fastTanh(dc * fbDrive);
                } else {
                    v.feedback[c] = 0;
                }
                in[c] = x;
            }
            wetL[i] = in[0] * gl; wetR[i] = in[1] * gr;
        }
    }

    // After the filters they work on the whole voice.
    if (anyInsertAt(1)) {
        for (int i = 0; i < n; ++i) { wetL[i] += dryL[i]; wetR[i] += dryR[i]; dryL[i] = 0; dryR[i] = 0; }
        runInserts(1, wetL, wetR);
    }

    // Amplifier.
    const float sens = clamp01(r[LY_VEL_SENS]);
    const float ampTarget = v.envelope[0].value * ((1.f - sens) + sens * v.velocity) * clampf(1.f + m[LY_DST_AMP], 0.f, 2.f);
    const float step = (ampTarget - v.amp) / n;
    float amp = v.amp;
    for (int i = 0; i < n; ++i) {
        amp += step;
        wetL[i] = (wetL[i] + dryL[i]) * amp;
        wetR[i] = (wetR[i] + dryR[i]) * amp;
    }
    v.amp = ampTarget;
}

bool anyGateHeld(const LYSynth *s) {
    for (const auto &v : s->voices) if (v.active && v.gate) return true;
    return false;
}

void startVoice(LYSynth *s, const Event &e, bool fromArp = false) {
    const int maxVoices = std::max(1, std::min(kMaxVoices, (int)std::lround(s->raw[LY_VOICES])));
    const bool mono = maxVoices == 1;
    const double target = 440.0 * std::pow(2.0, (e.note - 69) / 12.0);
    const float velocity = std::pow(std::max(1, e.velocity & 0xFF) / 127.f, 0.8f);
    const bool glideAlways = s->raw[LY_GLIDE_ALWAYS] > 0.5f;
    const bool glides = s->raw[LY_GLIDE] > 0.001f && (glideAlways || anyGateHeld(s));

    int index = -1;
    if (mono) {
        index = 0;
        Voice &v = s->voices[0];
        if (v.active && v.gate && s->raw[LY_LEGATO] > 0.5f) {
            v.note = e.note; v.targetFrequency = target; v.velocity = velocity;
            v.stepCutoff = e.cutoff; v.stepResonance = e.resonance;
            v.fromArp = fromArp;
            if (!glides) v.frequency = target;
            s->newestVoice = 0;
            s->lastFrequency = target;
            return;
        }
    } else {
        for (int i = 0; i < maxVoices; ++i) if (s->voices[i].active && s->voices[i].note == e.note) { index = i; break; }
        if (index < 0) for (int i = 0; i < maxVoices; ++i) if (!s->voices[i].active) { index = i; break; }
        if (index < 0) {
            uint64_t oldest = UINT64_MAX;
            for (int i = 0; i < maxVoices; ++i) if (!s->voices[i].gate && s->voices[i].age < oldest) { oldest = s->voices[i].age; index = i; }
            if (index < 0) for (int i = 0; i < maxVoices; ++i) if (s->voices[i].age < oldest) { oldest = s->voices[i].age; index = i; }
        }
    }
    Voice &v = s->voices[index];
    const bool wasActive = v.active;
    v.active = true; v.gate = true;
    v.note = e.note; v.velocity = velocity;
    v.age = ++s->voiceClock;
    v.targetFrequency = target;
    v.frequency = glides ? s->lastFrequency : target;
    v.stepCutoff = e.cutoff; v.stepResonance = e.resonance;
    v.channel = e.velocity >> 8;
    v.pressure = 0;
    v.sustained = false;
    v.fromArp = fromArp;
    v.random = s->random.bipolar();
    v.elapsed = 0;
    for (int o = 0; o < 2; ++o) {
        const int b = o == 0 ? LY_OSCA_BASE : LY_OSCB_BASE;
        const float start = s->raw[b + LY_OSC_PHASE];
        const float spread = s->raw[b + LY_OSC_RANDPHASE];
        for (int j = 0; j < kMaxUnison; ++j) {
            double ph = start + spread * s->random.unit();
            v.phase[o][j] = ph - std::floor(ph);
            v.uniRandom[o][j] = s->random.bipolar();
        }
    }
    v.subPhase = 0;
    for (int k = 0; k < 4; ++k) v.envelope[k].gateOn();
    for (int l = 0; l < 4; ++l) v.lfo[l].retrigger(s->random, s->raw[lfoBase(l) + (LY_LFO1_PHASE - LY_LFO1_SHAPE)]);
    if (!wasActive) {
        for (auto &filter : v.filter) for (auto &channel : filter) channel.reset();
        for (auto &insert : v.insert) insert.reset();
        for (int c = 0; c < 2; ++c) v.feedback[c] = v.feedbackLow[c] = v.feedbackDCX[c] = v.feedbackDCY[c] = 0;
        v.noise.reset();
        v.noiseColor = 0;
        v.amp = 0;
        for (int k = 0; k < 4; ++k) v.envelope[k].value = 0;
        std::memset(v.lastA, 0, sizeof(v.lastA));
    }
    s->newestVoice = index;
    s->lastFrequency = target;
}

void releaseVoice(Voice &v) {
    v.gate = false;
    v.sustained = false;
    for (auto &e : v.envelope) e.gateOff();
}

void stopNote(LYSynth *s, int note, int channel, bool fromArp = false) {
    const bool mpe = s->raw[LY_MPE] > 0.5f;
    for (auto &v : s->voices) {
        if (!v.active || !v.gate || v.note != note || v.fromArp != fromArp) continue;
        if (mpe && channel >= 0 && v.channel != channel) continue;
        if (!fromArp && s->sustainPedal) { v.sustained = true; continue; }
        releaseVoice(v);
    }
}

// MARK: - Arpeggiator

bool arpOn(const LYSynth *s) { return s->raw[LY_ARP_ON] > 0.5f; }

void arpReleaseSounding(LYSynth *s) {
    for (int i = 0; i < s->arpSoundingCount; ++i) stopNote(s, s->arpSounding[i], -1, true);
    s->arpSoundingCount = 0;
}

void arpNoteOn(LYSynth *s, int note, int velocity) {
    const bool latch = s->raw[LY_ARP_LATCH] > 0.5f;
    // With latch, a fresh chord (every key had been let go) replaces the old one.
    if (latch && s->keysDown == 0) s->heldCount = 0;
    ++s->keysDown;
    for (int i = 0; i < s->heldCount; ++i) if (s->held[i].note == note) return;
    if (s->heldCount >= kHeldNotes) return;
    const bool wasEmpty = s->heldCount == 0;
    s->held[s->heldCount++] = HeldNote { note, velocity, s->heldOrder++ };
    if (wasEmpty) { s->arpCountdown = 0; s->arpIndex = 0; s->arpDirection = 1; s->arpStep = 0; s->arpFresh = true; }
}

void arpNoteOff(LYSynth *s, int note) {
    s->keysDown = std::max(0, s->keysDown - 1);
    if (s->raw[LY_ARP_LATCH] > 0.5f) return;
    for (int i = 0; i < s->heldCount; ++i) if (s->held[i].note == note) {
        for (int j = i; j < s->heldCount - 1; ++j) s->held[j] = s->held[j + 1];
        --s->heldCount;
        break;
    }
    if (s->heldCount == 0) { arpReleaseSounding(s); s->arpStep = -1; }
}

/// The pattern the arpeggiator walks: held notes in order, across octaves.
int arpSequence(const LYSynth *s, int *notes, int *velocities) {
    HeldNote sorted[kHeldNotes];
    std::copy(s->held, s->held + s->heldCount, sorted);
    const int mode = (int)std::lround(s->raw[LY_ARP_MODE]);
    if (mode == LY_ARP_PLAYED) std::sort(sorted, sorted + s->heldCount, [](const HeldNote &a, const HeldNote &b) { return a.order < b.order; });
    else std::sort(sorted, sorted + s->heldCount, [](const HeldNote &a, const HeldNote &b) { return a.note < b.note; });
    const int octaves = std::max(1, std::min(4, (int)std::lround(s->raw[LY_ARP_OCTAVES])));
    int count = 0;
    for (int o = 0; o < octaves; ++o)
        for (int i = 0; i < s->heldCount; ++i) {
            notes[count] = std::min(127, sorted[i].note + 12 * o);
            velocities[count] = sorted[i].velocity;
            ++count;
        }
    return count;
}

void arpFireStep(LYSynth *s) {
    arpReleaseSounding(s);
    int notes[kHeldNotes * 4], velocities[kHeldNotes * 4];
    const int count = arpSequence(s, notes, velocities);
    if (count == 0) return;
    const int mode = (int)std::lround(s->raw[LY_ARP_MODE]);
    auto play = [s](int note, int velocity) {
        startVoice(s, Event { 0, note, velocity, 0, 1.f, 0.f }, true);
        if (s->arpSoundingCount < kHeldNotes * 4) s->arpSounding[s->arpSoundingCount++] = note;
    };
    if (mode == LY_ARP_CHORD) {
        const int octaves = std::max(1, std::min(4, (int)std::lround(s->raw[LY_ARP_OCTAVES])));
        const int perOctave = count / octaves;
        const int octave = s->arpIndex % octaves;
        for (int i = 0; i < perOctave; ++i) play(notes[octave * perOctave + i], velocities[octave * perOctave + i]);
        s->arpIndex = (s->arpIndex + 1) % octaves;
    } else {
        int index;
        switch (mode) {
        case LY_ARP_DOWN: index = count - 1 - (s->arpIndex % count); s->arpIndex = (s->arpIndex + 1) % count; break;
        case LY_ARP_UPDOWN: {
            if (count == 1) { index = 0; break; }
            index = std::max(0, std::min(count - 1, s->arpIndex));
            if (s->arpIndex + s->arpDirection >= count || s->arpIndex + s->arpDirection < 0) s->arpDirection = -s->arpDirection;
            s->arpIndex += s->arpDirection;
            break;
        }
        case LY_ARP_RANDOM: index = (int)(s->random.unit() * count) % count; break;
        default: index = s->arpIndex % count; s->arpIndex = (s->arpIndex + 1) % count; break;
        }
        play(notes[index], velocities[index]);
    }
    s->arpStep = s->arpStep < 0 ? 0 : s->arpStep + 1;
}

void arpAdvance(LYSynth *s, int n) {
    const bool on = arpOn(s);
    if (!on) {
        if (s->arpWasOn) { arpReleaseSounding(s); s->heldCount = 0; s->keysDown = 0; s->arpStep = -1; }
        s->arpWasOn = false;
        return;
    }
    s->arpWasOn = true;
    if (s->heldCount == 0) return;
    const double stepSamples = syncBeats(s->raw[LY_ARP_RATE]) * 60.0 / std::max(20.f, s->raw[LY_BPM]) * s->sampleRate;
    if (s->arpSoundingCount > 0) {
        s->arpGateLeft -= n;
        if (s->arpGateLeft <= 0) arpReleaseSounding(s);
    }
    if (s->songLocked) {
        // Locked to the song: steps land on the grid (odd steps late by the
        // swing). A chord that lands just after a grid line plays on it;
        // any later waits for the next one.
        const double stepBeats = syncBeats(s->raw[LY_ARP_RATE]);
        const double swingBeats = clamp01(s->raw[LY_ARP_SWING]) * 0.33 * stepBeats;
        auto gridBeat = [&](long k) { return k * stepBeats + ((k & 1) ? swingBeats : 0.0); };
        const long here = (long)std::floor(s->beat / stepBeats);
        if (s->arpFresh || gridBeat(s->arpNextStep) > s->beat + 2 * stepBeats || gridBeat(s->arpNextStep) < s->beat - 2 * stepBeats) {
            const double late = s->beat - gridBeat(here);
            s->arpNextStep = (late >= -1e-9 && late <= 0.15 * stepBeats) ? here : here + 1;
            if (gridBeat(here) > s->beat) s->arpNextStep = here;
            s->arpFresh = false;
        }
        if (s->beat + 1e-9 >= gridBeat(s->arpNextStep)) {
            arpFireStep(s);
            s->arpGateLeft = stepSamples * clampf(s->raw[LY_ARP_GATE], 0.05f, 1.f);
            s->arpNextStep += 1;
        }
        return;
    }
    s->arpFresh = false;
    s->arpCountdown -= n;
    if (s->arpCountdown <= 0) {
        arpFireStep(s);
        // Swing pushes every second step late and pulls the next one in.
        const double swing = clamp01(s->raw[LY_ARP_SWING]) * 0.33 * stepSamples;
        const double length = (s->arpStep % 2 == 0) ? stepSamples + swing : stepSamples - swing;
        s->arpCountdown += length;
        if (s->arpCountdown < 1) s->arpCountdown = length;
        s->arpGateLeft = stepSamples * clampf(s->raw[LY_ARP_GATE], 0.05f, 1.f);
    }
}

/// With switch keys on, the four keys from KEY ROOT choose the performers'
/// pattern and make no sound.
bool isSwitchKey(const LYSynth *s, int note) {
    if (s->raw[LY_PERF_KEYSWITCH] < 0.5f) return false;
    const int root = (int)std::lround(s->raw[LY_PERF_KEYROOT]);
    return note >= root && note < root + LY_PERF_PATTERNS;
}

void noteOnInput(LYSynth *s, const Event &e) {
    if (isSwitchKey(s, e.note)) { s->perfOverride = e.note - (int)std::lround(s->raw[LY_PERF_KEYROOT]); return; }
    if (arpOn(s)) arpNoteOn(s, e.note, e.velocity & 0xFF);
    else startVoice(s, e);
}

void noteOffInput(LYSynth *s, int note, int channel) {
    if (isSwitchKey(s, note)) return;
    if (arpOn(s)) arpNoteOff(s, note);
    else stopNote(s, note, channel);
}

void handleMIDI(LYSynth *s, const Event &e) {
    const int status = e.note & 0xF0;
    const int channel = e.note & 0x0F;
    const int d1 = e.velocity & 0x7F;
    const int d2 = (e.velocity >> 8) & 0x7F;
    switch (status) {
    case 0x90:
        if (d2 > 0) {
            noteOnInput(s, Event { 0, d1, d2 | (channel << 8), 0, 1.f, 0.f });
            break;
        }
        [[fallthrough]];
    case 0x80: noteOffInput(s, d1, channel); break;
    case 0xE0: {
        const float bend = ((d1 | (d2 << 7)) - 8192) / 8192.f;
        if (s->raw[LY_MPE] > 0.5f && channel != 0) s->channelBend[channel] = bend; else s->masterBend = bend;
        break;
    }
    case 0xD0: s->channelPressure[channel] = d1 / 127.f; if (s->raw[LY_MPE] < 0.5f) for (auto &v : s->voices) v.pressure = d1 / 127.f; break;
    case 0xA0: for (auto &v : s->voices) if (v.active && v.note == d1) v.pressure = d2 / 127.f; break;
    case 0xB0:
        if (d1 == 1) s->parameters[LY_MODWHEEL].store(d2 / 127.f, std::memory_order_relaxed);
        else if (d1 == 74) s->channelTimbre[channel] = d2 / 127.f;
        else if (d1 == 64) {
            s->sustainPedal = d2 >= 64;
            if (!s->sustainPedal) for (auto &v : s->voices) if (v.sustained) releaseVoice(v);
        } else if (d1 == 120 || d1 == 123) {
            s->sustainPedal = false;
            s->heldCount = 0; s->keysDown = 0;
            arpReleaseSounding(s);
            for (auto &v : s->voices) if (v.gate || v.sustained) releaseVoice(v);
        }
        break;
    default: break;
    }
}

void fire(LYSynth *s, const Event &e) {
    switch (e.type) {
    case 0: noteOnInput(s, e); break;
    case 1: noteOffInput(s, e.note, -1); break;
    case 3: handleMIDI(s, e); break;
    default:
        s->sustainPedal = false;
        s->heldCount = 0; s->keysDown = 0;
        arpReleaseSounding(s);
        for (auto &v : s->voices) if (v.gate || v.sustained) releaseVoice(v);
        break;
    }
}

int eventOffset(const LYSynth *s, const Event &e, uint64_t blockHost, int frames) {
    if (e.hostTime == 0 || blockHost == 0 || e.hostTime <= blockHost) return 0;
    const double seconds = (double)(e.hostTime - blockHost) / s->ticksPerSecond;
    const double offset = seconds * s->sampleRate;
    return offset >= frames ? frames : (int)std::lround(offset);
}

// MARK: - Effects

void prepareEffects(LYSynth *s) {
    const float sr = (float)s->sampleRate;
    s->hyper.prepare(sr); s->distortion.prepare(sr); s->flanger.prepare(sr); s->phaser.prepare(sr);
    s->chorus.prepare(sr); s->delay.prepare(sr); s->compressor.prepare(sr); s->eq.prepare(sr);
    s->fxFilter.prepare(sr); s->reverb.prepare(sr);
}

void clearEffect(LYSynth *s, int fx) {
    switch (fx) {
    case LY_FX_HYPER: s->hyper.clear(); break;
    case LY_FX_DIST: s->distortion.clear(); break;
    case LY_FX_FLANGER: s->flanger.clear(); break;
    case LY_FX_PHASER: s->phaser.clear(); break;
    case LY_FX_CHORUS: s->chorus.clear(); break;
    case LY_FX_DELAY: s->delay.clear(); break;
    case LY_FX_COMP: s->compressor.clear(); break;
    case LY_FX_EQ: s->eq.clear(); break;
    case LY_FX_FILTER: s->fxFilter.clear(); break;
    default: s->reverb.clear(); break;
    }
}

bool effectOn(const LYSynth *s, int fx) {
    static const int onIDs[LY_FX_COUNT] = { LY_HYPER_ON, LY_DIST_ON, LY_FLANGER_ON, LY_PHASER_ON, LY_CHORUS_ON,
                                            LY_DELAY_ON, LY_COMP_ON, LY_EQ_ON, LY_FXF_ON, LY_REVERB_ON };
    return s->raw[onIDs[fx]] > 0.5f;
}

/// The rack order from the patch; anything missing or repeated falls back
/// to the default order.
void effectOrder(const LYSynth *s, int *order) {
    bool seen[LY_FX_COUNT] = {};
    bool valid = true;
    for (int i = 0; i < LY_FX_COUNT; ++i) {
        const int fx = (int)std::lround(s->raw[LY_FX_ORDER + i]);
        if (fx < 0 || fx >= LY_FX_COUNT || seen[fx]) { valid = false; break; }
        seen[fx] = true;
        order[i] = fx;
    }
    if (!valid) std::copy(kDefaultFXOrder, kDefaultFXOrder + LY_FX_COUNT, order);
}

void processEffects(LYSynth *s, float *L, float *R, int n) {
    const float *p = s->smoothed;
    const float *m = s->fxMod;
    auto P = [&](int id, int dst = LY_DST_NONE) { return clamp01(p[id] + (dst != LY_DST_NONE ? m[dst] : 0.f)); };
    int order[LY_FX_COUNT];
    effectOrder(s, order);
    for (int k = 0; k < LY_FX_COUNT; ++k) {
        const int fx = order[k];
        const bool on = effectOn(s, fx);
        if (!on) {
            if (s->fxWasOn[fx]) clearEffect(s, fx);
            s->fxWasOn[fx] = false;
            s->meters[fx].peak *= 0.9f;
            continue;
        }
        s->fxWasOn[fx] = true;
        switch (fx) {
        case LY_FX_HYPER:
            s->hyper.process(L, R, n, P(LY_HYPER_RATE), P(LY_HYPER_DETUNE, LY_DST_HYPER_DETUNE), P(LY_HYPER_VOICES),
                             P(LY_HYPER_MIX, LY_DST_HYPER_MIX), P(LY_HYPER_DIM_SIZE), P(LY_HYPER_DIM_MIX, LY_DST_DIM_MIX));
            break;
        case LY_FX_DIST:
            s->distortion.process(L, R, n, (int)std::lround(s->raw[LY_DIST_MODE]), P(LY_DIST_DRIVE, LY_DST_DIST_DRIVE),
                                  P(LY_DIST_TONE), P(LY_DIST_MIX, LY_DST_DIST_MIX));
            break;
        case LY_FX_FLANGER:
            s->flanger.process(L, R, n, P(LY_FLANGER_RATE), P(LY_FLANGER_DEPTH, LY_DST_FLANGER_DEPTH),
                               P(LY_FLANGER_FEEDBACK), P(LY_FLANGER_MIX, LY_DST_FLANGER_MIX));
            break;
        case LY_FX_PHASER:
            s->phaser.process(L, R, n, P(LY_PHASER_RATE), P(LY_PHASER_DEPTH), P(LY_PHASER_FREQ, LY_DST_PHASER_FREQ),
                              P(LY_PHASER_FEEDBACK), P(LY_PHASER_MIX, LY_DST_PHASER_MIX));
            break;
        case LY_FX_CHORUS:
            s->chorus.process(L, R, n, P(LY_CHORUS_RATE), P(LY_CHORUS_DELAY), P(LY_CHORUS_DEPTH, LY_DST_CHORUS_DEPTH),
                              P(LY_CHORUS_FEEDBACK), P(LY_CHORUS_TONE), P(LY_CHORUS_MIX, LY_DST_CHORUS_MIX));
            break;
        case LY_FX_DELAY: {
            const double seconds = syncBeats(s->raw[LY_DELAY_TIME]) * 60.0 / std::max(20.f, s->raw[LY_BPM]);
            s->delay.process(L, R, n, (float)seconds, P(LY_DELAY_FEEDBACK, LY_DST_DELAY_FEEDBACK), s->raw[LY_DELAY_PINGPONG] > 0.5f,
                             P(LY_DELAY_WIDTH), P(LY_DELAY_LOWCUT), P(LY_DELAY_HIGHCUT), P(LY_DELAY_MIX, LY_DST_DELAY_MIX));
            break;
        }
        case LY_FX_COMP:
            s->compressor.process(L, R, n, (int)std::lround(s->raw[LY_COMP_MODE]), P(LY_COMP_THRESHOLD), P(LY_COMP_RATIO),
                                  P(LY_COMP_ATTACK), P(LY_COMP_RELEASE), P(LY_COMP_GAIN), P(LY_COMP_DEPTH, LY_DST_COMP_DEPTH),
                                  P(LY_COMP_MIX, LY_DST_COMP_MIX));
            break;
        case LY_FX_EQ:
            s->eq.process(L, R, n, P(LY_EQ_LOW_FREQ), clampf(p[LY_EQ_LOW_GAIN] + m[LY_DST_EQ_LOW], -1, 1),
                          P(LY_EQ_MID_FREQ), clampf(p[LY_EQ_MID_GAIN] + m[LY_DST_EQ_MID], -1, 1), P(LY_EQ_MID_Q),
                          P(LY_EQ_HIGH_FREQ), clampf(p[LY_EQ_HIGH_GAIN] + m[LY_DST_EQ_HIGH], -1, 1));
            break;
        case LY_FX_FILTER:
            s->fxFilter.process(L, R, n, (int)std::lround(s->raw[LY_FXF_TYPE]), P(LY_FXF_CUTOFF, LY_DST_FXF_CUTOFF),
                                P(LY_FXF_RES, LY_DST_FXF_RES), P(LY_FXF_DRIVE), P(LY_FXF_MIX, LY_DST_FXF_MIX));
            break;
        default:
            s->reverb.process(L, R, n, (int)std::lround(s->raw[LY_REVERB_MODE]), P(LY_REVERB_SIZE, LY_DST_REVERB_SIZE),
                              P(LY_REVERB_DECAY, LY_DST_REVERB_DECAY), P(LY_REVERB_DAMP), P(LY_REVERB_WIDTH),
                              P(LY_REVERB_PREDELAY), P(LY_REVERB_MIX, LY_DST_REVERB_MIX));
            break;
        }
        s->meters[fx].chunk(L, R, n);
    }
}

} // namespace

// MARK: - C interface

extern "C" {

LYSynth *lysynth_create(double sampleRate) {
    auto *s = new LYSynth();
    s->sampleRate = sampleRate > 0 ? sampleRate : 44100;
    setDefaults(s);
    buildSmoothing(s);
    for (int i = 0; i < LY_PARAM_COUNT; ++i) {
        s->raw[i] = s->parameters[i].load(std::memory_order_relaxed);
        s->smoothed[i] = s->raw[i];
    }
    for (auto &d : s->display) d.store(0, std::memory_order_relaxed);
    prepareEffects(s);
    lysynth_use_factory_table(s, 0, LY_TABLE_BASIC);
    lysynth_use_factory_table(s, 1, LY_TABLE_BASIC);
    return s;
}

void lysynth_destroy(LYSynth *s) { delete s; }

void lysynth_set_param(LYSynth *s, int id, float value) {
    if (id < 0 || id >= LY_PARAM_COUNT || !std::isfinite(value)) return;
    s->parameters[id].store(value, std::memory_order_relaxed);
}

float lysynth_get_param(const LYSynth *s, int id) {
    if (id < 0 || id >= LY_PARAM_COUNT) return 0;
    return s->parameters[id].load(std::memory_order_relaxed);
}

static void enqueue(LYSynth *s, const Event &e) {
    while (s->producerLock.test_and_set(std::memory_order_acquire)) {}
    const uint32_t w = s->writeIndex.load(std::memory_order_relaxed);
    const uint32_t r = s->readIndex.load(std::memory_order_acquire);
    if (w - r < kQueue) {
        s->queue[w % kQueue] = e;
        s->writeIndex.store(w + 1, std::memory_order_release);
    }
    s->producerLock.clear(std::memory_order_release);
}

void lysynth_note_on(LYSynth *s, int note, int velocity, uint64_t hostTime, float cutoff, float resonance) {
    enqueue(s, Event { 0, std::max(0, std::min(127, note)), velocity, hostTime, cutoff, resonance });
}

void lysynth_note_off(LYSynth *s, int note, uint64_t hostTime) {
    enqueue(s, Event { 1, note, 0, hostTime, 0, 0 });
}

void lysynth_all_notes_off(LYSynth *s) {
    enqueue(s, Event { 2, 0, 0, 0, 0, 0 });
}

void lysynth_midi(LYSynth *s, uint8_t status, uint8_t data1, uint8_t data2, uint64_t hostTime) {
    enqueue(s, Event { 3, status, data1 | (data2 << 8), hostTime, 0, 0 });
}

void lysynth_render(LYSynth *s, float *left, float *right, int frames, uint64_t blockHost) {
    std::memset(left, 0, sizeof(float) * frames);
    std::memset(right, 0, sizeof(float) * frames);

    // Pick up parameters once per block; smooth the continuous ones.
    for (int i = 0; i < LY_PARAM_COUNT; ++i) {
        const float target = s->parameters[i].load(std::memory_order_relaxed);
        s->raw[i] = target;
        s->smoothed[i] = s->smooths[i] ? s->smoothed[i] + (target - s->smoothed[i]) * 0.35f : target;
    }

    // Move newly queued events into the time-ordered pending list.
    const uint32_t w = s->writeIndex.load(std::memory_order_acquire);
    uint32_t r = s->readIndex.load(std::memory_order_relaxed);
    while (r != w) {
        if (s->pendingCount < kPending) s->pending[s->pendingCount++] = s->queue[r % kQueue];
        ++r;
    }
    s->readIndex.store(r, std::memory_order_release);

    // Where the song is: a plug-in's position for this render, an app's
    // transport anchor, or the synth's own clock running at the tempo.
    const double beatsPerSecond = std::max(20.f, s->raw[LY_BPM]) / 60.0;
    const bool wasLocked = s->songLocked;
    if (s->blockPositionValid) {
        s->beat = s->blockBeat;
        s->songLocked = s->blockPlaying;
        s->blockPositionValid = false;
    } else if (blockHost != 0 && s->anchorPlaying.load(std::memory_order_relaxed)) {
        uint32_t version;
        uint64_t host;
        double anchor;
        do {
            version = s->anchorVersion.load(std::memory_order_acquire);
            host = s->anchorHost.load(std::memory_order_relaxed);
            anchor = s->anchorBeat.load(std::memory_order_relaxed);
        } while ((version & 1) || version != s->anchorVersion.load(std::memory_order_acquire));
        const double seconds = blockHost >= host ? (double)(blockHost - host) / s->ticksPerSecond
                                                 : -(double)(host - blockHost) / s->ticksPerSecond;
        s->beat = anchor + seconds * beatsPerSecond;
        s->songLocked = true;
    } else {
        s->songLocked = false;
    }
    if (s->songLocked != wasLocked) s->arpFresh = true;

    // Performer patterns: the patch's, until a switch key picks another; a
    // change to the patch's pattern takes over again.
    for (int k = 0; k < 2; ++k) {
        const int param = std::max(0, std::min((int)LY_PERF_PATTERNS - 1, (int)std::lround(s->raw[LY_PERF1_PATTERN + k * LY_PERF_STRIDE])));
        if (param != s->perfPatternParam[k]) {
            if (s->perfPatternParam[k] >= 0) s->perfOverride = -1;
            s->perfPatternParam[k] = param;
        }
    }
    for (int k = 0; k < 2; ++k) s->perfPattern[k] = s->perfOverride >= 0 ? s->perfOverride : s->perfPatternParam[k];

    const int maxVoices = std::max(1, std::min(kMaxVoices, (int)std::lround(s->raw[LY_VOICES])));
    for (int i = maxVoices; i < kMaxVoices; ++i) {
        if (s->voices[i].gate) { s->voices[i].gate = false; for (auto &e : s->voices[i].envelope) e.gateOff(); }
    }

    int position = 0;
    while (position < frames) {
        // Fire what is due now, and find the next due offset.
        int next = frames;
        for (int i = 0; i < s->pendingCount;) {
            const int offset = eventOffset(s, s->pending[i], blockHost, frames);
            if (offset <= position) {
                fire(s, s->pending[i]);
                s->pending[i] = s->pending[--s->pendingCount];
                continue;
            }
            next = std::min(next, offset);
            ++i;
        }
        const int n = std::min(kChunk, std::min(frames - position, std::max(1, next - position)));

        arpAdvance(s, n);

        for (int l = 0; l < 4; ++l) {
            const int b = lfoBase(l);
            double increment = lfoIncrement(s, l, nullptr, n);
            // Synced and FREE while a transport drives the song: the phase is
            // the bar position, so the LFO lines up with the beat.
            if (s->songLocked && s->raw[b + (LY_LFO1_SYNC - LY_LFO1_SHAPE)] > 0.5f
                && (int)std::lround(s->raw[b + (LY_LFO1_RETRIG - LY_LFO1_SHAPE)]) == LY_LFOMODE_FREE) {
                double target = s->beat / syncBeats(s->raw[b + (LY_LFO1_RATE - LY_LFO1_SHAPE)]);
                target -= std::floor(target);
                increment = target - s->globalLFO[l].phase;
                increment -= std::floor(increment);
            }
            s->globalLFO[l].advance(increment, (int)std::lround(s->raw[b]), s->random,
                                    s->raw + LY_LFO_POINTS_BASE + l * LY_LFO_POINTS, s->raw[b + (LY_LFO1_SMOOTH - LY_LFO1_SHAPE)] > 0.5f,
                                    false, s->raw[b + (LY_LFO1_PHASE - LY_LFO1_SHAPE)]);
        }

        float *outL = left + position, *outR = right + position;
        for (auto &v : s->voices) {
            if (!v.active) continue;
            const float *mod = v.modulation;
            for (int k = 0; k < 4; ++k) {
                const int b = LY_ENV1_A + k * 4;
                const int c = LY_ENV1_ACURVE + k * 3;
                float a = s->smoothed[b], d = s->smoothed[b + 1], rel = s->smoothed[b + 3];
                if (k == 0) { a += mod[LY_DST_ENV1_ATTACK]; d += mod[LY_DST_ENV1_DECAY]; rel += mod[LY_DST_ENV1_RELEASE]; }
                if (k == 1) { a += mod[LY_DST_ENV2_ATTACK]; d += mod[LY_DST_ENV2_DECAY]; rel += mod[LY_DST_ENV2_RELEASE]; }
                v.envelope[k].advance(n, s->sampleRate, clamp01(a), s->raw[LY_ENV1_H + k], clamp01(d), s->raw[b + 2], clamp01(rel),
                                      s->raw[c], s->raw[c + 1], s->raw[c + 2]);
            }
            for (int l = 0; l < 4; ++l) {
                const int b = lfoBase(l);
                const int mode = (int)std::lround(s->raw[b + (LY_LFO1_RETRIG - LY_LFO1_SHAPE)]);
                v.lfo[l].advance(lfoIncrement(s, l, v.modulation, n), (int)std::lround(s->raw[b]), s->random,
                                 s->raw + LY_LFO_POINTS_BASE + l * LY_LFO_POINTS, s->raw[b + (LY_LFO1_SMOOTH - LY_LFO1_SHAPE)] > 0.5f,
                                 mode == LY_LFOMODE_ENV, 0.f);
            }
            v.elapsed += (double)n / s->sampleRate;
            renderVoice(s, v, n);
            for (int i = 0; i < n; ++i) { outL[i] += s->mixL[i]; outR[i] += s->mixR[i]; }
            if (v.envelope[0].stage == 0 && v.amp < 1e-5f) v.active = false;
        }

        // Effects follow the newest voice's modulation, or the global
        // sources alone when nothing is playing.
        const Voice &source = (s->newestVoice >= 0 && s->voices[s->newestVoice].active) ? s->voices[s->newestVoice] : s->idle;
        if (&source == &s->idle) evaluateMatrix(s, s->idle, s->fxMod);
        else std::memcpy(s->fxMod, source.modulation, sizeof(s->fxMod));

        processEffects(s, outL, outR, n);

        const float master = clampf(s->smoothed[LY_MASTER] + s->fxMod[LY_DST_MASTER], 0.f, 1.f);
        for (int i = 0; i < n; ++i) {
            float l = outL[i] * master, rr = outR[i] * master;
            l = fastTanh(l * 0.9f) / 0.9f;
            rr = fastTanh(rr * 0.9f) / 0.9f;
            outL[i] = l; outR[i] = rr;
        }
        position += n;
        s->beat += n * beatsPerSecond / s->sampleRate;
    }

    // Scope and display, for the editor.
    uint32_t sw = s->scopeWrite.load(std::memory_order_relaxed);
    for (int i = 0; i < frames; ++i) s->scope[(sw + i) % kScope] = 0.5f * (left[i] + right[i]);
    s->scopeWrite.store(sw + frames, std::memory_order_release);

    int active = 0;
    for (auto &v : s->voices) active += v.active ? 1 : 0;
    s->display[0].store((float)active, std::memory_order_relaxed);
    const bool hasVoice = s->newestVoice >= 0;
    const Voice &v = hasVoice ? s->voices[s->newestVoice] : s->idle;
    s->display[1].store(v.wavetablePosition[0], std::memory_order_relaxed);
    s->display[2].store(v.wavetablePosition[1], std::memory_order_relaxed);
    for (int k = 0; k < 4; ++k) s->display[3 + k].store(v.envelope[k].value, std::memory_order_relaxed);
    for (int l = 0; l < 4; ++l) {
        const int mode = (int)std::lround(s->raw[lfoBase(l) + (LY_LFO1_RETRIG - LY_LFO1_SHAPE)]);
        const bool perVoice = hasVoice && v.active && mode != LY_LFOMODE_FREE;
        const LFOState &state = perVoice ? v.lfo[l] : s->globalLFO[l];
        s->display[7 + l].store(hasVoice && v.active ? lfoValue(s, v, l) : state.value, std::memory_order_relaxed);
        float phase = (float)state.phase;
        if (!perVoice) { phase += s->raw[lfoBase(l) + (LY_LFO1_PHASE - LY_LFO1_SHAPE)]; phase -= std::floor(phase); }
        s->display[11 + l].store(phase, std::memory_order_relaxed);
    }
    s->display[15].store(v.cutoffHz, std::memory_order_relaxed);
    s->display[16].store(v.cutoff2Hz, std::memory_order_relaxed);
    for (int b = 0; b < 3; ++b) s->display[17 + b].store(s->compressor.gainDb[b], std::memory_order_relaxed);
    for (int f = 0; f < LY_FX_COUNT; ++f) s->display[20 + f].store(s->meters[f].peak, std::memory_order_relaxed);
    s->display[30].store((float)(s->heldCount > 0 && arpOn(s) ? s->arpStep : -1), std::memory_order_relaxed);
    for (int d = 0; d < LY_DST_COUNT; ++d) s->display[40 + d].store(v.active ? v.modulation[d] : s->fxMod[d], std::memory_order_relaxed);
    const int extra = 40 + LY_DST_COUNT;
    for (int k = 0; k < 2; ++k) {
        int step = -1;
        const float value = performerValue(s, k, performerBeat(s, v, k), &step);
        s->display[extra + k].store((float)step, std::memory_order_relaxed);
        s->display[extra + 2 + k].store((float)s->perfPattern[k], std::memory_order_relaxed);
        s->display[extra + 4 + k].store(value, std::memory_order_relaxed);
        s->display[extra + 6 + k].store(trackerInput(s, v, k), std::memory_order_relaxed);
    }
    s->display[extra + 8].store((float)s->beat, std::memory_order_relaxed);
    s->display[extra + 9].store(s->songLocked ? 1.f : 0.f, std::memory_order_relaxed);
}

void lysynth_set_song_position(LYSynth *s, double beat, int playing) {
    if (!std::isfinite(beat)) return;
    s->blockBeat = beat;
    s->blockPlaying = playing != 0;
    s->blockPositionValid = true;
}

void lysynth_set_transport(LYSynth *s, int playing, uint64_t hostTime, double beat) {
    if (!std::isfinite(beat)) return;
    s->anchorVersion.fetch_add(1, std::memory_order_acq_rel);
    s->anchorHost.store(hostTime, std::memory_order_relaxed);
    s->anchorBeat.store(beat, std::memory_order_relaxed);
    s->anchorPlaying.store(playing ? 1 : 0, std::memory_order_relaxed);
    s->anchorVersion.fetch_add(1, std::memory_order_acq_rel);
}

void lysynth_set_wavetable(LYSynth *s, int oscillator, const float *frames, int frameCount) {
    if (oscillator < 0 || oscillator > 1 || frames == nullptr || frameCount < 1) return;
    auto table = buildWavetable(frames, frameCount);
    std::lock_guard<std::mutex> guard(s->tableMutex);
    // The audio thread may still be reading the old table for this block, so
    // it is kept until a later swap rather than freed here.
    if (s->owned[oscillator]) s->retired.push_back(s->owned[oscillator]);
    if (s->retired.size() > 4) s->retired.erase(s->retired.begin(), s->retired.end() - 4);
    s->owned[oscillator] = table;
    s->live[oscillator].store(table.get(), std::memory_order_release);
}

void lysynth_use_factory_table(LYSynth *s, int oscillator, int tableID) {
    if (oscillator < 0 || oscillator > 1 || tableID < 0 || tableID >= LY_TABLE_FACTORY_COUNT) return;
    static std::mutex cacheMutex;
    static std::shared_ptr<Wavetable> cache[LY_TABLE_FACTORY_COUNT];
    std::shared_ptr<Wavetable> table;
    {
        std::lock_guard<std::mutex> guard(cacheMutex);
        if (!cache[tableID]) {
            std::vector<float> frames((size_t)LY_WT_MAX_FRAMES * kSize);
            const int count = lysynth_factory_table(tableID, frames.data(), LY_WT_MAX_FRAMES);
            cache[tableID] = buildWavetable(frames.data(), count);
        }
        table = cache[tableID];
    }
    std::lock_guard<std::mutex> guard(s->tableMutex);
    if (s->owned[oscillator]) s->retired.push_back(s->owned[oscillator]);
    if (s->retired.size() > 4) s->retired.erase(s->retired.begin(), s->retired.end() - 4);
    s->owned[oscillator] = table;
    s->live[oscillator].store(table.get(), std::memory_order_release);
}

void lysynth_get_display(const LYSynth *s, LYSynthDisplay *out) {
    out->activeVoices = (int)s->display[0].load(std::memory_order_relaxed);
    out->wavetablePosition[0] = s->display[1].load(std::memory_order_relaxed);
    out->wavetablePosition[1] = s->display[2].load(std::memory_order_relaxed);
    for (int k = 0; k < 4; ++k) out->envelope[k] = s->display[3 + k].load(std::memory_order_relaxed);
    for (int l = 0; l < 4; ++l) {
        out->lfo[l] = s->display[7 + l].load(std::memory_order_relaxed);
        out->lfoPhase[l] = s->display[11 + l].load(std::memory_order_relaxed);
    }
    out->cutoffHz = s->display[15].load(std::memory_order_relaxed);
    out->cutoff2Hz = s->display[16].load(std::memory_order_relaxed);
    for (int b = 0; b < 3; ++b) out->compGain[b] = s->display[17 + b].load(std::memory_order_relaxed);
    for (int f = 0; f < LY_FX_COUNT; ++f) out->fxLevel[f] = s->display[20 + f].load(std::memory_order_relaxed);
    out->arpStep = (int)s->display[30].load(std::memory_order_relaxed);
    for (int d = 0; d < LY_DST_COUNT; ++d) out->modulation[d] = s->display[40 + d].load(std::memory_order_relaxed);
    const int extra = 40 + LY_DST_COUNT;
    for (int k = 0; k < 2; ++k) {
        out->perfStep[k] = (int)s->display[extra + k].load(std::memory_order_relaxed);
        out->perfPattern[k] = (int)s->display[extra + 2 + k].load(std::memory_order_relaxed);
        out->perfValue[k] = s->display[extra + 4 + k].load(std::memory_order_relaxed);
        out->trackInput[k] = s->display[extra + 6 + k].load(std::memory_order_relaxed);
    }
    out->songBeat = s->display[extra + 8].load(std::memory_order_relaxed);
    out->songLocked = (int)s->display[extra + 9].load(std::memory_order_relaxed);
}

void lysynth_get_scope(const LYSynth *s, float *out, int count) {
    count = std::max(0, std::min(count, kScope));
    const uint32_t w = s->scopeWrite.load(std::memory_order_acquire);
    for (int i = 0; i < count; ++i) out[i] = s->scope[(w - count + i) % kScope];
}

// MARK: - Factory wavetables

int lysynth_factory_table(int id, float *out, int maxFrames) {
    const int frames = std::min(64, std::max(1, maxFrames));
    auto additive = [](float *dst, auto amplitude) {
        for (int i = 0; i < kSize; ++i) dst[i] = 0;
        for (int h = 1; h < 256; ++h) {
            const float a = amplitude(h);
            if (std::fabs(a) < 1e-5f) continue;
            for (int i = 0; i < kSize; ++i) dst[i] += a * std::sin((float)kTwoPi * h * i / kSize);
        }
    };
    const float vowels[5][3] = { {800, 1150, 2900}, {400, 1700, 2600}, {350, 1900, 2800}, {450, 800, 2830}, {325, 700, 2530} };

    for (int f = 0; f < frames; ++f) {
        float *dst = out + (size_t)f * kSize;
        const float x = frames > 1 ? (float)f / (frames - 1) : 0.f;
        switch (id) {
        case LY_TABLE_BASIC: {
            for (int i = 0; i < kSize; ++i) {
                const float p = (float)i / kSize;
                const float sine = std::sin((float)kTwoPi * p);
                const float tri = 1.f - 4.f * std::fabs(p - 0.5f);
                const float saw = 1.f - 2.f * p;
                const float square = p < 0.5f ? 1.f : -1.f;
                const float seg = x * 3.f;
                if (seg < 1) dst[i] = sine + (tri - sine) * seg;
                else if (seg < 2) dst[i] = tri + (saw - tri) * (seg - 1);
                else dst[i] = saw + (square - saw) * (seg - 2);
            }
            break;
        }
        case LY_TABLE_ANALOG: {
            const float bright = 0.02f + x * 0.98f;
            additive(dst, [bright](int h) { return (1.f / h) * std::exp(-(h - 1) * (1.f - bright) * 0.12f) * (h % 7 == 0 ? 0.8f : 1.f); });
            break;
        }
        case LY_TABLE_PWM: {
            const float w = 0.5f - x * 0.47f;
            for (int i = 0; i < kSize; ++i) dst[i] = ((float)i / kSize) < w ? 1.f : -1.f;
            break;
        }
        case LY_TABLE_HARMONIC_SWEEP: {
            const float top = 1.f + x * 63.f;
            additive(dst, [top](int h) { return h <= top ? 1.f / std::sqrt((float)h) : (h < top + 1 ? (top + 1 - h) / std::sqrt((float)h) : 0.f); });
            break;
        }
        case LY_TABLE_FORMANT:
        case LY_TABLE_CHOIR: {
            const float v = x * 4.f;
            const int a = std::min(3, (int)v);
            const float t = v - a;
            float formant[3];
            for (int k = 0; k < 3; ++k) formant[k] = vowels[a][k] + (vowels[a + 1][k] - vowels[a][k]) * t;
            const float base = id == LY_TABLE_CHOIR ? 196.f : 110.f;
            const float width = id == LY_TABLE_CHOIR ? 140.f : 90.f;
            additive(dst, [&](int h) {
                const float hz = base * h;
                float amplitude = 0;
                const float gains[3] = { 1.f, 0.6f, 0.25f };
                for (int k = 0; k < 3; ++k) amplitude += gains[k] * std::exp(-std::pow((hz - formant[k]) / width, 2.f));
                if (id == LY_TABLE_CHOIR && h % 2 == 1) amplitude *= 1.3f;
                return amplitude / std::sqrt((float)h);
            });
            break;
        }
        case LY_TABLE_FM_BELL: {
            const float index = x * 6.f;
            for (int i = 0; i < kSize; ++i) {
                const float p = (float)kTwoPi * i / kSize;
                dst[i] = std::sin(p + index * std::sin(3.f * p));
            }
            break;
        }
        case LY_TABLE_SYNC_SWEEP: {
            const float ratio = 1.f + x * 7.f;
            for (int i = 0; i < kSize; ++i) {
                float p = (float)i / kSize * ratio;
                p -= std::floor(p);
                dst[i] = (1.f - 2.f * p) * (1.f - (float)i / kSize * 0.35f);
            }
            break;
        }
        case LY_TABLE_ORGAN: {
            const float bars[4][9] = {
                {1, 0.9f, 0.8f, 0, 0, 0, 0, 0, 0},
                {1, 0.7f, 0.6f, 0.6f, 0.4f, 0, 0.3f, 0, 0.2f},
                {1, 0.5f, 0.8f, 0.2f, 0.6f, 0.3f, 0.5f, 0.2f, 0.4f},
                {0.6f, 1, 0.9f, 0.8f, 0.7f, 0.6f, 0.6f, 0.5f, 0.5f}
            };
            const int hs[9] = {1, 2, 3, 4, 6, 8, 10, 12, 16};
            const float v = x * 3.f;
            const int a = std::min(2, (int)v);
            const float t = v - a;
            for (int i = 0; i < kSize; ++i) dst[i] = 0;
            for (int k = 0; k < 9; ++k) {
                const float amplitude = bars[a][k] + (bars[a + 1][k] - bars[a][k]) * t;
                for (int i = 0; i < kSize; ++i) dst[i] += amplitude * std::sin((float)kTwoPi * hs[k] * i / kSize);
            }
            break;
        }
        case LY_TABLE_DIGITAL: {
            const float bits = 8.f - x * 6.f;
            const float steps = std::exp2(bits);
            const int hold = 1 + (int)(x * 48.f);
            for (int i = 0; i < kSize; ++i) {
                const int j = (i / hold) * hold;
                const float value = std::sin((float)kTwoPi * j / kSize) * 0.8f + 0.2f * std::sin((float)kTwoPi * 3 * j / kSize);
                dst[i] = std::round(value * steps) / steps;
            }
            break;
        }
        case LY_TABLE_VOID_FOLD: {
            const float drive = 1.f + x * 8.f;
            for (int i = 0; i < kSize; ++i) {
                float value = std::sin((float)kTwoPi * i / kSize) * drive;
                for (int k = 0; k < 6 && std::fabs(value) > 1.f; ++k) value = value > 1.f ? 2.f - value : -2.f - value;
                dst[i] = value;
            }
            break;
        }
        case LY_TABLE_GROWL: {
            const float index = 0.5f + x * 4.f;
            for (int i = 0; i < kSize; ++i) {
                const float p = (float)kTwoPi * i / kSize;
                float value = std::sin(p + index * std::sin(2.f * p) + 0.5f * x * std::sin(5.f * p)) * (1.2f + x);
                for (int k = 0; k < 4 && std::fabs(value) > 1.f; ++k) value = value > 1.f ? 2.f - value : -2.f - value;
                dst[i] = value;
            }
            break;
        }
        case LY_TABLE_SPECTRAL_COMB: {
            const float spacing = 0.05f + x * 0.4f;
            additive(dst, [spacing](int h) { return (1.f / h) * (0.5f + 0.5f * std::cos((float)kTwoPi * h * spacing)); });
            break;
        }
        case LY_TABLE_GLASS:
        default: {
            const int partials[9] = {1, 3, 5, 7, 9, 12, 15, 19, 24};
            additive(dst, [&](int h) {
                for (int k = 0; k < 9; ++k) if (partials[k] == h) {
                    const float centre = x * 8.f;
                    return std::exp(-std::pow((k - centre) / 2.2f, 2.f)) / (1.f + k * 0.15f);
                }
                return 0.f;
            });
            break;
        }
        }
    }
    return frames;
}

} // extern "C"
