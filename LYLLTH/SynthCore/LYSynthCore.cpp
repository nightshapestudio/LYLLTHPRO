// LYLLTH SYNTH realtime core. See LYSynthCore.h for the contract.

#include "LYSynthCore.h"

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
constexpr double kTwoPi = 6.283185307179586476925286766559;

// MARK: - Small helpers

inline float clamp01(float v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
inline float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline float fastTanh(float x) {
    x = clampf(x, -3.f, 3.f);
    const float x2 = x * x;
    return x * (27.f + x2) / (27.f + 9.f * x2);
}
inline double envelopeTime(float p) { return 0.0005 * std::pow(20000.0, (double)clamp01(p)); }

struct Random {
    uint32_t state = 0x9E3779B9u;
    inline uint32_t next() {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5;
        return state;
    }
    inline float bipolar() { return (float)((int32_t)next()) / 2147483648.0f; }
    inline float unit() { return (float)(next() >> 8) / 16777216.0f; }
};

const double kSyncBeats[] = { 16, 8, 4, 3, 2, 1.5, 1, 0.75, 0.5, 0.375, 0.25, 0.1875, 0.125, 1.0 / 12.0, 0.0625 };
constexpr int kSyncCount = sizeof(kSyncBeats) / sizeof(kSyncBeats[0]);

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
    int stage = 0;    // 0 idle, 1 attack, 2 decay, 3 sustain, 4 release
    float value = 0;
    float progress = 0;
    float from = 0;
    inline void gateOn() { stage = 1; progress = 0; from = value; }
    inline void gateOff() { if (stage != 0) { stage = 4; progress = 0; from = value; } }
    inline void reset() { stage = 0; value = 0; progress = 0; from = 0; }
    inline void advance(int n, double sampleRate, float a, float d, float s, float r, float ca, float cd, float cr) {
        switch (stage) {
        case 1:
            progress += (float)(n / (envelopeTime(a) * sampleRate));
            if (progress >= 1.f) { value = 1.f; stage = 2; progress = 0; break; }
            value = from + (1.f - from) * curveShape(progress, ca);
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
    inline void retrigger(Random &random) {
        phase = 0; previous = next; next = random.bipolar(); held = next;
    }
    inline void advance(double increment, int shape, Random &random, const float *points, bool smooth) {
        phase += increment;
        if (phase >= 1.0) {
            phase -= std::floor(phase);
            previous = next;
            next = random.bipolar();
            held = next;
        }
        const float p = (float)phase;
        switch (shape) {
        case LY_LFO_SINE: value = std::sin((float)kTwoPi * p); break;
        case LY_LFO_TRIANGLE: value = 1.f - 4.f * std::fabs(p - 0.5f); break;
        case LY_LFO_SAW_UP: value = 2.f * p - 1.f; break;
        case LY_LFO_SAW_DOWN: value = 1.f - 2.f * p; break;
        case LY_LFO_SQUARE: value = p < 0.5f ? 1.f : -1.f; break;
        case LY_LFO_SAMPLE_HOLD: value = held; break;
        case LY_LFO_CUSTOM: {
            const float position = p * LY_LFO_POINTS;
            const int i = std::min((int)position, LY_LFO_POINTS - 1);
            if (!smooth) { value = points[i]; break; }
            const float t = position - i;
            const float eased = 0.5f - 0.5f * std::cos((float)M_PI * t);
            value = points[i] + (points[(i + 1) % LY_LFO_POINTS] - points[i]) * eased;
            break;
        }
        default: {
            const float t = 0.5f - 0.5f * std::cos((float)M_PI * p);
            value = previous + (next - previous) * t;
            break;
        }
        }
    }
};

struct SVF {
    float ic1 = 0, ic2 = 0;
    inline void reset() { ic1 = ic2 = 0; }
    inline void process(float x, float a1, float a2, float a3, float k, float &lp, float &bp, float &hp) {
        const float v3 = x - ic2;
        const float v1 = a1 * ic1 + a2 * v3;
        const float v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2.f * v1 - ic1;
        ic2 = 2.f * v2 - ic2;
        lp = v2; bp = v1; hp = x - k * v1 - v2;
    }
};

struct Ladder {
    float y[4] = {0, 0, 0, 0};
    inline void reset() { y[0] = y[1] = y[2] = y[3] = 0; }
    inline float process(float x, float g, float feedback) {
        const float input = fastTanh(x - feedback * y[3]);
        y[0] += g * (input - fastTanh(y[0]));
        y[1] += g * (fastTanh(y[0]) - fastTanh(y[1]));
        y[2] += g * (fastTanh(y[1]) - fastTanh(y[2]));
        y[3] += g * (fastTanh(y[2]) - fastTanh(y[3]));
        return y[3];
    }
};

struct Voice {
    bool active = false;
    bool gate = false;
    int note = 60;
    float velocity = 1;
    uint64_t age = 0;
    double frequency = 261.6;
    double targetFrequency = 261.6;
    double phase[2][kMaxUnison] = {};
    double subPhase = 0;
    float lastOscillator[2] = {0, 0};
    float noise = 0;
    float random = 0;
    float stepCutoff = 1, stepResonance = 0;
    int channel = 0;
    float pressure = 0;
    bool sustained = false;
    float bendSemis = 0;
    float amp = 0;
    Envelope envelope[3];
    LFOState lfo[4];
    SVF svf[2][2];
    Ladder ladder[2];
    float modulation[LY_DST_COUNT] = {};
    float wavetablePosition[2] = {0, 0};
    float cutoffHz = 1000;
};

struct Event {
    int type;       // 0 on, 1 off, 2 all off, 3 MIDI message (note = status, velocity = data1 | data2 << 8)
    int note;
    int velocity;
    uint64_t hostTime;
    float cutoff;
    float resonance;
};

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
    uint64_t voiceClock = 0;
    int newestVoice = -1;
    double lastFrequency = 261.6;
    LFOState globalLFO[4];
    Random random;

    // MIDI state, audio thread only.
    float masterBend = 0;          // -1…1
    float channelBend[16] = {};    // -1…1, MPE per-note bend (±48 semitones)
    float channelPressure[16] = {};
    float channelTimbre[16] = {};
    bool sustainPedal = false;

    float scope[kScope] = {};
    std::atomic<uint32_t> scopeWrite { 0 };
    std::atomic<float> display[16 + LY_DST_COUNT];

    float mixL[kChunk], mixR[kChunk];
    float oscL[2][kChunk], oscR[2][kChunk], oscMono[2][kChunk];
};

namespace {

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
    set(LY_NOISE_LEVEL, 0.3f);
    set(LY_FILTER_ON, 1); set(LY_FILTER_TYPE, LY_FILTER_LP24);
    set(LY_FILTER_CUTOFF, 0.8f); set(LY_FILTER_RES, 0.15f); set(LY_FILTER_MIX, 1);
    set(LY_FILTER_ROUTE_A, 1); set(LY_FILTER_ROUTE_B, 1); set(LY_FILTER_ROUTE_SUB, 1); set(LY_FILTER_ROUTE_NOISE, 1);
    const float env[3][4] = { {0.05f, 0.4f, 0.8f, 0.35f}, {0.02f, 0.42f, 0.3f, 0.4f}, {0.02f, 0.42f, 0.3f, 0.4f} };
    for (int e = 0; e < 3; ++e) for (int k = 0; k < 4; ++k) set(LY_ENV1_A + e * 4 + k, env[e][k]);
    for (int l = 0; l < 4; ++l) set(LY_LFO1_RATE + l * 4, 0.4f);
    set(LY_VOICES, 8); set(LY_MASTER, 0.8f); set(LY_BPM, 120);
    for (int e = 0; e < 3; ++e) { set(LY_ENV1_DCURVE + e * 3, -0.55f); set(LY_ENV1_RCURVE + e * 3, -0.55f); }
    for (int l = 0; l < 4; ++l) {
        set(LY_LFO1_SMOOTH + l, 1);
        for (int i = 0; i < LY_LFO_POINTS; ++i)
            set(LY_LFO_POINTS_BASE + l * LY_LFO_POINTS + i, std::sin((float)kTwoPi * i / LY_LFO_POINTS));
    }
    set(LY_BEND_RANGE, 2);
}

inline float readWavetable(const float *table, double phase) {
    const double index = phase * kSize;
    const int i = (int)index;
    const float frac = (float)(index - i);
    return table[i] + (table[i + 1] - table[i]) * frac;
}

inline double warpPhase(int mode, double p, float amount) {
    switch (mode) {
    case LY_WARP_SYNC: {
        const double stretched = p * (1.0 + amount * 7.0);
        return stretched - std::floor(stretched);
    }
    case LY_WARP_BEND_POS: return std::pow(p, std::exp(-amount * 2.0));
    case LY_WARP_BEND_NEG: return std::pow(p, std::exp(amount * 2.0));
    case LY_WARP_MIRROR: {
        const double mirrored = p < 0.5 ? 2 * p : 2 * (1 - p);
        return p + (mirrored * 0.999 - p) * amount;
    }
    case LY_WARP_PWM: {
        const double w = 0.5 - 0.49 * amount;
        return p < w ? p * 0.5 / w : 0.5 + (p - w) * 0.5 / (1 - w);
    }
    default: return p;
    }
}

void renderOscillator(LYSynth *s, Voice &v, int o, int n, const float *m, float baseSemis, const float *modulator) {
    const Wavetable *table = s->live[o].load(std::memory_order_acquire);
    float *outL = s->oscL[o], *outR = s->oscR[o], *mono = s->oscMono[o];
    std::memset(outL, 0, sizeof(float) * n);
    std::memset(outR, 0, sizeof(float) * n);
    std::memset(mono, 0, sizeof(float) * n);
    const int b = o == 0 ? LY_OSCA_BASE : LY_OSCB_BASE;
    const float *p = s->smoothed;
    if (s->raw[b + LY_OSC_ON] < 0.5f || table == nullptr) return;

    const int dOffset = o == 0 ? 0 : (LY_DST_B_LEVEL - LY_DST_A_LEVEL);
    const float level = clamp01(p[b + LY_OSC_LEVEL] + m[LY_DST_A_LEVEL + dOffset]);
    if (level <= 0.0001f) return;
    const float pan = clampf(p[b + LY_OSC_PAN] + m[LY_DST_A_PAN + dOffset] + m[LY_DST_PAN], -1, 1);
    const float position = clamp01(p[b + LY_OSC_WTPOS] + m[LY_DST_A_WTPOS + dOffset]);
    const float detune = clamp01(p[b + LY_OSC_DETUNE] + m[LY_DST_A_DETUNE + dOffset]);
    const float blend = clamp01(p[b + LY_OSC_BLEND] + m[LY_DST_A_BLEND + dOffset]);
    const float width = clamp01(p[b + LY_OSC_WIDTH]);
    const float warp = clamp01(p[b + LY_OSC_WARPAMT] + m[LY_DST_A_WARP + dOffset]);
    const int warpMode = (int)std::lround(s->raw[b + LY_OSC_WARPMODE]);
    const int unison = std::max(1, std::min(kMaxUnison, (int)std::lround(s->raw[b + LY_OSC_UNISON])));
    v.wavetablePosition[o] = position;

    const float semis = baseSemis + 12.f * std::round(s->raw[b + LY_OSC_OCTAVE]) + std::round(s->raw[b + LY_OSC_SEMI])
        + p[b + LY_OSC_FINE] / 100.f + m[LY_DST_A_PITCH + dOffset] * 24.f + m[LY_DST_PITCH] * 24.f + v.bendSemis;
    const double frequency = v.frequency * std::pow(2.0, semis / 12.0);
    const double baseIncrement = frequency / s->sampleRate;
    if (baseIncrement >= 0.5) return;

    int level0 = (int)std::ceil(std::log2(std::max(1.0, baseIncrement * kSize * 1.0)));
    level0 = std::max(0, std::min(kLevels - 1, level0));
    const double framePosition = position * (table->frames - 1);
    const int f0 = (int)framePosition;
    const int f1 = std::min(table->frames - 1, f0 + 1);
    const float ff = (float)(framePosition - f0);
    const float *t0 = table->frame(level0, f0);
    const float *t1 = table->frame(level0, f1);

    float gainL[kMaxUnison], gainR[kMaxUnison];
    double increment[kMaxUnison];
    float gainSum = 0;
    for (int j = 0; j < unison; ++j) {
        const float t = unison == 1 ? 0.f : -1.f + 2.f * j / (unison - 1);
        const float cents = t * detune * detune * 100.f;
        increment[j] = baseIncrement * std::pow(2.0, cents / 1200.0);
        const float g = unison == 1 ? 1.f : 1.f + ((0.15f + 0.85f * blend) - 1.f) * std::fabs(t);
        const float voicePan = clampf(pan + t * width, -1, 1);
        const float angle = (voicePan + 1.f) * 0.25f * (float)M_PI;
        gainL[j] = g * std::cos(angle);
        gainR[j] = g * std::sin(angle);
        gainSum += g * g;
    }
    const float normal = level / std::sqrt(std::max(gainSum, 1e-6f));

    for (int i = 0; i < n; ++i) {
        float sumL = 0, sumR = 0, sumMono = 0;
        const float mod = modulator ? modulator[i] : 0.f;
        for (int j = 0; j < unison; ++j) {
            double ph = v.phase[o][j] + increment[j];
            ph -= std::floor(ph);
            v.phase[o][j] = ph;
            double read = ph;
            if (warpMode == LY_WARP_FM) {
                read = ph + mod * warp * 1.5;
                read -= std::floor(read);
            } else if (warpMode != LY_WARP_OFF && warpMode != LY_WARP_RM && warpMode != LY_WARP_QUANTIZE) {
                read = warpPhase(warpMode, ph, warp);
                read = std::min(std::max(read, 0.0), 0.9999999);
            }
            float value = readWavetable(t0, read);
            if (f1 != f0) value += (readWavetable(t1, read) - value) * ff;
            if (warpMode == LY_WARP_RM) value *= 1.f + (mod - 1.f) * warp;
            else if (warpMode == LY_WARP_QUANTIZE && warp > 0.001f) {
                const float steps = std::exp2(1.f + (1.f - warp) * 7.f);
                value = std::round(value * steps) / steps;
            }
            sumL += value * gainL[j];
            sumR += value * gainR[j];
            sumMono += value;
        }
        outL[i] = sumL * normal;
        outR[i] = sumR * normal;
        mono[i] = sumMono / unison;
    }
    v.lastOscillator[o] = mono[n - 1];
}

inline float sourceValue(const LYSynth *s, const Voice &v, int source) {
    switch (source) {
    case LY_SRC_ENV1: return v.envelope[0].value;
    case LY_SRC_ENV2: return v.envelope[1].value;
    case LY_SRC_ENV3: return v.envelope[2].value;
    case LY_SRC_LFO1: case LY_SRC_LFO2: case LY_SRC_LFO3: case LY_SRC_LFO4: {
        const int l = source - LY_SRC_LFO1;
        const bool retrig = s->raw[LY_LFO1_RETRIG + l * 4] > 0.5f;
        return retrig ? v.lfo[l].value : s->globalLFO[l].value;
    }
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
    default: return 0;
    }
}

double lfoIncrement(const LYSynth *s, int l, const float *m, int n) {
    const float rate = s->smoothed[LY_LFO1_RATE + l * 4];
    double hz;
    if (s->raw[LY_LFO1_SYNC + l * 4] > 0.5f) {
        const int index = std::max(0, std::min(kSyncCount - 1, (int)std::lround(s->raw[LY_LFO1_RATE + l * 4] * (kSyncCount - 1))));
        hz = (std::max(20.f, s->raw[LY_BPM]) / 60.0) / kSyncBeats[index];
    } else {
        hz = 0.02 * std::pow(1500.0, (double)rate);
    }
    if (m) hz *= std::pow(4.0, (double)m[LY_DST_LFO1_RATE + l]);
    return hz * n / s->sampleRate;
}

void renderVoice(LYSynth *s, Voice &v, int n) {
    const float *p = s->smoothed;
    const float *r = s->raw;

    // Modulation for this chunk, from where every source is now.
    float m[LY_DST_COUNT] = {};
    for (int slot = 0; slot < LY_MATRIX_SLOTS; ++slot) {
        const int base = LY_MATRIX_BASE + slot * 3;
        const int source = (int)std::lround(r[base]);
        const int destination = (int)std::lround(r[base + 1]);
        if (source <= LY_SRC_NONE || source >= LY_SRC_COUNT || destination <= LY_DST_NONE || destination >= LY_DST_COUNT) continue;
        m[destination] += p[base + 2] * sourceValue(s, v, source);
    }
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

    // Oscillator B first so A can use it as its FM / ring source.
    renderOscillator(s, v, 1, n, m, 0.f, nullptr);
    renderOscillator(s, v, 0, n, m, 0.f, s->oscMono[1]);

    float *wetL = s->mixL, *wetR = s->mixR;
    float dryL[kChunk] = {}, dryR[kChunk] = {};
    std::memset(wetL, 0, sizeof(float) * n);
    std::memset(wetR, 0, sizeof(float) * n);
    const bool filterOn = r[LY_FILTER_ON] > 0.5f;
    auto route = [&](const float *l, const float *rr, bool toFilter) {
        float *dl = (toFilter && filterOn) ? wetL : dryL;
        float *dr = (toFilter && filterOn) ? wetR : dryR;
        for (int i = 0; i < n; ++i) { dl[i] += l[i]; dr[i] += rr[i]; }
    };
    route(s->oscL[0], s->oscR[0], r[LY_FILTER_ROUTE_A] > 0.5f);
    route(s->oscL[1], s->oscR[1], r[LY_FILTER_ROUTE_B] > 0.5f);

    // Sub and noise, centred.
    float extra[kChunk];
    if (r[LY_SUB_ON] > 0.5f) {
        const float level = clamp01(p[LY_SUB_LEVEL] + m[LY_DST_SUB_LEVEL]);
        const double increment = v.frequency / std::exp2(std::max(1.f, std::round(r[LY_SUB_OCTAVE]))) / s->sampleRate;
        const int shape = (int)std::lround(r[LY_SUB_SHAPE]);
        for (int i = 0; i < n; ++i) {
            v.subPhase += increment; v.subPhase -= std::floor(v.subPhase);
            const float ph = (float)v.subPhase;
            float value;
            if (shape == 0) value = std::sin((float)kTwoPi * ph);
            else if (shape == 1) value = 1.f - 4.f * std::fabs(ph - 0.5f);
            else {
                value = ph < 0.5f ? 1.f : -1.f;
                const float dt = (float)increment;
                auto blep = [dt](float t) {
                    if (t < dt) { t /= dt; return t + t - t * t - 1.f; }
                    if (t > 1.f - dt) { t = (t - 1.f) / dt; return t * t + t + t + 1.f; }
                    return 0.f;
                };
                value += blep(ph);
                float shifted = ph + 0.5f; shifted -= std::floor(shifted);
                value -= blep(shifted);
            }
            extra[i] = value * level * 0.7071f;
        }
        route(extra, extra, r[LY_FILTER_ROUTE_SUB] > 0.5f);
    }
    if (r[LY_NOISE_ON] > 0.5f) {
        const float level = clamp01(p[LY_NOISE_LEVEL] + m[LY_DST_NOISE_LEVEL]);
        const float color = clamp01(p[LY_NOISE_COLOR]);
        const float k = 1.f - color * 0.97f;
        for (int i = 0; i < n; ++i) {
            v.noise += (s->random.bipolar() - v.noise) * k;
            extra[i] = v.noise * level * (0.5f + color);
        }
        route(extra, extra, r[LY_FILTER_ROUTE_NOISE] > 0.5f);
    }

    // Filter.
    if (filterOn) {
        const float keytrack = p[LY_FILTER_KEYTRACK] * (v.note - 60) / 120.f;
        const float cutoff = clamp01(p[LY_FILTER_CUTOFF] + m[LY_DST_CUTOFF] + p[LY_FILTER_ENVAMT] * v.envelope[1].value + keytrack);
        double hz = 20.0 * std::pow(1000.0, (double)cutoff);
        hz = std::min(hz, s->sampleRate * 0.45);
        v.cutoffHz = (float)hz;
        const float res = clamp01(p[LY_FILTER_RES] + m[LY_DST_RES]);
        const float drive = clamp01(p[LY_FILTER_DRIVE] + m[LY_DST_DRIVE]);
        const float mix = clamp01(p[LY_FILTER_MIX] + m[LY_DST_FILTER_MIX]);
        const int type = (int)std::lround(r[LY_FILTER_TYPE]);
        const float preGain = 1.f + drive * 9.f;
        const float postGain = 1.f / std::sqrt(preGain);
        if (type == LY_FILTER_LADDER) {
            const float g = (float)(1.0 - std::exp(-kTwoPi * hz / s->sampleRate));
            const float feedback = res * 3.9f;
            for (int i = 0; i < n; ++i) {
                const float inL = wetL[i] * preGain, inR = wetR[i] * preGain;
                const float outL = v.ladder[0].process(inL, g, feedback) * (1.f + res * 0.8f) * postGain;
                const float outR = v.ladder[1].process(inR, g, feedback) * (1.f + res * 0.8f) * postGain;
                wetL[i] += (outL - wetL[i]) * mix;
                wetR[i] += (outR - wetR[i]) * mix;
            }
        } else {
            const float g = (float)std::tan(M_PI * hz / s->sampleRate);
            const float k = 2.f - 1.97f * res;
            const float a1 = 1.f / (1.f + g * (g + k));
            const float a2 = g * a1;
            const float a3 = g * a2;
            const bool stacked = type == LY_FILTER_LP24 || type == LY_FILTER_HP24;
            const float k2 = stacked ? 2.f - 1.2f * res : k;
            const float b1 = 1.f / (1.f + g * (g + k2));
            const float b2 = g * b1;
            const float b3 = g * b2;
            for (int i = 0; i < n; ++i) {
                float in[2] = { wetL[i], wetR[i] };
                for (int c = 0; c < 2; ++c) {
                    float x = drive > 0.001f ? fastTanh(in[c] * preGain) * postGain * 1.4f : in[c];
                    float lp, bp, hp, y;
                    v.svf[c][0].process(x, a1, a2, a3, k, lp, bp, hp);
                    switch (type) {
                    case LY_FILTER_LP12: y = lp; break;
                    case LY_FILTER_HP12: y = hp; break;
                    case LY_FILTER_BP: y = bp * k; break;
                    case LY_FILTER_NOTCH: y = lp + hp; break;
                    case LY_FILTER_LP24: v.svf[c][1].process(lp, b1, b2, b3, k2, lp, bp, hp); y = lp; break;
                    default: v.svf[c][1].process(hp, b1, b2, b3, k2, lp, bp, hp); y = hp; break;
                    }
                    in[c] += (y - in[c]) * mix;
                }
                wetL[i] = in[0]; wetR[i] = in[1];
            }
        }
    }

    // Amplifier.
    const float ampTarget = v.envelope[0].value * (0.2f + 0.8f * v.velocity) * clampf(1.f + m[LY_DST_AMP], 0.f, 2.f);
    const float step = (ampTarget - v.amp) / n;
    float amp = v.amp;
    for (int i = 0; i < n; ++i) {
        amp += step;
        wetL[i] = (wetL[i] + dryL[i]) * amp;
        wetR[i] = (wetR[i] + dryR[i]) * amp;
    }
    v.amp = ampTarget;
}

void startVoice(LYSynth *s, const Event &e) {
    const int maxVoices = std::max(1, std::min(kMaxVoices, (int)std::lround(s->raw[LY_VOICES])));
    const bool mono = maxVoices == 1;
    const double target = 440.0 * std::pow(2.0, (e.note - 69) / 12.0);
    const float velocity = std::pow(std::max(1, e.velocity & 0xFF) / 127.f, 0.8f);

    int index = -1;
    if (mono) {
        index = 0;
        Voice &v = s->voices[0];
        if (v.active && v.gate && s->raw[LY_LEGATO] > 0.5f) {
            v.note = e.note; v.targetFrequency = target; v.velocity = velocity;
            v.stepCutoff = e.cutoff; v.stepResonance = e.resonance;
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
    v.frequency = (s->raw[LY_GLIDE] > 0.001f) ? s->lastFrequency : target;
    v.stepCutoff = e.cutoff; v.stepResonance = e.resonance;
    v.channel = e.velocity >> 8;
    v.pressure = 0;
    v.sustained = false;
    v.random = s->random.bipolar();
    for (int o = 0; o < 2; ++o) {
        const int b = o == 0 ? LY_OSCA_BASE : LY_OSCB_BASE;
        const float start = s->raw[b + LY_OSC_PHASE];
        const float spread = s->raw[b + LY_OSC_RANDPHASE];
        for (int j = 0; j < kMaxUnison; ++j) {
            double ph = start + spread * s->random.unit();
            v.phase[o][j] = ph - std::floor(ph);
        }
    }
    v.subPhase = 0;
    for (int k = 0; k < 3; ++k) v.envelope[k].gateOn();
    for (int l = 0; l < 4; ++l) v.lfo[l].retrigger(s->random);
    if (!wasActive) {
        for (int c = 0; c < 2; ++c) { v.svf[c][0].reset(); v.svf[c][1].reset(); v.ladder[c].reset(); }
        v.amp = 0;
        for (int k = 0; k < 3; ++k) v.envelope[k].value = 0;
    }
    s->newestVoice = index;
    s->lastFrequency = target;
}

void releaseVoice(Voice &v) {
    v.gate = false;
    v.sustained = false;
    for (auto &e : v.envelope) e.gateOff();
}

void stopNote(LYSynth *s, int note, int channel) {
    const bool mpe = s->raw[LY_MPE] > 0.5f;
    for (auto &v : s->voices) {
        if (!v.active || !v.gate || v.note != note) continue;
        if (mpe && channel >= 0 && v.channel != channel) continue;
        if (s->sustainPedal) { v.sustained = true; continue; }
        releaseVoice(v);
    }
}

void handleMIDI(LYSynth *s, const Event &e) {
    const int status = e.note & 0xF0;
    const int channel = e.note & 0x0F;
    const int d1 = e.velocity & 0x7F;
    const int d2 = (e.velocity >> 8) & 0x7F;
    switch (status) {
    case 0x90:
        if (d2 > 0) {
            startVoice(s, Event { 0, d1, d2 | (channel << 8), 0, 1.f, 0.f });
            break;
        }
        [[fallthrough]];
    case 0x80: stopNote(s, d1, channel); break;
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
            for (auto &v : s->voices) if (v.gate || v.sustained) releaseVoice(v);
        }
        break;
    default: break;
    }
}

void fire(LYSynth *s, const Event &e) {
    switch (e.type) {
    case 0: startVoice(s, e); break;
    case 1: stopNote(s, e.note, -1); break;
    case 3: handleMIDI(s, e); break;
    default:
        s->sustainPedal = false;
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

bool isSmoothed(int id) {
    if (id >= LY_MATRIX_BASE) return (id - LY_MATRIX_BASE) % 3 == 2;
    const int local = id < 2 * LY_OSC_PARAM_COUNT ? id % LY_OSC_PARAM_COUNT : -1;
    if (local >= 0) {
        return local == LY_OSC_LEVEL || local == LY_OSC_PAN || local == LY_OSC_FINE || local == LY_OSC_WTPOS
            || local == LY_OSC_DETUNE || local == LY_OSC_BLEND || local == LY_OSC_WIDTH || local == LY_OSC_WARPAMT;
    }
    switch (id) {
    case LY_SUB_LEVEL: case LY_NOISE_LEVEL: case LY_NOISE_COLOR:
    case LY_FILTER_CUTOFF: case LY_FILTER_RES: case LY_FILTER_DRIVE: case LY_FILTER_KEYTRACK:
    case LY_FILTER_ENVAMT: case LY_FILTER_MIX:
    case LY_LFO1_RATE: case LY_LFO2_RATE: case LY_LFO3_RATE: case LY_LFO4_RATE:
    case LY_MACRO1: case LY_MACRO2: case LY_MACRO3: case LY_MACRO4: case LY_MODWHEEL: case LY_MASTER:
        return true;
    default: return false;
    }
}

} // namespace

// MARK: - C interface

extern "C" {

LYSynth *lysynth_create(double sampleRate) {
    auto *s = new LYSynth();
    s->sampleRate = sampleRate > 0 ? sampleRate : 44100;
    setDefaults(s);
    for (int i = 0; i < LY_PARAM_COUNT; ++i) {
        s->raw[i] = s->parameters[i].load(std::memory_order_relaxed);
        s->smoothed[i] = s->raw[i];
    }
    for (auto &d : s->display) d.store(0, std::memory_order_relaxed);
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
        s->smoothed[i] = isSmoothed(i) ? s->smoothed[i] + (target - s->smoothed[i]) * 0.35f : target;
    }

    // Move newly queued events into the time-ordered pending list.
    const uint32_t w = s->writeIndex.load(std::memory_order_acquire);
    uint32_t r = s->readIndex.load(std::memory_order_relaxed);
    while (r != w) {
        if (s->pendingCount < kPending) s->pending[s->pendingCount++] = s->queue[r % kQueue];
        ++r;
    }
    s->readIndex.store(r, std::memory_order_release);

    const int maxVoices = std::max(1, std::min(kMaxVoices, (int)std::lround(s->raw[LY_VOICES])));
    for (int i = maxVoices; i < kMaxVoices; ++i) {
        if (s->voices[i].gate) { s->voices[i].gate = false; for (auto &e : s->voices[i].envelope) e.gateOff(); }
    }

    const float master = s->smoothed[LY_MASTER];
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

        for (int l = 0; l < 4; ++l)
            s->globalLFO[l].advance(lfoIncrement(s, l, nullptr, n), (int)std::lround(s->raw[LY_LFO1_SHAPE + l * 4]), s->random,
                                    s->raw + LY_LFO_POINTS_BASE + l * LY_LFO_POINTS, s->raw[LY_LFO1_SMOOTH + l] > 0.5f);

        for (auto &v : s->voices) {
            if (!v.active) continue;
            for (int k = 0; k < 3; ++k) {
                const int b = LY_ENV1_A + k * 4;
                const int c = LY_ENV1_ACURVE + k * 3;
                v.envelope[k].advance(n, s->sampleRate, s->smoothed[b], s->smoothed[b + 1], s->raw[b + 2], s->smoothed[b + 3],
                                      s->raw[c], s->raw[c + 1], s->raw[c + 2]);
            }
            for (int l = 0; l < 4; ++l)
                v.lfo[l].advance(lfoIncrement(s, l, v.modulation, n), (int)std::lround(s->raw[LY_LFO1_SHAPE + l * 4]), s->random,
                                 s->raw + LY_LFO_POINTS_BASE + l * LY_LFO_POINTS, s->raw[LY_LFO1_SMOOTH + l] > 0.5f);
            renderVoice(s, v, n);
            for (int i = 0; i < n; ++i) { left[position + i] += s->mixL[i]; right[position + i] += s->mixR[i]; }
            if (v.envelope[0].stage == 0 && v.amp < 1e-5f) v.active = false;
        }

        for (int i = 0; i < n; ++i) {
            float l = left[position + i] * master, rr = right[position + i] * master;
            l = fastTanh(l * 0.9f) / 0.9f;
            rr = fastTanh(rr * 0.9f) / 0.9f;
            left[position + i] = l; right[position + i] = rr;
        }
        position += n;
    }

    // Scope and display, for the editor.
    uint32_t sw = s->scopeWrite.load(std::memory_order_relaxed);
    for (int i = 0; i < frames; ++i) s->scope[(sw + i) % kScope] = 0.5f * (left[i] + right[i]);
    s->scopeWrite.store(sw + frames, std::memory_order_release);

    int active = 0;
    for (auto &v : s->voices) active += v.active ? 1 : 0;
    s->display[0].store((float)active, std::memory_order_relaxed);
    if (s->newestVoice >= 0) {
        const Voice &v = s->voices[s->newestVoice];
        s->display[1].store(v.wavetablePosition[0], std::memory_order_relaxed);
        s->display[2].store(v.wavetablePosition[1], std::memory_order_relaxed);
        for (int k = 0; k < 3; ++k) s->display[3 + k].store(v.envelope[k].value, std::memory_order_relaxed);
        for (int l = 0; l < 4; ++l) {
            const bool retrig = s->raw[LY_LFO1_RETRIG + l * 4] > 0.5f;
            const LFOState &state = retrig ? v.lfo[l] : s->globalLFO[l];
            s->display[6 + l].store(state.value, std::memory_order_relaxed);
            s->display[10 + l].store((float)state.phase, std::memory_order_relaxed);
        }
        s->display[14].store(v.cutoffHz, std::memory_order_relaxed);
        for (int d = 0; d < LY_DST_COUNT; ++d) s->display[16 + d].store(v.active ? v.modulation[d] : 0.f, std::memory_order_relaxed);
    } else {
        for (int l = 0; l < 4; ++l) {
            s->display[6 + l].store(s->globalLFO[l].value, std::memory_order_relaxed);
            s->display[10 + l].store((float)s->globalLFO[l].phase, std::memory_order_relaxed);
        }
    }
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
    for (int k = 0; k < 3; ++k) out->envelope[k] = s->display[3 + k].load(std::memory_order_relaxed);
    for (int l = 0; l < 4; ++l) {
        out->lfo[l] = s->display[6 + l].load(std::memory_order_relaxed);
        out->lfoPhase[l] = s->display[10 + l].load(std::memory_order_relaxed);
    }
    out->cutoffHz = s->display[14].load(std::memory_order_relaxed);
    for (int d = 0; d < LY_DST_COUNT; ++d) out->modulation[d] = s->display[16 + d].load(std::memory_order_relaxed);
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
