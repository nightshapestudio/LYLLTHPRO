#include "LYVocalDSP.h"

#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cmath>
#include <vector>

void lyv_yin(const float *signal, int frameCount, int hop, int window,
             int tauMin, int tauMax, double rate,
             float *outMidi, float *outLevel) {
    const int span = window + tauMax;
    std::vector<float> correlation(tauMax + 1);
    std::vector<float> squares(span + 1);
    std::vector<float> difference(tauMax + 1);
    for (int frame = 0; frame < frameCount; ++frame) {
        const float *base = signal + (size_t)frame * hop;
        float meanSquare = 0;
        vDSP_measqv(base, 1, &meanSquare, window);
        outLevel[frame] = std::sqrt(meanSquare);
        outMidi[frame] = 0;

        vDSP_conv(base, 1, base, 1, correlation.data(), 1, tauMax + 1, window);
        squares[0] = 0;
        for (int i = 0; i < span; ++i) squares[i + 1] = squares[i] + base[i] * base[i];
        const float energy0 = squares[window];
        if (energy0 <= 1e-9f) continue;

        // Cumulative mean normalized difference.
        float running = 0;
        difference[0] = 1;
        for (int tau = 1; tau <= tauMax; ++tau) {
            const float energyTau = squares[tau + window] - squares[tau];
            const float d = std::max(0.0f, energy0 + energyTau - 2 * correlation[tau]);
            running += d;
            difference[tau] = running > 0 ? d * (float)tau / running : 1;
        }
        int best = -1;
        int minimumTau = tauMin;
        float minimum = 1e30f;
        for (int tau = tauMin; tau <= tauMax; ++tau) {
            const float value = difference[tau];
            if (value < minimum) { minimum = value; minimumTau = tau; }
            if (value < 0.15f) {
                while (tau + 1 <= tauMax && difference[tau + 1] < difference[tau]) ++tau;
                best = tau;
                break;
            }
        }
        if (best < 0 && minimum < 0.3f) best = minimumTau;
        if (best < 0) continue;
        double refined = best;
        if (best > 1 && best < tauMax) {
            const double a = difference[best - 1], b = difference[best], c = difference[best + 1];
            const double denominator = a - 2 * b + c;
            if (std::fabs(denominator) > 1e-12) refined += 0.5 * (a - c) / denominator;
        }
        const double hz = rate / refined;
        outMidi[frame] = (float)(69 + 12 * std::log2(hz / 440));
    }
}

static inline float control(const float *values, int count, double position) {
    if (position <= 0) return values[0];
    const int index = (int)position;
    if (index + 1 >= count) return values[count - 1];
    const float fraction = (float)(position - index);
    return values[index] + (values[index + 1] - values[index]) * fraction;
}

static inline double controlTime(const double *values, int count, double position) {
    if (position <= 0) return values[0];
    const int index = (int)position;
    if (index + 1 >= count) return values[count - 1];
    const double fraction = position - index;
    return values[index] + (values[index + 1] - values[index]) * fraction;
}

void lyv_psola(const float *const *source, float *const *destination,
               int channels, int frames, double rate,
               const double *markPosition, const double *markPeriod,
               const unsigned char *markVoiced, int markCount,
               const double *controlSource, const float *controlSemitones,
               const float *controlGain, const float *controlMix,
               int controlCount, int controlStep) {
    // Untouched stretches are copied straight through.
    for (int c = 0; c < channels; ++c) std::copy(source[c], source[c] + frames, destination[c]);
    if (markCount == 0 || controlCount == 0) return;

    double longest = 0;
    for (int m = 0; m < markCount; ++m) longest = std::max(longest, markPeriod[m]);
    const int reach = (int)std::ceil(longest) + 2;

    std::vector<std::vector<float>> accumulated(channels, std::vector<float>(frames, 0.0f));
    std::vector<float> weight(frames, 0.0f);

    // Next control step, at or after `from`, where the rebuilt signal is used.
    auto nextActive = [&](int from) {
        for (int k = std::max(0, from); k < controlCount; ++k) if (controlMix[k] > 0) return k;
        return controlCount;
    };

    double position = 0;
    int cursor = 0;
    while (position < frames) {
        const int step = (int)(position / controlStep);
        // Far from any edit: jump to just before the next one.
        const int lookahead = (reach * 2) / controlStep + 2;
        bool near = false;
        for (int k = std::max(0, step - lookahead); k <= std::min(controlCount - 1, step + lookahead); ++k) {
            if (controlMix[k] > 0) { near = true; break; }
        }
        if (!near) {
            const int next = nextActive(step);
            if (next >= controlCount) break;
            position = std::max(position + 1.0, (double)(next * controlStep - reach * 2));
            continue;
        }

        const double at = position / controlStep;
        const double sourceSample = controlTime(controlSource, controlCount, at) * rate;
        while (cursor + 1 < markCount && std::fabs(markPosition[cursor + 1] - sourceSample) <= std::fabs(markPosition[cursor] - sourceSample)) ++cursor;
        while (cursor > 0 && std::fabs(markPosition[cursor - 1] - sourceSample) < std::fabs(markPosition[cursor] - sourceSample)) --cursor;

        const double semitones = control(controlSemitones, controlCount, at);
        const double ratio = markVoiced[cursor] ? std::pow(2.0, semitones / 12.0) : 1.0;
        const int halfWidth = (int)std::lround(markPeriod[cursor]);
        const float gain = control(controlGain, controlCount, at);
        const int center = (int)std::lround(position);
        const int grainCenter = (int)std::lround(markPosition[cursor]);
        for (int offset = -halfWidth; offset <= halfWidth; ++offset) {
            const int target = center + offset, read = grainCenter + offset;
            if (target < 0 || target >= frames || read < 0 || read >= frames) continue;
            const float w = (float)(0.5 + 0.5 * std::cos(M_PI * offset / (halfWidth + 1)));
            weight[target] += w;
            const float scaled = w * gain;
            for (int c = 0; c < channels; ++c) accumulated[c][target] += source[c][read] * scaled;
        }
        position += std::max(1.0, markPeriod[cursor] / ratio);
    }

    // Blend: the rebuilt signal where mix is up, the original read through
    // the time map where it fades, the untouched original elsewhere.
    for (int i = 0; i < frames; ++i) {
        const double at = (double)i / controlStep;
        const float mix = control(controlMix, controlCount, at);
        if (mix <= 0) continue;
        const double sourcePosition = controlTime(controlSource, controlCount, at) * rate;
        const int index = (int)sourcePosition;
        const float fraction = (float)(sourcePosition - index);
        const float level = std::max(weight[i], 1.0f);
        for (int c = 0; c < channels; ++c) {
            float original = 0;
            if (index >= 0 && index + 1 < frames) original = source[c][index] + (source[c][index + 1] - source[c][index]) * fraction;
            else if (index >= 0 && index < frames) original = source[c][index];
            const float rebuilt = accumulated[c][i] / level;
            destination[c][i] = original + (rebuilt - original) * mix;
        }
    }
}
