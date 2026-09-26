// LUNATK effects rack. Internal to LYSynthCore.cpp; plain C++ with no
// platform code, so a plugin build uses it unchanged.
//
// Every effect is stereo, allocates only in `prepare`, and processes a chunk
// in place. Parameters arrive already mapped to 0…1 (or their stepped
// values) with modulation added.

#pragma once

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

namespace lyfx {

constexpr float kPi = 3.14159265358979f;
constexpr float kTwoPi = 6.28318530717959f;

inline float clamp01(float v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
inline float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline float flush(float v) { return std::fabs(v) < 1e-15f ? 0.f : v; }
inline float softclip(float x) {
    x = clampf(x, -3.f, 3.f);
    const float x2 = x * x;
    return x * (27.f + x2) / (27.f + 9.f * x2);
}
inline float dbToGain(float db) { return std::pow(10.f, db / 20.f); }
inline float gainToDb(float g) { return 20.f * std::log10(std::max(g, 1e-9f)); }

/// A circular buffer read at a fractional delay.
struct DelayLine {
    std::vector<float> data;
    int write = 0;
    void prepare(int length) { data.assign(std::max(4, length), 0.f); write = 0; }
    void clear() { std::fill(data.begin(), data.end(), 0.f); }
    inline void push(float x) { data[write] = x; write = (write + 1) % (int)data.size(); }
    /// `delay` in samples, at least 1.
    inline float read(float delay) const {
        const int size = (int)data.size();
        delay = clampf(delay, 1.f, (float)size - 2.f);
        float position = (float)write - delay;
        while (position < 0) position += size;
        const int i = (int)position;
        const float f = position - i;
        const float a = data[i % size], b = data[(i + 1) % size];
        return a + (b - a) * f;
    }
};

/// Zero-delay-feedback state variable filter.
struct SVF {
    float ic1 = 0, ic2 = 0;
    float a1 = 0, a2 = 0, a3 = 0, k = 2;
    void reset() { ic1 = ic2 = 0; }
    void set(float hz, float q, float sampleRate) {
        const float g = std::tan(kPi * clampf(hz, 10.f, sampleRate * 0.45f) / sampleRate);
        k = 1.f / std::max(q, 0.05f);
        a1 = 1.f / (1.f + g * (g + k));
        a2 = g * a1;
        a3 = g * a2;
    }
    inline void process(float x, float &lp, float &bp, float &hp) {
        const float v3 = x - ic2;
        const float v1 = a1 * ic1 + a2 * v3;
        const float v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = flush(2.f * v1 - ic1);
        ic2 = flush(2.f * v2 - ic2);
        lp = v2; bp = v1; hp = x - k * v1 - v2;
    }
};

/// RBJ biquad, transposed direct form II.
struct Biquad {
    float b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0;
    void reset() { z1 = z2 = 0; }
    inline float process(float x) {
        const float y = b0 * x + z1;
        z1 = flush(b1 * x - a1 * y + z2);
        z2 = flush(b2 * x - a2 * y);
        return y;
    }
    void lowShelf(float hz, float db, float sr) { shelf(hz, db, sr, true); }
    void highShelf(float hz, float db, float sr) { shelf(hz, db, sr, false); }
    void shelf(float hz, float db, float sr, bool low) {
        const float A = std::pow(10.f, db / 40.f);
        const float w = kTwoPi * clampf(hz, 10.f, sr * 0.45f) / sr;
        const float cw = std::cos(w), sw = std::sin(w);
        const float alpha = sw / 2.f * std::sqrt(2.f);
        const float s = 2.f * std::sqrt(A) * alpha;
        float B0, B1, B2, A0, A1, A2;
        if (low) {
            B0 = A * ((A + 1) - (A - 1) * cw + s); B1 = 2 * A * ((A - 1) - (A + 1) * cw); B2 = A * ((A + 1) - (A - 1) * cw - s);
            A0 = (A + 1) + (A - 1) * cw + s; A1 = -2 * ((A - 1) + (A + 1) * cw); A2 = (A + 1) + (A - 1) * cw - s;
        } else {
            B0 = A * ((A + 1) + (A - 1) * cw + s); B1 = -2 * A * ((A - 1) + (A + 1) * cw); B2 = A * ((A + 1) + (A - 1) * cw - s);
            A0 = (A + 1) - (A - 1) * cw + s; A1 = 2 * ((A - 1) - (A + 1) * cw); A2 = (A + 1) - (A - 1) * cw - s;
        }
        b0 = B0 / A0; b1 = B1 / A0; b2 = B2 / A0; a1 = A1 / A0; a2 = A2 / A0;
    }
    void peak(float hz, float db, float q, float sr) {
        const float A = std::pow(10.f, db / 40.f);
        const float w = kTwoPi * clampf(hz, 10.f, sr * 0.45f) / sr;
        const float alpha = std::sin(w) / (2.f * std::max(q, 0.05f));
        const float cw = std::cos(w);
        const float A0 = 1 + alpha / A;
        b0 = (1 + alpha * A) / A0; b1 = -2 * cw / A0; b2 = (1 - alpha * A) / A0;
        a1 = -2 * cw / A0; a2 = (1 - alpha / A) / A0;
    }
};

/// Tracks a chunk's peak so the editor can light each effect.
struct Meter {
    float peak = 0;
    inline void chunk(const float *l, const float *r, int n) {
        float p = 0;
        for (int i = 0; i < n; ++i) p = std::max(p, std::max(std::fabs(l[i]), std::fabs(r[i])));
        peak = std::max(p, peak * 0.97f);
    }
};

// MARK: - HYPER / DIMENSION

/// HYPER: up to seven detuned, modulated copies spread across the stereo
/// field, the unison of a whole patch at once. DIMENSION widens by feeding
/// each side a short, differently delayed copy of the other.
struct Hyper {
    DelayLine line[2], dim[2];
    float phase[7] = {};
    float sampleRate = 44100;
    void prepare(float sr) {
        sampleRate = sr;
        for (int c = 0; c < 2; ++c) { line[c].prepare((int)(sr * 0.06f)); dim[c].prepare((int)(sr * 0.06f)); }
        for (int i = 0; i < 7; ++i) phase[i] = i / 7.f;
    }
    void clear() { for (int c = 0; c < 2; ++c) { line[c].clear(); dim[c].clear(); } }
    void process(float *L, float *R, int n, float rate, float detune, float voices, float mix, float dimSize, float dimMix) {
        const int count = 1 + (int)std::lround(clamp01(voices) * 6.f);
        const float hz = 0.1f + rate * rate * 6.f;
        const float depth = detune * 0.0045f * sampleRate;
        const float base = 0.008f * sampleRate;
        for (int i = 0; i < n; ++i) {
            line[0].push(L[i]); line[1].push(R[i]);
            float wl = 0, wr = 0;
            for (int v = 0; v < count; ++v) {
                phase[v] += hz * (1.f + 0.173f * v) / sampleRate;
                if (phase[v] >= 1.f) phase[v] -= 1.f;
                const float d = base + v * 0.0011f * sampleRate + depth * (0.5f + 0.5f * std::sin(kTwoPi * phase[v]));
                const float pan = count == 1 ? 0.f : -1.f + 2.f * v / (count - 1);
                const float s = 0.5f * (line[0].read(d) + line[1].read(d * 1.013f));
                wl += s * (0.5f - 0.5f * pan);
                wr += s * (0.5f + 0.5f * pan);
            }
            const float norm = 1.4f / std::sqrt((float)count);
            float l = L[i] + (wl * norm - L[i]) * mix;
            float r = R[i] + (wr * norm - R[i]) * mix;
            if (dimMix > 0.001f) {
                dim[0].push(l); dim[1].push(r);
                const float dl = dim[1].read((0.006f + 0.02f * dimSize) * sampleRate);
                const float dr = dim[0].read((0.009f + 0.027f * dimSize) * sampleRate);
                const float g = dimMix * 0.7f;
                l = (l + dl * g) / (1.f + g * 0.5f);
                r = (r + dr * g) / (1.f + g * 0.5f);
            }
            L[i] = l; R[i] = r;
        }
    }
};

// MARK: - DISTORTION

struct Distortion {
    float held[2] = {}, holdCount = 0, tone[2] = {}, dcIn[2] = {}, dcOut[2] = {};
    float sampleRate = 44100;
    void prepare(float sr) { sampleRate = sr; }
    void clear() { held[0] = held[1] = 0; tone[0] = tone[1] = 0; holdCount = 0; dcIn[0] = dcIn[1] = dcOut[0] = dcOut[1] = 0; }
    static inline float shape(int mode, float x) {
        switch (mode) {
        case 0: return softclip(x + 0.15f * x * x);                              // TUBE: even harmonics
        case 1: return softclip(x);                                                 // SOFT
        case 2: return clampf(x, -1.f, 1.f);                                        // HARD
        case 3: return x > 0 ? softclip(x) : softclip(x * 0.25f) * 0.4f;             // DIODE
        case 4: {                                                                   // LIN FOLD
            float y = x;
            for (int k = 0; k < 8 && std::fabs(y) > 1.f; ++k) y = y > 1.f ? 2.f - y : -2.f - y;
            return y;
        }
        case 5: return std::sin(x * 0.5f * kPi);                                    // SIN FOLD
        case 6: return clampf(x * std::fabs(x), -1.f, 1.f);                         // ZERO-SQUARE
        case 9: return softclip(std::fabs(x) * 1.2f);                               // RECTIFY (the DC blocker centres it)
        default: return x;
        }
    }
    void process(float *L, float *R, int n, int mode, float drive, float toneAmt, float mix) {
        const float gain = dbToGain(drive * 36.f);
        const float cutoff = 400.f * std::pow(50.f, toneAmt);
        const float coef = 1.f - std::exp(-kTwoPi * cutoff / sampleRate);
        const float makeup = mode == 7 || mode == 8 ? 1.f : 1.f / (1.f + drive * 0.6f);
        const float holdLength = 1.f + drive * 40.f;
        const float steps = std::exp2(12.f - drive * 10.f);
        float *io[2] = { L, R };
        for (int i = 0; i < n; ++i) {
            bool resample = false;
            if (mode == 7) { holdCount += 1.f; if (holdCount >= holdLength) { holdCount -= holdLength; resample = true; } }
            for (int c = 0; c < 2; ++c) {
                const float x = io[c][i];
                float y;
                if (mode == 7) { if (resample) held[c] = x; y = held[c]; }
                else if (mode == 8) y = std::round(x * steps) / steps;
                else y = shape(mode, x * gain);
                tone[c] += (y - tone[c]) * coef;
                tone[c] = flush(tone[c]);
                // DC blocker: asymmetric shapes (tube, diode, rectify) push the
                // signal off centre, which the stages after would amplify.
                const float blocked = tone[c] - dcIn[c] + 0.9985f * dcOut[c];
                dcIn[c] = tone[c]; dcOut[c] = flush(blocked);
                io[c][i] = x + (blocked * makeup - x) * mix;
            }
        }
    }
};

// MARK: - FLANGER, PHASER, CHORUS

struct Flanger {
    DelayLine line[2];
    float phase = 0, fb[2] = {};
    float sampleRate = 44100;
    void prepare(float sr) { sampleRate = sr; for (auto &l : line) l.prepare((int)(sr * 0.02f)); }
    void clear() { for (auto &l : line) l.clear(); fb[0] = fb[1] = 0; }
    void process(float *L, float *R, int n, float rate, float depth, float feedback, float mix) {
        const float hz = 0.02f + rate * rate * 5.f;
        const float fbk = (feedback * 2.f - 1.f) * 0.92f;
        float *io[2] = { L, R };
        for (int i = 0; i < n; ++i) {
            phase += hz / sampleRate; if (phase >= 1) phase -= 1;
            for (int c = 0; c < 2; ++c) {
                const float lfo = 0.5f + 0.5f * std::sin(kTwoPi * (phase + c * 0.25f));
                const float d = (0.0003f + depth * 0.006f * lfo) * sampleRate;
                const float x = io[c][i];
                line[c].push(x + fb[c] * fbk);
                const float wet = line[c].read(d);
                fb[c] = flush(wet);
                io[c][i] = x * (1.f - mix) + 0.5f * (x + wet) * mix * 1.4f;
            }
        }
    }
};

struct Phaser {
    float state[2][6] = {}, fb[2] = {}, phase = 0;
    float sampleRate = 44100;
    void prepare(float sr) { sampleRate = sr; }
    void clear() { std::memset(state, 0, sizeof(state)); fb[0] = fb[1] = 0; }
    void process(float *L, float *R, int n, float rate, float depth, float freq, float feedback, float mix) {
        const float hz = 0.02f + rate * rate * 6.f;
        const float centre = 100.f * std::pow(80.f, freq);
        float *io[2] = { L, R };
        for (int i = 0; i < n; ++i) {
            phase += hz / sampleRate; if (phase >= 1) phase -= 1;
            for (int c = 0; c < 2; ++c) {
                const float lfo = std::sin(kTwoPi * (phase + c * 0.25f));
                const float f = clampf(centre * std::exp2(lfo * depth * 3.f), 30.f, sampleRate * 0.45f);
                const float t = std::tan(kPi * f / sampleRate);
                const float a = (t - 1.f) / (t + 1.f);
                const float x = io[c][i];
                float y = x + fb[c] * feedback * 0.85f;
                for (int s = 0; s < 6; ++s) {
                    const float out = a * y + state[c][s];
                    state[c][s] = flush(y - a * out);
                    y = out;
                }
                fb[c] = flush(y);
                io[c][i] = x * (1.f - mix * 0.5f) + y * mix * 0.5f;
            }
        }
    }
};

struct Chorus {
    DelayLine line[2];
    float phase = 0, fb[2] = {}, lp[2] = {};
    float sampleRate = 44100;
    void prepare(float sr) { sampleRate = sr; for (auto &l : line) l.prepare((int)(sr * 0.08f)); }
    void clear() { for (auto &l : line) l.clear(); fb[0] = fb[1] = lp[0] = lp[1] = 0; }
    void process(float *L, float *R, int n, float rate, float delay, float depth, float feedback, float tone, float mix) {
        const float hz = 0.05f + rate * rate * 5.f;
        const float base = (0.004f + delay * 0.026f) * sampleRate;
        const float swing = depth * base * 0.45f;
        const float coef = 1.f - std::exp(-kTwoPi * (800.f * std::pow(25.f, tone)) / sampleRate);
        float *io[2] = { L, R };
        for (int i = 0; i < n; ++i) {
            phase += hz / sampleRate; if (phase >= 1) phase -= 1;
            for (int c = 0; c < 2; ++c) {
                const float x = io[c][i];
                line[c].push(x + fb[c] * feedback * 0.8f);
                const float a = line[c].read(base + swing * std::sin(kTwoPi * (phase + c * 0.33f)));
                const float b = line[c].read(base * 1.37f + swing * std::sin(kTwoPi * (phase + 0.5f + c * 0.33f)));
                float wet = 0.5f * (a + b);
                lp[c] += (wet - lp[c]) * coef; lp[c] = flush(lp[c]);
                wet = lp[c];
                fb[c] = flush(wet);
                io[c][i] = x * (1.f - mix) + (x + wet) * 0.7f * mix;
            }
        }
    }
};

/// The NIGHTSHAPE track chorus (DrumKit's CHORUS, modelled on the Juno's
/// chorus), ported sample for sample: one modulated delay per side, the two
/// LFOs apart by WIDTH, a dark wet path with a slow drift and soft
/// saturation, and a little of each side fed to the other. `mode` 1–3 is
/// SUBTLE, WIDE, DEEP; `rateHz` 0.05–3.5.
struct JunoChorus {
    std::vector<float> bufferL, bufferR;
    int size = 0, writeIndex = 0;
    double phaseL = 0, phaseR = 0.25, driftPhase = 0;
    float rate = 0.42f, depth = 0, width = 0, mix = 0;
    float delayMs = 7, bandwidthHz = 8000, character = 0;
    float lpL = 0, lpR = 0;
    float sampleRate = 44100, smoothCoeff = 0;

    void prepare(float sr) {
        sampleRate = sr;
        size = (int)(sr * 0.045f) + 8;
        bufferL.assign(size, 0.f); bufferR.assign(size, 0.f);
        smoothCoeff = (float)std::exp(-1.0 / (sr * 0.020));
        clear();
    }
    void clear() {
        std::fill(bufferL.begin(), bufferL.end(), 0.f);
        std::fill(bufferR.begin(), bufferR.end(), 0.f);
        writeIndex = 0; lpL = lpR = 0;
        phaseL = 0; phaseR = 0.25; driftPhase = 0;
        depth = width = mix = 0;
    }
    inline float smooth(float current, float target) const { return flush(smoothCoeff * current + (1.f - smoothCoeff) * target); }
    inline float readAt(const std::vector<float> &buffer, double delaySamples) const {
        const double clamped = std::min(std::max(delaySamples, 1.0), (double)(size - 3));
        const int whole = (int)clamped;
        const float frac = (float)(clamped - whole);
        const int index0 = (writeIndex - whole + size * 2) % size;
        const int index1 = (index0 - 1 + size) % size;
        return buffer[index0] * (1.f - frac) + buffer[index1] * frac;
    }
    static inline float softLimit(float x) { return x / (1.f + std::fabs(x) * 0.35f); }

    void process(float *L, float *R, int n, int mode, float rateHz, float depthTarget, float widthTarget, float mixTarget) {
        float baseDelay, depthMs, phaseSpread, bandwidth, characterTarget;
        switch (mode) {
        case 1: baseDelay = 7.0f; depthMs = 1.1f; phaseSpread = 0.25f; bandwidth = 8400; characterTarget = 0.18f; break;
        case 2: baseDelay = 8.8f; depthMs = 2.6f; phaseSpread = 0.50f; bandwidth = 7600; characterTarget = 0.34f; break;
        default: baseDelay = 11.5f; depthMs = 4.2f; phaseSpread = 0.42f; bandwidth = 6900; characterTarget = 0.52f; break;
        }
        const double spread = 0.08 + widthTarget * phaseSpread;
        for (int i = 0; i < n; ++i) {
            rate = smooth(rate, rateHz);
            depth = smooth(depth, depthTarget);
            width = smooth(width, widthTarget);
            mix = smooth(mix, mixTarget);
            delayMs = smooth(delayMs, baseDelay);
            bandwidthHz = smooth(bandwidthHz, bandwidth);
            character = smooth(character, characterTarget);

            const float dryL = L[i], dryR = R[i];
            const float mono = (dryL + dryR) * 0.5f;
            const float writeL = dryL * 0.88f + mono * 0.12f;
            const float writeR = dryR * 0.88f + mono * 0.12f;

            driftPhase += kTwoPi * 0.031 / sampleRate;
            if (driftPhase >= kTwoPi) driftPhase -= kTwoPi;
            const double drift = 1.0 + character * 0.035 * std::sin(driftPhase);
            const double hz = std::max(0.03, rate * drift);
            phaseL += hz / sampleRate;
            phaseR = phaseL + spread;
            if (phaseL >= 1.0) phaseL -= std::floor(phaseL);

            const double swing = (double)depth * depthMs;
            const double leftDelay = std::max(0.25, delayMs + std::sin(phaseL * kTwoPi) * swing);
            const double rightDelay = std::max(0.25, delayMs + std::sin(phaseR * kTwoPi) * swing);
            float wetL = readAt(bufferL, leftDelay * sampleRate / 1000.0);
            float wetR = readAt(bufferR, rightDelay * sampleRate / 1000.0);

            const float coef = 1.f - (float)std::exp(-kTwoPi * std::min(std::max(bandwidthHz, 1000.f), 16000.f) / sampleRate);
            lpL = flush(lpL + coef * (wetL - lpL));
            lpR = flush(lpR + coef * (wetR - lpR));
            wetL = softLimit(lpL * (1.f + character * 0.35f));
            wetR = softLimit(lpR * (1.f + character * 0.35f));

            const float cross = (1.f - width) * 0.18f;
            const float spreadL = wetL * (1.f - cross) + wetR * cross;
            const float spreadR = wetR * (1.f - cross) + wetL * cross;

            bufferL[writeIndex] = writeL;
            bufferR[writeIndex] = writeR;
            if (++writeIndex >= size) writeIndex = 0;

            L[i] = dryL * (1.f - mix) + spreadL * mix;
            R[i] = dryR * (1.f - mix) + spreadR * mix;
        }
    }
};

// MARK: - VOCODER

/// A channel vocoder. The synth is the carrier; the sidechain input is the
/// modulator. Both are split into the same log-spaced bands (100 Hz–8 kHz,
/// two band-passes each); the input's level in each band shapes the synth's
/// band. SHIFT moves the carrier bands against the input's for a smaller or
/// bigger throat; HIGHS lets the input's sibilance through.
struct Vocoder {
    struct Coef { float b0 = 0, a1 = 0, a2 = 0; };           // constant-peak band-pass: b1 = 0, b2 = -b0
    struct State { float z1 = 0, z2 = 0; };
    static inline float run(const Coef &c, State &s, float x) {
        const float y = c.b0 * x + s.z1;
        s.z1 = -c.a1 * y + s.z2;
        s.z2 = -c.b0 * x - c.a2 * y;
        return y;
    }
    float sampleRate = 44100;
    int designedBands = -1;
    float designedShift = -9, designedQ = -9;
    Coef modCoef[LY_VOC_MAX_BANDS], carCoef[LY_VOC_MAX_BANDS];
    State mod[LY_VOC_MAX_BANDS][2], car[LY_VOC_MAX_BANDS][2][2];
    float envelope[LY_VOC_MAX_BANDS] = {};
    float hpX[2] = {}, hpY[2] = {};
    float level[LY_VOC_MAX_BANDS] = {};

    void prepare(float sr) { sampleRate = sr; designedBands = -1; clear(); }
    void clear() {
        for (auto &b : mod) for (auto &s : b) s = State();
        for (auto &b : car) for (auto &c : b) for (auto &s : c) s = State();
        for (auto &e : envelope) e = 0;
        for (auto &l : level) l = 0;
        hpX[0] = hpX[1] = hpY[0] = hpY[1] = 0;
    }
    Coef bandPass(float hz, float q) const {
        hz = std::min(std::max(hz, 20.f), sampleRate * 0.45f);
        const float w = kTwoPi * hz / sampleRate;
        const float alpha = std::sin(w) / (2.f * q);
        const float a0 = 1.f + alpha;
        Coef c;
        c.b0 = alpha / a0;
        c.a1 = -2.f * std::cos(w) / a0;
        c.a2 = (1.f - alpha) / a0;
        return c;
    }
    void design(int bands, float shift, float q) {
        if (bands == designedBands && std::fabs(shift - designedShift) < 1e-4f && std::fabs(q - designedQ) < 1e-4f) return;
        designedBands = bands; designedShift = shift; designedQ = q;
        const float quality = 2.f + q * 14.f;
        for (int i = 0; i < bands; ++i) {
            const float hz = 100.f * std::pow(80.f, bands > 1 ? (float)i / (bands - 1) : 0.f);
            modCoef[i] = bandPass(hz, quality);
            carCoef[i] = bandPass(hz * std::pow(2.f, shift), quality);
        }
    }
    /// In place on L/R (the carrier). `inL`/`inR` is the modulator.
    void process(float *L, float *R, const float *inL, const float *inR, int n, int bands, float attack, float release,
                 float shift, float q, float highs, float gain, float mix) {
        bands = std::max(8, std::min((int)LY_VOC_MAX_BANDS, bands));
        design(bands, shift, q);
        const float attackCoef = 1.f - std::exp(-1.f / (0.001f * std::pow(50.f, attack) * sampleRate));
        const float releaseCoef = 1.f - std::exp(-1.f / (0.01f * std::pow(50.f, release) * sampleRate));
        const float inputGain = std::pow(10.f, (-12.f + gain * 36.f) / 20.f);
        const float hpCoef = std::exp(-kTwoPi * 6000.f / sampleRate);
        // A broadband carrier split into n bands, shaped by n envelopes, lands
        // around the product of the two levels; this brings it back up.
        const float makeup = 6.f;
        for (int i = 0; i < n; ++i) {
            const float m = 0.5f * (inL[i] + inR[i]) * inputGain;
            float outL = 0, outR = 0;
            for (int b = 0; b < bands; ++b) {
                const float band = run(modCoef[b], mod[b][1], run(modCoef[b], mod[b][0], m));
                const float rectified = std::fabs(band);
                float &e = envelope[b];
                e += (rectified - e) * (rectified > e ? attackCoef : releaseCoef);
                e = flush(e);
                outL += run(carCoef[b], car[b][0][1], run(carCoef[b], car[b][0][0], L[i])) * e;
                outR += run(carCoef[b], car[b][1][1], run(carCoef[b], car[b][1][0], R[i])) * e;
            }
            // The input's own highs (above ~6 kHz) for consonants.
            float sib = 0;
            for (int c = 0; c < 1; ++c) {
                const float y = hpCoef * (hpY[c] + m - hpX[c]);
                hpX[c] = m; hpY[c] = flush(y);
                sib = y;
            }
            const float vocL = outL * makeup + sib * highs;
            const float vocR = outR * makeup + sib * highs;
            L[i] = L[i] * (1.f - mix) + vocL * mix;
            R[i] = R[i] * (1.f - mix) + vocR * mix;
        }
        for (int b = 0; b < bands; ++b) level[b] = envelope[b];
        for (int b = bands; b < LY_VOC_MAX_BANDS; ++b) level[b] = 0;
    }
};

// MARK: - DELAY

struct Delay {
    DelayLine line[2];
    float hp[2] = {}, lp[2] = {};
    float timeL = 0, timeR = 0;
    float sampleRate = 44100;
    void prepare(float sr) { sampleRate = sr; for (auto &l : line) l.prepare((int)(sr * 4.2f)); timeL = timeR = 0; }
    void clear() { for (auto &l : line) l.clear(); hp[0] = hp[1] = lp[0] = lp[1] = 0; }
    /// `seconds` is the left time; `width` stretches the right against it.
    void process(float *L, float *R, int n, float seconds, float feedback, bool pingPong, float width,
                 float lowCut, float highCut, float mix) {
        const float targetL = clampf(seconds * sampleRate, 2.f, sampleRate * 4.f);
        const float targetR = clampf(targetL * (1.f + width * 0.5f), 2.f, sampleRate * 4.f);
        if (timeL <= 0) { timeL = targetL; timeR = targetR; }
        const float hpCoef = 1.f - std::exp(-kTwoPi * (20.f * std::pow(50.f, lowCut)) / sampleRate);
        const float lpCoef = 1.f - std::exp(-kTwoPi * (1000.f * std::pow(20.f, highCut)) / sampleRate);
        const float fbk = feedback * 0.98f;
        for (int i = 0; i < n; ++i) {
            timeL += (targetL - timeL) * 0.0005f;
            timeR += (targetR - timeR) * 0.0005f;
            float wet[2] = { line[0].read(timeL), line[1].read(timeR) };
            for (int c = 0; c < 2; ++c) {
                hp[c] += (wet[c] - hp[c]) * hpCoef; hp[c] = flush(hp[c]);
                float y = wet[c] - hp[c];
                lp[c] += (y - lp[c]) * lpCoef; lp[c] = flush(lp[c]);
                wet[c] = lp[c];
            }
            const float inL = L[i], inR = R[i];
            if (pingPong) {
                line[0].push(0.5f * (inL + inR) + softclip(wet[1] * fbk));
                line[1].push(softclip(wet[0] * fbk));
            } else {
                line[0].push(inL + softclip(wet[0] * fbk));
                line[1].push(inR + softclip(wet[1] * fbk));
            }
            L[i] = inL * (1.f - mix) + wet[0] * mix;
            R[i] = inR * (1.f - mix) + wet[1] * mix;
        }
    }
};

// MARK: - COMPRESSOR

/// SINGLE: one band, feed-forward. MULTIBAND: three bands, each pushed
/// down above a high threshold and pulled up below a low one, the
/// loud-and-dense sound of an upward/downward multiband.
struct Compressor {
    SVF lowSplit[2][2], highSplit[2][2];
    float env[3] = {};
    float gainDb[3] = {};
    float sampleRate = 44100;
    void prepare(float sr) {
        sampleRate = sr;
        for (int c = 0; c < 2; ++c) for (int s = 0; s < 2; ++s) {
            lowSplit[c][s].set(120.f, 0.7071f, sr);
            highSplit[c][s].set(2500.f, 0.7071f, sr);
        }
    }
    void clear() {
        for (int c = 0; c < 2; ++c) for (int s = 0; s < 2; ++s) { lowSplit[c][s].reset(); highSplit[c][s].reset(); }
        env[0] = env[1] = env[2] = 0;
    }
    static inline float coef(float seconds, float sr) { return 1.f - std::exp(-1.f / (std::max(seconds, 1e-5f) * sr)); }
    void process(float *L, float *R, int n, int mode, float threshold, float ratio, float attack, float release,
                 float gain, float depth, float mix) {
        const float makeup = dbToGain(gain * 24.f);
        if (mode == 0) {
            const float th = -60.f + threshold * 60.f;
            const float r = 1.f + ratio * ratio * 19.f;
            const float att = coef(0.0001f + attack * attack * 0.1f, sampleRate);
            const float rel = coef(0.01f + release * release * 1.f, sampleRate);
            for (int i = 0; i < n; ++i) {
                const float level = std::max(std::fabs(L[i]), std::fabs(R[i]));
                env[1] += (level - env[1]) * (level > env[1] ? att : rel);
                env[1] = flush(env[1]);
                const float over = gainToDb(env[1]) - th;
                const float reduction = over > 0 ? over * (1.f - 1.f / r) : 0.f;
                gainDb[1] = -reduction;
                const float g = dbToGain(-reduction) * makeup;
                L[i] = L[i] + (L[i] * g - L[i]) * mix;
                R[i] = R[i] + (R[i] * g - R[i]) * mix;
            }
            gainDb[0] = gainDb[2] = 0;
            return;
        }
        // Multiband: TIME (release knob) scales how fast each band moves.
        const float time = 0.2f + release * 1.8f;
        const float att = coef(0.003f * time, sampleRate);
        const float rel = coef(0.08f * time, sampleRate);
        const float downTh = -30.f + threshold * 24.f, upTh = -42.f + threshold * 24.f;
        for (int i = 0; i < n; ++i) {
            float bands[3][2];
            const float in[2] = { L[i], R[i] };
            for (int c = 0; c < 2; ++c) {
                float lp, bp, hp, lp2;
                lowSplit[c][0].process(in[c], lp, bp, hp);
                lowSplit[c][1].process(lp, lp2, bp, hp);
                const float rest = in[c] - lp2;
                float mlp, mlp2;
                highSplit[c][0].process(rest, mlp, bp, hp);
                highSplit[c][1].process(mlp, mlp2, bp, hp);
                bands[0][c] = lp2;
                bands[1][c] = mlp2;
                bands[2][c] = rest - mlp2;
            }
            float outL = 0, outR = 0;
            for (int b = 0; b < 3; ++b) {
                const float level = std::max(std::fabs(bands[b][0]), std::fabs(bands[b][1]));
                env[b] += (level - env[b]) * (level > env[b] ? att : rel);
                env[b] = flush(env[b]);
                const float db = gainToDb(env[b] + 1e-7f);
                float change = 0;
                if (db > downTh) change -= (db - downTh) * (1.f - 1.f / 4.f);
                if (db < upTh && db > -70.f) change += std::min((upTh - db) * (1.f - 1.f / 3.f), 24.f);
                change *= depth;
                gainDb[b] = change;
                const float g = dbToGain(change);
                outL += bands[b][0] * g;
                outR += bands[b][1] * g;
            }
            L[i] = L[i] + (outL * makeup - L[i]) * mix;
            R[i] = R[i] + (outR * makeup - R[i]) * mix;
        }
    }
};

// MARK: - EQ

struct EQ {
    Biquad low[2], mid[2], high[2];
    float sampleRate = 44100;
    void prepare(float sr) { sampleRate = sr; }
    void clear() { for (int c = 0; c < 2; ++c) { low[c].reset(); mid[c].reset(); high[c].reset(); } }
    static float lowHz(float v) { return 20.f * std::pow(50.f, v); }
    static float midHz(float v) { return 100.f * std::pow(100.f, v); }
    static float highHz(float v) { return 1000.f * std::pow(20.f, v); }
    static float q(float v) { return 0.3f * std::pow(27.f, v); }
    void process(float *L, float *R, int n, float lf, float lg, float mf, float mg, float mq, float hf, float hg) {
        for (int c = 0; c < 2; ++c) {
            low[c].lowShelf(lowHz(lf), lg * 18.f, sampleRate);
            mid[c].peak(midHz(mf), mg * 18.f, q(mq), sampleRate);
            high[c].highShelf(highHz(hf), hg * 18.f, sampleRate);
        }
        for (int i = 0; i < n; ++i) {
            L[i] = high[0].process(mid[0].process(low[0].process(L[i])));
            R[i] = high[1].process(mid[1].process(low[1].process(R[i])));
        }
    }
};

// MARK: - FILTER

struct FXFilter {
    SVF svf[2];
    float ladder[2][4] = {};
    DelayLine comb[2];
    float sampleRate = 44100;
    void prepare(float sr) { sampleRate = sr; for (auto &c : comb) c.prepare((int)(sr / 15.f)); }
    void clear() { svf[0].reset(); svf[1].reset(); std::memset(ladder, 0, sizeof(ladder)); comb[0].clear(); comb[1].clear(); }
    static float hz(float v) { return 20.f * std::pow(1000.f, v); }
    void process(float *L, float *R, int n, int type, float cutoff, float res, float drive, float mix) {
        const float f = std::min(hz(cutoff), sampleRate * 0.45f);
        for (auto &s : svf) s.set(f, 0.5f + res * res * 12.f, sampleRate);
        const float g = 1.f - std::exp(-kTwoPi * f / sampleRate);
        const float pre = 1.f + drive * 8.f, post = 1.f / std::sqrt(pre);
        float *io[2] = { L, R };
        for (int i = 0; i < n; ++i) {
            for (int c = 0; c < 2; ++c) {
                const float x = io[c][i];
                const float in = drive > 0.001f ? softclip(x * pre) * post * 1.3f : x;
                float y;
                if (type == 4) {
                    float *yv = ladder[c];
                    const float u = softclip(in - res * 3.9f * yv[3]);
                    yv[0] = flush(yv[0] + g * (u - softclip(yv[0])));
                    yv[1] = flush(yv[1] + g * (softclip(yv[0]) - softclip(yv[1])));
                    yv[2] = flush(yv[2] + g * (softclip(yv[1]) - softclip(yv[2])));
                    yv[3] = flush(yv[3] + g * (softclip(yv[2]) - softclip(yv[3])));
                    y = yv[3] * (1.f + res * 0.8f);
                } else if (type == 5) {
                    const float delay = sampleRate / f;
                    const float wet = comb[c].read(delay);
                    comb[c].push(flush(in + wet * res * 0.95f));
                    y = (in + wet) * (1.f - res * 0.45f);
                } else {
                    float lp, bp, hp;
                    svf[c].process(in, lp, bp, hp);
                    y = type == 0 ? lp : type == 1 ? hp : type == 2 ? bp : lp + hp;
                }
                io[c][i] = x + (y - x) * mix;
            }
        }
    }
};

// MARK: - REVERB

/// Eight-line feedback delay network with input diffusion. PLATE diffuses
/// hard and runs short, bright lines; HALL runs longer, darker and slower.
struct Reverb {
    static constexpr int kLines = 8;
    DelayLine lines[kLines];
    DelayLine pre[2];
    DelayLine diffuser[4];
    float damp[kLines] = {};
    float lengths[kLines] = {};
    float modPhase = 0;
    float sizeSmoothed = -1;
    float sampleRate = 44100;
    void prepare(float sr) {
        sampleRate = sr;
        const float ms[kLines] = { 29.7f, 37.1f, 41.1f, 43.7f, 53.3f, 59.9f, 67.1f, 73.3f };
        for (int i = 0; i < kLines; ++i) { lengths[i] = ms[i] * 0.001f * sr; lines[i].prepare((int)(lengths[i] * 2.4f) + 64); }
        for (auto &p : pre) p.prepare((int)(sr * 0.26f));
        const float diff[4] = { 4.771f, 3.595f, 12.73f, 9.307f };
        for (int i = 0; i < 4; ++i) diffuser[i].prepare((int)(diff[i] * 0.001f * sr) + 4);
    }
    void clear() {
        for (auto &l : lines) l.clear();
        for (auto &p : pre) p.clear();
        for (auto &d : diffuser) d.clear();
        std::memset(damp, 0, sizeof(damp));
    }
    void process(float *L, float *R, int n, int mode, float size, float decay, float dampAmt, float width,
                 float predelay, float mix) {
        const bool hall = mode == 1;
        const float targetSize = (hall ? 0.8f : 0.35f) + size * (hall ? 1.4f : 0.9f);
        if (sizeSmoothed < 0) sizeSmoothed = targetSize;
        const float t60 = (hall ? 0.6f : 0.3f) + decay * decay * (hall ? 18.f : 8.f);
        const float dampHz = 20000.f * std::pow(0.03f, dampAmt) * (hall ? 0.6f : 1.f);
        const float dampCoef = 1.f - std::exp(-kTwoPi * dampHz / sampleRate);
        const float preSamples = std::max(1.f, predelay * predelay * 0.25f * sampleRate);
        const float diffusion = hall ? 0.5f : 0.7f;
        const float diffLen[4] = { 4.771f, 3.595f, 12.73f, 9.307f };
        for (int i = 0; i < n; ++i) {
            sizeSmoothed += (targetSize - sizeSmoothed) * 0.0002f;
            modPhase += 0.6f / sampleRate; if (modPhase >= 1) modPhase -= 1;
            pre[0].push(L[i]); pre[1].push(R[i]);
            float inL = pre[0].read(preSamples), inR = pre[1].read(preSamples);
            // Input diffusion: two allpasses per side.
            float *ins[2] = { &inL, &inR };
            for (int d = 0; d < 4; ++d) {
                float &x = *ins[d / 2];
                const float delayed = diffuser[d].read(diffLen[d] * 0.001f * sampleRate);
                const float v = x + diffusion * delayed;
                diffuser[d].push(flush(v));
                x = delayed - diffusion * v;
            }
            float taps[kLines];
            float sum = 0;
            for (int k = 0; k < kLines; ++k) {
                float d = lengths[k] * sizeSmoothed;
                if (k == 1 || k == 6) d += 8.f * std::sin(kTwoPi * (modPhase + k * 0.13f));
                float t = lines[k].read(d);
                damp[k] += (t - damp[k]) * dampCoef; damp[k] = flush(damp[k]);
                const float g = std::pow(10.f, -3.f * (d / sampleRate) / t60);
                taps[k] = damp[k] * g;
                sum += taps[k];
            }
            const float householder = sum * (2.f / kLines);
            float outL = 0, outR = 0;
            for (int k = 0; k < kLines; ++k) {
                const float input = (k % 2 == 0 ? inL : inR) * 0.35f;
                lines[k].push(flush(taps[k] - householder + input));
                if (k % 2 == 0) outL += taps[k]; else outR += taps[k];
            }
            outL *= 0.5f; outR *= 0.5f;
            const float mid = 0.5f * (outL + outR), side = 0.5f * (outL - outR) * width * 1.4f;
            outL = mid + side; outR = mid - side;
            L[i] = L[i] * (1.f - mix) + outL * mix;
            R[i] = R[i] * (1.f - mix) + outR * mix;
        }
    }
};

} // namespace lyfx
