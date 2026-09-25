// LYLLTH SYNTH realtime core.
//
// Portable C++ DSP behind a plain C interface, so the LYLLTH app, and later an
// AU / VST3 wrapper, drive the same engine. Nothing in here touches Apple UI
// frameworks; Accelerate is used only to build band-limited wavetables, off
// the audio thread.
//
// Threading: lysynth_render runs on the audio thread and never allocates,
// locks, or logs. Parameters are lock-free atomics. Note events go through a
// bounded multi-producer queue and are placed on their exact sample using the
// host-time stamp they were scheduled with. Wavetables are built on the
// caller's thread and swapped in atomically.

#ifndef LY_SYNTH_CORE_H
#define LY_SYNTH_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LYSynth LYSynth;

// ---------------------------------------------------------------------------
// Parameters. Every value is a float; switches and choices are whole numbers.
// Keep in step with LYSynthParameter in Swift (LYSynthPatch.swift).
// ---------------------------------------------------------------------------

enum {
    // Oscillator A, then B at the same offsets from LY_OSCB_BASE.
    LY_OSC_ON = 0,
    LY_OSC_LEVEL,       // 0…1
    LY_OSC_PAN,         // -1…1
    LY_OSC_OCTAVE,      // -3…3
    LY_OSC_SEMI,        // -12…12
    LY_OSC_FINE,        // -100…100 cents
    LY_OSC_WTPOS,       // 0…1
    LY_OSC_UNISON,      // 1…16
    LY_OSC_DETUNE,      // 0…1
    LY_OSC_BLEND,       // 0…1, outer voices against the centre
    LY_OSC_WIDTH,       // 0…1, unison stereo spread
    LY_OSC_PHASE,       // 0…1 start phase
    LY_OSC_RANDPHASE,   // 0…1
    LY_OSC_WARPMODE,    // LY_WARP_*
    LY_OSC_WARPAMT,     // 0…1
    LY_OSC_PARAM_COUNT
};

enum { LY_OSCA_BASE = 0, LY_OSCB_BASE = LY_OSC_PARAM_COUNT };

enum {
    LY_SUB_ON = 2 * LY_OSC_PARAM_COUNT,
    LY_SUB_LEVEL,
    LY_SUB_OCTAVE,      // 1 or 2 octaves down
    LY_SUB_SHAPE,       // 0 sine, 1 triangle, 2 square
    LY_NOISE_ON,
    LY_NOISE_LEVEL,
    LY_NOISE_COLOR,     // 0 white … 1 dark

    LY_FILTER_ON,
    LY_FILTER_TYPE,     // LY_FILTER_*
    LY_FILTER_CUTOFF,   // 0…1, 20 Hz…20 kHz exponential
    LY_FILTER_RES,      // 0…1
    LY_FILTER_DRIVE,    // 0…1
    LY_FILTER_KEYTRACK, // 0…1
    LY_FILTER_ENVAMT,   // -1…1, ENV 2 to cutoff
    LY_FILTER_MIX,      // 0…1 dry/wet
    LY_FILTER_ROUTE_A,
    LY_FILTER_ROUTE_B,
    LY_FILTER_ROUTE_SUB,
    LY_FILTER_ROUTE_NOISE,

    LY_ENV1_A,          // envelope times 0…1 map 0.5 ms…10 s
    LY_ENV1_D,
    LY_ENV1_S,          // 0…1 level
    LY_ENV1_R,
    LY_ENV2_A, LY_ENV2_D, LY_ENV2_S, LY_ENV2_R,
    LY_ENV3_A, LY_ENV3_D, LY_ENV3_S, LY_ENV3_R,

    LY_LFO1_SHAPE,      // LY_LFO_*
    LY_LFO1_RATE,       // 0…1, 0.02…30 Hz, or a sync division index when synced
    LY_LFO1_SYNC,       // 0 free, 1 tempo
    LY_LFO1_RETRIG,     // 0 free-running, 1 restarts per note
    LY_LFO2_SHAPE, LY_LFO2_RATE, LY_LFO2_SYNC, LY_LFO2_RETRIG,
    LY_LFO3_SHAPE, LY_LFO3_RATE, LY_LFO3_SYNC, LY_LFO3_RETRIG,
    LY_LFO4_SHAPE, LY_LFO4_RATE, LY_LFO4_SYNC, LY_LFO4_RETRIG,

    LY_MACRO1, LY_MACRO2, LY_MACRO3, LY_MACRO4,
    LY_MODWHEEL,

    LY_VOICES,          // 1…16; 1 is mono
    LY_GLIDE,           // 0…1 s
    LY_LEGATO,          // 0/1
    LY_MASTER,          // 0…1
    LY_BPM,             // host tempo

    // Envelope curves, -1…1: negative starts fast (the analogue feel),
    // positive starts slow, 0 is a straight line.
    LY_ENV1_ACURVE, LY_ENV1_DCURVE, LY_ENV1_RCURVE,
    LY_ENV2_ACURVE, LY_ENV2_DCURVE, LY_ENV2_RCURVE,
    LY_ENV3_ACURVE, LY_ENV3_DCURVE, LY_ENV3_RCURVE,

    // Drawn LFOs: 0 steps between points, 1 glides between them.
    LY_LFO1_SMOOTH, LY_LFO2_SMOOTH, LY_LFO3_SMOOTH, LY_LFO4_SMOOTH,

    LY_MPE,             // 0/1: each note's own channel carries its bend, pressure, timbre
    LY_BEND_RANGE,      // master pitch bend, semitones

    // Modulation matrix: LY_MATRIX_SLOTS × (source, destination, amount).
    LY_MATRIX_BASE,
};

enum { LY_MATRIX_SLOTS = 16 };
enum { LY_LFO_POINTS = 32 };
/// Drawn LFO shapes: 4 × LY_LFO_POINTS values, -1…1, after the matrix.
enum { LY_LFO_POINTS_BASE = LY_MATRIX_BASE + LY_MATRIX_SLOTS * 3 };
enum { LY_PARAM_COUNT = LY_LFO_POINTS_BASE + 4 * LY_LFO_POINTS };

enum {
    LY_WARP_OFF = 0, LY_WARP_SYNC, LY_WARP_BEND_POS, LY_WARP_BEND_NEG,
    LY_WARP_MIRROR, LY_WARP_PWM, LY_WARP_FM, LY_WARP_RM, LY_WARP_QUANTIZE,
    LY_WARP_COUNT
};

enum {
    LY_FILTER_LP12 = 0, LY_FILTER_LP24, LY_FILTER_HP12, LY_FILTER_HP24,
    LY_FILTER_BP, LY_FILTER_NOTCH, LY_FILTER_LADDER, LY_FILTER_COUNT
};

enum {
    LY_LFO_SINE = 0, LY_LFO_TRIANGLE, LY_LFO_SAW_UP, LY_LFO_SAW_DOWN,
    LY_LFO_SQUARE, LY_LFO_SAMPLE_HOLD, LY_LFO_SMOOTH_RANDOM, LY_LFO_CUSTOM, LY_LFO_SHAPE_COUNT
};

enum {
    LY_SRC_NONE = 0, LY_SRC_ENV1, LY_SRC_ENV2, LY_SRC_ENV3,
    LY_SRC_LFO1, LY_SRC_LFO2, LY_SRC_LFO3, LY_SRC_LFO4,
    LY_SRC_VELOCITY, LY_SRC_NOTE, LY_SRC_MODWHEEL,
    LY_SRC_MACRO1, LY_SRC_MACRO2, LY_SRC_MACRO3, LY_SRC_MACRO4,
    LY_SRC_RANDOM, LY_SRC_STEP_CUTOFF, LY_SRC_STEP_RES,
    LY_SRC_PRESSURE, LY_SRC_TIMBRE, LY_SRC_PITCHBEND,
    LY_SRC_COUNT
};

enum {
    LY_DST_NONE = 0,
    LY_DST_A_LEVEL, LY_DST_A_PAN, LY_DST_A_PITCH, LY_DST_A_WTPOS, LY_DST_A_DETUNE, LY_DST_A_BLEND, LY_DST_A_WARP,
    LY_DST_B_LEVEL, LY_DST_B_PAN, LY_DST_B_PITCH, LY_DST_B_WTPOS, LY_DST_B_DETUNE, LY_DST_B_BLEND, LY_DST_B_WARP,
    LY_DST_SUB_LEVEL, LY_DST_NOISE_LEVEL,
    LY_DST_CUTOFF, LY_DST_RES, LY_DST_DRIVE, LY_DST_FILTER_MIX,
    LY_DST_AMP, LY_DST_PAN, LY_DST_PITCH,
    LY_DST_LFO1_RATE, LY_DST_LFO2_RATE, LY_DST_LFO3_RATE, LY_DST_LFO4_RATE,
    LY_DST_COUNT
};

enum { LY_WT_SIZE = 2048, LY_WT_MAX_FRAMES = 256 };

// Factory wavetables, generated in the core.
enum {
    LY_TABLE_BASIC = 0, LY_TABLE_ANALOG, LY_TABLE_PWM, LY_TABLE_HARMONIC_SWEEP,
    LY_TABLE_FORMANT, LY_TABLE_FM_BELL, LY_TABLE_SYNC_SWEEP, LY_TABLE_ORGAN,
    LY_TABLE_DIGITAL, LY_TABLE_VOID_FOLD, LY_TABLE_GROWL, LY_TABLE_CHOIR,
    LY_TABLE_SPECTRAL_COMB, LY_TABLE_GLASS,
    LY_TABLE_FACTORY_COUNT
};

typedef struct {
    int activeVoices;
    float wavetablePosition[2];   // modulated, of the newest voice
    float envelope[3];            // current level of the newest voice
    float lfo[4];                 // -1…1
    float lfoPhase[4];            // 0…1
    float cutoffHz;               // modulated, of the newest voice
    float modulation[LY_DST_COUNT]; // modulation offset per LY_DST_*, newest voice
} LYSynthDisplay;

LYSynth *lysynth_create(double sampleRate);
void lysynth_destroy(LYSynth *synth);

void lysynth_set_param(LYSynth *synth, int id, float value);
float lysynth_get_param(const LYSynth *synth, int id);

/// hostTime 0 plays at the top of the next block.
void lysynth_note_on(LYSynth *synth, int note, int velocity, uint64_t hostTime, float stepCutoff, float stepResonance);
void lysynth_note_off(LYSynth *synth, int note, uint64_t hostTime);
void lysynth_all_notes_off(LYSynth *synth);
/// One MIDI 1.0 channel message: notes, pitch bend, channel and poly
/// pressure, CC 1 (mod wheel), CC 64 (sustain), CC 74 (MPE timbre),
/// CC 120/123. Any thread; hostTime 0 is now.
void lysynth_midi(LYSynth *synth, uint8_t status, uint8_t data1, uint8_t data2, uint64_t hostTime);

/// Audio thread. `blockHostTime` 0 when the render has no host clock.
void lysynth_render(LYSynth *synth, float *left, float *right, int frames, uint64_t blockHostTime);

/// Not the audio thread. frameCount × LY_WT_SIZE samples, frame after frame.
void lysynth_set_wavetable(LYSynth *synth, int oscillator, const float *frames, int frameCount);
/// Not the audio thread. Uses a factory table built once and shared by every
/// synth instance, so sixteen synth tracks do not hold sixteen copies.
void lysynth_use_factory_table(LYSynth *synth, int oscillator, int tableID);
/// Fills `out` (frameCount × LY_WT_SIZE) and returns the frame count.
int lysynth_factory_table(int tableID, float *out, int maxFrames);

void lysynth_get_display(const LYSynth *synth, LYSynthDisplay *out);
/// Copies the most recent `count` mono output samples (count ≤ 2048).
void lysynth_get_scope(const LYSynth *synth, float *out, int count);

#ifdef __cplusplus
}
#endif

#endif
