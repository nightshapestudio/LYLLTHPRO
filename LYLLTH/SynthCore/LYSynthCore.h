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
// Keep in step with LYSynthParameters in Swift (LYSynthPatch.swift). Saved
// patches store names, not these numbers, so the layout may change; the
// values of choices (warp modes, filter types, …) may only ever be appended.
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
    LY_OSC_WARPMODE2,   // second warp, applied after the first
    LY_OSC_WARPAMT2,
    LY_OSC_UNIMODE,     // LY_UNI_*: how detune spreads across the unison voices
    LY_OSC_STACK,       // LY_STACK_*: octave / fifth stacking of unison voices
    LY_OSC_PARAM_COUNT
};

enum { LY_OSCA_BASE = 0, LY_OSCB_BASE = LY_OSC_PARAM_COUNT };

enum {
    LY_SUB_ON = 2 * LY_OSC_PARAM_COUNT,
    LY_SUB_LEVEL,
    LY_SUB_OCTAVE,      // 1 or 2 octaves down
    LY_SUB_SHAPE,       // 0 sine, 1 triangle, 2 square, 3 saw
    LY_SUB_PAN,
    LY_NOISE_ON,
    LY_NOISE_LEVEL,
    LY_NOISE_COLOR,     // 0 bright … 1 dark
    LY_NOISE_TYPE,      // LY_NOISE_*
    LY_NOISE_PITCH,     // 0…1, rate of the pitched noises
    LY_NOISE_KEYTRACK,  // 0/1: the pitched noises follow the note
    LY_NOISE_PAN,

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
    LY_FILTER_PAN,      // -1…1, after the filters

    // Second filter, after the first (serial) or beside it (parallel).
    LY_F2_ON,
    LY_F2_TYPE,
    LY_F2_CUTOFF,
    LY_F2_RES,
    LY_F2_DRIVE,
    LY_F2_KEYTRACK,
    LY_F2_ENVAMT,       // ENV 3 to cutoff
    LY_F2_MIX,
    LY_FILTER_ROUTING,  // 0 serial, 1 parallel

    // Envelopes: times 0…1 map 0.5 ms…10 s; sustain is a level.
    LY_ENV1_A, LY_ENV1_D, LY_ENV1_S, LY_ENV1_R,
    LY_ENV2_A, LY_ENV2_D, LY_ENV2_S, LY_ENV2_R,
    LY_ENV3_A, LY_ENV3_D, LY_ENV3_S, LY_ENV3_R,
    LY_ENV4_A, LY_ENV4_D, LY_ENV4_S, LY_ENV4_R,
    // Hold after the attack peak, same time scale (0 is none).
    LY_ENV1_H, LY_ENV2_H, LY_ENV3_H, LY_ENV4_H,
    // Curves, -1…1: negative starts fast (the analogue feel), positive slow.
    LY_ENV1_ACURVE, LY_ENV1_DCURVE, LY_ENV1_RCURVE,
    LY_ENV2_ACURVE, LY_ENV2_DCURVE, LY_ENV2_RCURVE,
    LY_ENV3_ACURVE, LY_ENV3_DCURVE, LY_ENV3_RCURVE,
    LY_ENV4_ACURVE, LY_ENV4_DCURVE, LY_ENV4_RCURVE,

    // LFOs: LY_LFO_STRIDE values each, from LY_LFO1_SHAPE.
    LY_LFO1_SHAPE,      // LY_LFO_*
    LY_LFO1_RATE,       // 0…1, 0.02…30 Hz, or a sync division index when synced
    LY_LFO1_SYNC,       // 0 free, 1 tempo
    LY_LFO1_RETRIG,     // LY_LFOMODE_*: free-running, restarts per note, or runs once
    LY_LFO1_SMOOTH,     // drawn shapes: 0 steps, 1 glides
    LY_LFO1_PHASE,      // 0…1 start phase
    LY_LFO1_DELAY,      // 0…1, 0…4 s before it starts
    LY_LFO1_RISE,       // 0…1, 0…4 s fade-in after the delay
    LY_LFO1_END,
    LY_LFO_STRIDE = LY_LFO1_END - LY_LFO1_SHAPE,

    LY_MACRO1 = LY_LFO1_SHAPE + 4 * LY_LFO_STRIDE, LY_MACRO2, LY_MACRO3, LY_MACRO4,
    LY_MODWHEEL,

    LY_VOICES,          // 1…16; 1 is mono
    LY_GLIDE,           // 0…1 s
    LY_LEGATO,          // 0/1
    LY_GLIDE_ALWAYS,    // 0 glides only between held notes, 1 every note
    LY_MASTER,          // 0…1
    LY_BPM,             // host tempo
    LY_TUNE,            // -100…100 cents
    LY_VEL_SENS,        // 0…1: how much velocity sets the volume
    LY_MPE,             // 0/1: each note's own channel carries its bend, pressure, timbre
    LY_BEND_RANGE,      // master pitch bend, semitones

    // Arpeggiator.
    LY_ARP_ON,
    LY_ARP_MODE,        // LY_ARP_*
    LY_ARP_RATE,        // sync division index, as the LFOs
    LY_ARP_OCTAVES,     // 1…4
    LY_ARP_GATE,        // 0.05…1 of a step
    LY_ARP_SWING,       // 0…1
    LY_ARP_LATCH,       // 0/1: keeps playing after the keys are let go

    // Effects rack. LY_FX_SLOTS order values (LY_FX_*), then each effect.
    LY_FX_ORDER,
    LY_FX_ORDER_END = LY_FX_ORDER + 10,

    LY_HYPER_ON = LY_FX_ORDER_END, LY_HYPER_RATE, LY_HYPER_DETUNE, LY_HYPER_VOICES, LY_HYPER_MIX,
    LY_HYPER_DIM_SIZE, LY_HYPER_DIM_MIX,
    LY_DIST_ON, LY_DIST_MODE, LY_DIST_DRIVE, LY_DIST_TONE, LY_DIST_MIX,
    LY_FLANGER_ON, LY_FLANGER_RATE, LY_FLANGER_DEPTH, LY_FLANGER_FEEDBACK, LY_FLANGER_MIX,
    LY_PHASER_ON, LY_PHASER_RATE, LY_PHASER_DEPTH, LY_PHASER_FREQ, LY_PHASER_FEEDBACK, LY_PHASER_MIX,
    LY_CHORUS_ON, LY_CHORUS_RATE, LY_CHORUS_DELAY, LY_CHORUS_DEPTH, LY_CHORUS_FEEDBACK, LY_CHORUS_TONE, LY_CHORUS_MIX,
    LY_DELAY_ON, LY_DELAY_TIME, LY_DELAY_FEEDBACK, LY_DELAY_PINGPONG, LY_DELAY_WIDTH,
    LY_DELAY_LOWCUT, LY_DELAY_HIGHCUT, LY_DELAY_MIX,
    LY_COMP_ON, LY_COMP_MODE, LY_COMP_THRESHOLD, LY_COMP_RATIO, LY_COMP_ATTACK, LY_COMP_RELEASE,
    LY_COMP_GAIN, LY_COMP_DEPTH, LY_COMP_MIX,
    LY_EQ_ON, LY_EQ_LOW_FREQ, LY_EQ_LOW_GAIN, LY_EQ_MID_FREQ, LY_EQ_MID_GAIN, LY_EQ_MID_Q,
    LY_EQ_HIGH_FREQ, LY_EQ_HIGH_GAIN,
    LY_FXF_ON, LY_FXF_TYPE, LY_FXF_CUTOFF, LY_FXF_RES, LY_FXF_DRIVE, LY_FXF_MIX,
    LY_REVERB_ON, LY_REVERB_MODE, LY_REVERB_SIZE, LY_REVERB_DECAY, LY_REVERB_DAMP,
    LY_REVERB_WIDTH, LY_REVERB_PREDELAY, LY_REVERB_MIX,

    // Modulation matrix: LY_MATRIX_SLOTS × LY_MATRIX_STRIDE.
    LY_MATRIX_BASE,
};

enum { LY_MATRIX_SLOTS = 32, LY_MATRIX_STRIDE = 6 };
// Offsets inside one matrix slot.
enum {
    LY_MX_SOURCE = 0,
    LY_MX_DEST,
    LY_MX_AMOUNT,       // -1…1
    LY_MX_AUX,          // a second source that scales the first (LY_SRC_NONE for none)
    LY_MX_CURVE,        // -1…1, bends the source's response
    LY_MX_BIPOLAR,      // 0/1: a 0…1 source swings -1…1 instead
};
enum { LY_LFO_POINTS = 32 };
/// Drawn LFO shapes: 4 × LY_LFO_POINTS values, -1…1, after the matrix.
enum { LY_LFO_POINTS_BASE = LY_MATRIX_BASE + LY_MATRIX_SLOTS * LY_MATRIX_STRIDE };

// Added later. Everything from here on sits after the drawn LFO points so the
// ids above (the plug-ins' host parameter addresses) never move.
enum {
    LY_MACRO5 = LY_LFO_POINTS_BASE + 4 * LY_LFO_POINTS, LY_MACRO6, LY_MACRO7, LY_MACRO8,

    // Feedback: the filters' output fed back into their input, per voice.
    LY_FB_AMOUNT,       // 0…1, 0 is off
    LY_FB_DRIVE,        // 0…1: saturation inside the loop
    LY_FB_TONE,         // 0…1: low-pass inside the loop, dark … open

    // Voice inserts: two slots, before or after the filters, per voice.
    LY_INS1_TYPE,       // LY_INS_*
    LY_INS1_POSITION,   // 0 before the filters, 1 after
    LY_INS1_AMOUNT,     // 0…1
    LY_INS1_FREQ,       // 0…1: ring and comb pitch against the note, or the shifter's Hz
    LY_INS1_MIX,        // 0…1
    LY_INS1_END,
    LY_INS_STRIDE = LY_INS1_END - LY_INS1_TYPE,

    // Performers: tempo step sequencers for modulation, four patterns each.
    LY_PERF1_MODE = LY_INS1_TYPE + 2 * LY_INS_STRIDE,   // LY_PERFMODE_*
    LY_PERF1_RATE,      // one step, as a sync division index (like the LFOs)
    LY_PERF1_STEPS,     // 1…16
    LY_PERF1_PATTERN,   // 0…3: A–D
    LY_PERF1_END,
    LY_PERF_STRIDE = LY_PERF1_END - LY_PERF1_MODE,
    LY_PERF_KEYSWITCH = LY_PERF1_MODE + 2 * LY_PERF_STRIDE, // 0/1: four keys choose the pattern
    LY_PERF_KEYROOT,    // 0…124: the lowest switch key (A), the next three B–D

    // Trackers: any source read through a drawn curve.
    LY_TRACK1_SOURCE,   // LY_SRC_*
    LY_TRACK2_SOURCE,

    LY_PERF_VALUES_BASE,
};
enum { LY_PERF_PATTERNS = 4, LY_PERF_MAX_STEPS = 16, LY_TRACK_POINTS = 16 };
/// Performer steps, [performer][pattern][step]: values (-1…1), then shapes (LY_PSTEP_*).
/// Then each tracker's curve: LY_TRACK_POINTS outputs (-1…1) across its input.
enum {
    LY_PERF_SHAPES_BASE = LY_PERF_VALUES_BASE + 2 * LY_PERF_PATTERNS * LY_PERF_MAX_STEPS,
    LY_TRACK_POINTS_BASE = LY_PERF_SHAPES_BASE + 2 * LY_PERF_PATTERNS * LY_PERF_MAX_STEPS,
    LY_PARAM_COUNT = LY_TRACK_POINTS_BASE + 2 * LY_TRACK_POINTS
};

enum {
    LY_INS_OFF = 0, LY_INS_BITCRUSH, LY_INS_DECIMATE, LY_INS_SINE, LY_INS_FOLD, LY_INS_RECTIFY,
    LY_INS_RING, LY_INS_SHIFT, LY_INS_COMB, LY_INS_COUNT
};
enum { LY_PERFMODE_SONG = 0, LY_PERFMODE_TRIG, LY_PERFMODE_COUNT };
enum {
    LY_PSTEP_HOLD = 0, LY_PSTEP_RAMP_UP, LY_PSTEP_RAMP_DOWN, LY_PSTEP_TRIANGLE, LY_PSTEP_DECAY,
    LY_PSTEP_RISE, LY_PSTEP_PULSE, LY_PSTEP_GLIDE, LY_PSTEP_COUNT
};

// Values may be appended, never reordered: patches store them.
enum {
    LY_WARP_OFF = 0, LY_WARP_SYNC, LY_WARP_BEND_POS, LY_WARP_BEND_NEG,
    LY_WARP_MIRROR, LY_WARP_PWM, LY_WARP_FM, LY_WARP_RM, LY_WARP_QUANTIZE,
    LY_WARP_ASYM_POS, LY_WARP_ASYM_NEG, LY_WARP_FLIP, LY_WARP_AM, LY_WARP_FOLD,
    LY_WARP_COUNT
};

enum { LY_UNI_LINEAR = 0, LY_UNI_SUPER, LY_UNI_EXP, LY_UNI_RANDOM, LY_UNI_COUNT };
enum { LY_STACK_OFF = 0, LY_STACK_OCTAVE, LY_STACK_TWO_OCTAVES, LY_STACK_OCTAVE_FIFTH, LY_STACK_FIFTH, LY_STACK_COUNT };

enum {
    LY_NOISE_WHITE = 0, LY_NOISE_PINK, LY_NOISE_BROWN, LY_NOISE_CRACKLE, LY_NOISE_VINYL,
    LY_NOISE_DIGITAL, LY_NOISE_METAL, LY_NOISE_BREATH, LY_NOISE_COUNT
};

enum {
    LY_FILTER_LP12 = 0, LY_FILTER_LP24, LY_FILTER_HP12, LY_FILTER_HP24,
    LY_FILTER_BP, LY_FILTER_NOTCH, LY_FILTER_LADDER,
    LY_FILTER_COMB_POS, LY_FILTER_COMB_NEG, LY_FILTER_FORMANT, LY_FILTER_PHASER, LY_FILTER_BP24,
    LY_FILTER_COUNT
};

enum {
    LY_LFO_SINE = 0, LY_LFO_TRIANGLE, LY_LFO_SAW_UP, LY_LFO_SAW_DOWN,
    LY_LFO_SQUARE, LY_LFO_SAMPLE_HOLD, LY_LFO_SMOOTH_RANDOM, LY_LFO_CUSTOM, LY_LFO_SHAPE_COUNT
};

enum { LY_LFOMODE_FREE = 0, LY_LFOMODE_TRIG, LY_LFOMODE_ENV, LY_LFOMODE_COUNT };

enum { LY_ARP_UP = 0, LY_ARP_DOWN, LY_ARP_UPDOWN, LY_ARP_PLAYED, LY_ARP_RANDOM, LY_ARP_CHORD, LY_ARP_COUNT };

enum {
    LY_FX_HYPER = 0, LY_FX_DIST, LY_FX_FLANGER, LY_FX_PHASER, LY_FX_CHORUS,
    LY_FX_DELAY, LY_FX_COMP, LY_FX_EQ, LY_FX_FILTER, LY_FX_REVERB, LY_FX_COUNT
};

enum {
    LY_DIST_TUBE = 0, LY_DIST_SOFT, LY_DIST_HARD, LY_DIST_DIODE, LY_DIST_LINFOLD, LY_DIST_SINFOLD,
    LY_DIST_ZEROSQUARE, LY_DIST_DOWNSAMPLE, LY_DIST_BITCRUSH, LY_DIST_RECTIFY, LY_DIST_COUNT
};

enum { LY_COMP_SINGLE = 0, LY_COMP_MULTIBAND, LY_COMP_MODE_COUNT };
enum { LY_REVERB_PLATE = 0, LY_REVERB_HALL, LY_REVERB_MODE_COUNT };
enum { LY_FXF_LP = 0, LY_FXF_HP, LY_FXF_BP, LY_FXF_NOTCH, LY_FXF_LADDER, LY_FXF_COMB, LY_FXF_COUNT };

enum {
    LY_SRC_NONE = 0, LY_SRC_ENV1, LY_SRC_ENV2, LY_SRC_ENV3,
    LY_SRC_LFO1, LY_SRC_LFO2, LY_SRC_LFO3, LY_SRC_LFO4,
    LY_SRC_VELOCITY, LY_SRC_NOTE, LY_SRC_MODWHEEL,
    LY_SRC_MACRO1, LY_SRC_MACRO2, LY_SRC_MACRO3, LY_SRC_MACRO4,
    LY_SRC_RANDOM, LY_SRC_STEP_CUTOFF, LY_SRC_STEP_RES,
    LY_SRC_PRESSURE, LY_SRC_TIMBRE, LY_SRC_PITCHBEND,
    LY_SRC_ENV4,
    LY_SRC_MACRO5, LY_SRC_MACRO6, LY_SRC_MACRO7, LY_SRC_MACRO8,
    LY_SRC_PERF1, LY_SRC_PERF2, LY_SRC_TRACK1, LY_SRC_TRACK2,
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
    // Appended; the order above is what older patches saved.
    LY_DST_A_WARP2, LY_DST_A_WIDTH, LY_DST_A_FINE,
    LY_DST_B_WARP2, LY_DST_B_WIDTH, LY_DST_B_FINE,
    LY_DST_SUB_PAN, LY_DST_NOISE_COLOR, LY_DST_NOISE_PITCH, LY_DST_NOISE_PAN,
    LY_DST_F2_CUTOFF, LY_DST_F2_RES, LY_DST_F2_DRIVE, LY_DST_F2_MIX, LY_DST_FILTER_PAN,
    LY_DST_ENV1_ATTACK, LY_DST_ENV1_DECAY, LY_DST_ENV1_RELEASE,
    LY_DST_ENV2_ATTACK, LY_DST_ENV2_DECAY, LY_DST_ENV2_RELEASE,
    LY_DST_HYPER_MIX, LY_DST_HYPER_DETUNE, LY_DST_DIM_MIX,
    LY_DST_DIST_DRIVE, LY_DST_DIST_MIX,
    LY_DST_FLANGER_DEPTH, LY_DST_FLANGER_MIX,
    LY_DST_PHASER_FREQ, LY_DST_PHASER_MIX,
    LY_DST_CHORUS_DEPTH, LY_DST_CHORUS_MIX,
    LY_DST_DELAY_FEEDBACK, LY_DST_DELAY_MIX,
    LY_DST_COMP_DEPTH, LY_DST_COMP_MIX,
    LY_DST_EQ_LOW, LY_DST_EQ_MID, LY_DST_EQ_HIGH,
    LY_DST_FXF_CUTOFF, LY_DST_FXF_RES, LY_DST_FXF_MIX,
    LY_DST_REVERB_SIZE, LY_DST_REVERB_DECAY, LY_DST_REVERB_MIX,
    LY_DST_MASTER,
    LY_DST_FEEDBACK, LY_DST_FB_TONE,
    LY_DST_INS1_AMOUNT, LY_DST_INS1_FREQ, LY_DST_INS2_AMOUNT, LY_DST_INS2_FREQ,
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
    float envelope[4];            // current level of the newest voice
    float lfo[4];                 // -1…1
    float lfoPhase[4];            // 0…1
    float cutoffHz;               // modulated, of the newest voice
    float cutoff2Hz;              // second filter
    float compGain[3];            // compressor gain change per band, dB (single band uses [1])
    float fxLevel[LY_FX_COUNT];   // each effect's output peak, 0…1
    int arpStep;                  // arpeggiator step, -1 when idle
    float modulation[LY_DST_COUNT]; // modulation offset per LY_DST_*, newest voice
    int perfStep[2];              // the step each performer is on, -1 when silent
    int perfPattern[2];           // the pattern playing, 0…3 (a switch key can change it)
    float perfValue[2];           // -1…1
    float trackInput[2];          // where each tracker is reading its curve, 0…1
    float songBeat;               // the beat the synth is following
    int songLocked;               // 1 while a host transport is driving it
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

/// Song position. A plug-in calls this on the audio thread just before each
/// render with the beat at the start of that render (from the host's
/// transport); it holds for that render only. Tempo-synced FREE LFOs, the
/// arpeggiator and SONG performers then line up with the bar.
void lysynth_set_song_position(LYSynth *synth, double beat, int playing);
/// The same for an app that knows where its transport is on the host clock:
/// `beat` is played at `hostTime`. Any thread; lasts until changed. Renders
/// with a block host time follow it.
void lysynth_set_transport(LYSynth *synth, int playing, uint64_t hostTime, double beat);

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
