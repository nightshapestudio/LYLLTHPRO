// SIREN's inner loops. Built at -O3 in every configuration: in a Debug
// build, Swift at these sample counts would take half a minute per edit.
#ifndef LYVocalDSP_h
#define LYVocalDSP_h

#ifdef __cplusplus
extern "C" {
#endif

/// YIN pitch per frame. `signal` holds `window / 2` samples of silence
/// before the audio and enough after it for the last frame. Writes MIDI
/// pitch (0 when unvoiced) and RMS level per frame.
void lyv_yin(const float *signal, int frameCount, int hop, int window,
             int tauMin, int tauMax, double rate,
             float *outMidi, float *outLevel);

/// Pitch-synchronous overlap-add. Control arrays hold one value per
/// `controlStep` output samples: the source time (seconds) each moment
/// reads from, its pitch and formant shifts in semitones, its gain, and how
/// much of the rebuilt signal replaces the original (0 keeps it unchanged).
void lyv_psola(const float *const *source, float *const *destination,
               int channels, int frames, double rate,
               const double *markPosition, const double *markPeriod,
               const unsigned char *markVoiced, int markCount,
               const double *controlSource, const float *controlSemitones,
               const float *controlFormants,
               const float *controlGain, const float *controlMix,
               int controlCount, int controlStep);

#ifdef __cplusplus
}
#endif

#endif
