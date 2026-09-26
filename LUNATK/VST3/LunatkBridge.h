// The C boundary between LUNATK's VST3 wrapper (C++) and its Swift side
// (patch, state, parameter table and editor). Swift implements these with
// @_cdecl; the wrapper calls them.
#pragma once
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct LYSynth;

typedef struct LunatkParamInfo {
    int32_t id;
    float minimum;
    float maximum;
    float defaultValue;
    int32_t stepCount;   // 0 continuous
    int32_t group;       // index into the group names
    char name[96];
} LunatkParamInfo;

int32_t lunatk_param_count(void);
bool lunatk_param_info(int32_t index, LunatkParamInfo *out);
int32_t lunatk_group_count(void);
bool lunatk_group_name(int32_t index, char *out, int32_t capacity);

/// Editor edits reach the controller through this: phase 0 begin, 1
/// perform, 2 end, value in the parameter's own units.
typedef void (*LunatkEditFunction)(void *context, int32_t parameterID, float value, int32_t phase);

void *lunatk_box_create(double sampleRate);
void lunatk_box_destroy(void *box);
struct LYSynth *lunatk_box_core(void *box);
/// Not while processing. Rebuilds the core at the new rate with the patch.
struct LYSynth *lunatk_box_set_sample_rate(void *box, double sampleRate);
void lunatk_box_set_bpm(void *box, double bpm);
/// The host or automation moved a knob. Any thread.
void lunatk_box_param_changed(void *box, int32_t parameterID, float value);
float lunatk_box_param_value(void *box, int32_t parameterID);
/// malloc'd; the caller frees.
uint8_t *lunatk_box_copy_state(void *box, int32_t *length);
bool lunatk_box_load_state(void *box, const uint8_t *bytes, int32_t length);
/// A retained NSView; the caller releases it.
void *lunatk_box_make_view(void *box, void *context, LunatkEditFunction edit);

#ifdef __cplusplus
}
#endif
