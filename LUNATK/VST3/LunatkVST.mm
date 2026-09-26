// LUNATK as a VST3 instrument: one component that processes and controls,
// the same C++ core LYLLTH plays, every LUNATK knob a parameter, pitch bend
// and the wheels mapped from MIDI, the patch saved in the host's project,
// and LYLLTH's editor in a resizable window.

#import <Cocoa/Cocoa.h>

#include "LunatkBridge.h"
#include "../../LYLLTH/SynthCore/LYSynthCore.h"

#include "public.sdk/source/common/pluginview.h"
#include "public.sdk/source/main/pluginfactory.h"
#include "public.sdk/source/vst/vstsinglecomponenteffect.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/base/ustring.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivstmidicontrollers.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include "pluginterfaces/vst/vsttypes.h"

#include <algorithm>
#include <cmath>
#include <vector>

using namespace Steinberg;
using namespace Steinberg::Vst;

namespace {

// Parameters that stand in for MIDI messages VST3 does not deliver as MIDI.
enum : ParamID {
    kPitchBendID = 90000,
    kModWheelID = 90001,
    kSustainID = 90002,
    kAftertouchID = 90003,
};

void toUTF16(const char *text, String128 out) {
    UString(out, 128).fromAscii(text);
}

} // namespace

class LunatkVST;

// MARK: - Editor view

class LunatkView : public CPluginView {
public:
    LunatkView(LunatkVST *owner, void *box);
    ~LunatkView() override;

    tresult PLUGIN_API isPlatformTypeSupported(FIDString type) SMTG_OVERRIDE {
        return strcmp(type, kPlatformTypeNSView) == 0 ? kResultTrue : kResultFalse;
    }
    void attachedToParent() SMTG_OVERRIDE;
    void removedFromParent() SMTG_OVERRIDE;
    tresult PLUGIN_API onSize(ViewRect *newSize) SMTG_OVERRIDE;
    tresult PLUGIN_API canResize() SMTG_OVERRIDE { return kResultTrue; }
    tresult PLUGIN_API checkSizeConstraint(ViewRect *rect) SMTG_OVERRIDE {
        if (rect->getWidth() < 560) rect->right = rect->left + 560;
        if (rect->getHeight() < 340) rect->bottom = rect->top + 340;
        return kResultTrue;
    }

private:
    LunatkVST *owner;
    void *box;
    NSView *editor = nil;
};

// MARK: - Plug-in

class LunatkVST : public SingleComponentEffect, public IMidiMapping {
public:
    static FUID cid;
    static FUnknown *createInstance(void *) { return (IAudioProcessor *)new LunatkVST(); }

    LunatkVST() {
        processContextRequirements.needTempo();
    }

    ~LunatkVST() override {
        if (box) lunatk_box_destroy(box);
    }

    tresult PLUGIN_API initialize(FUnknown *context) SMTG_OVERRIDE {
        tresult result = SingleComponentEffect::initialize(context);
        if (result != kResultOk) return result;
        addEventInput(STR16("MIDI In"), 16);
        addAudioOutput(STR16("Stereo Out"), SpeakerArr::kStereo);

        box = lunatk_box_create(44100);
        core = lunatk_box_core(box);

        // One unit per section, so hosts can list them as LUNATK shows them.
        const int32 groups = lunatk_group_count();
        for (int32 g = 0; g < groups; ++g) {
            char name[128] = {};
            lunatk_group_name(g, name, sizeof(name));
            String128 title;
            toUTF16(name, title);
            addUnit(new Unit(title, g + 1, kRootUnitId));
        }
        const int32 count = lunatk_param_count();
        for (int32 i = 0; i < count; ++i) {
            LunatkParamInfo info = {};
            if (!lunatk_param_info(i, &info)) continue;
            String128 title;
            toUTF16(info.name, title);
            auto *parameter = new RangeParameter(title, (ParamID)info.id, nullptr, info.minimum, info.maximum,
                                                 info.defaultValue, info.stepCount, ParameterInfo::kCanAutomate, info.group + 1);
            parameters.addParameter(parameter);
        }
        parameters.addParameter(STR16("PITCH BEND"), nullptr, 0, 0.5, ParameterInfo::kCanAutomate, kPitchBendID);
        parameters.addParameter(STR16("MOD WHEEL"), nullptr, 0, 0, ParameterInfo::kCanAutomate, kModWheelID);
        parameters.addParameter(STR16("SUSTAIN"), nullptr, 1, 0, ParameterInfo::kCanAutomate, kSustainID);
        parameters.addParameter(STR16("AFTERTOUCH"), nullptr, 0, 0, ParameterInfo::kCanAutomate, kAftertouchID);
        return kResultOk;
    }

    tresult PLUGIN_API terminate() SMTG_OVERRIDE { return SingleComponentEffect::terminate(); }

    tresult PLUGIN_API setBusArrangements(SpeakerArrangement *inputs, int32 numIns, SpeakerArrangement *outputs, int32 numOuts) SMTG_OVERRIDE {
        // Stereo out only.
        if (numIns == 0 && numOuts == 1 && outputs[0] == SpeakerArr::kStereo)
            return SingleComponentEffect::setBusArrangements(inputs, numIns, outputs, numOuts);
        return kResultFalse;
    }

    tresult PLUGIN_API canProcessSampleSize(int32 size) SMTG_OVERRIDE {
        return size == kSample32 ? kResultTrue : kResultFalse;
    }

    tresult PLUGIN_API setupProcessing(ProcessSetup &setup) SMTG_OVERRIDE {
        core = lunatk_box_set_sample_rate(box, setup.sampleRate);
        return SingleComponentEffect::setupProcessing(setup);
    }

    tresult PLUGIN_API setActive(TBool state) SMTG_OVERRIDE {
        if (!state) lysynth_all_notes_off(core);
        return kResultOk;
    }

    tresult PLUGIN_API setProcessing(TBool) SMTG_OVERRIDE { return kResultOk; }

    uint32 PLUGIN_API getTailSamples() SMTG_OVERRIDE { return kInfiniteTail; }

    // Parameters: the host and automation reach the core here, from the
    // processor side; the controller side tells the editor.
    tresult PLUGIN_API setParamNormalized(ParamID tag, ParamValue value) SMTG_OVERRIDE {
        tresult result = SingleComponentEffect::setParamNormalized(tag, value);
        if (tag < kPitchBendID) {
            if (Parameter *parameter = parameters.getParameter(tag))
                lunatk_box_param_changed(box, (int32)tag, (float)parameter->toPlain(value));
        }
        return result;
    }

    tresult PLUGIN_API process(ProcessData &data) SMTG_OVERRIDE {
        if (data.processContext && (data.processContext->state & ProcessContext::kTempoValid)) {
            const double tempo = data.processContext->tempo;
            if (tempo > 0 && std::fabs(tempo - bpm) > 0.001) {
                bpm = tempo;
                lysynth_set_param(core, LY_BPM, (float)tempo);
            }
        }

        // Every parameter point and note, in time order, so each lands on its sample.
        timeline.clear();
        if (IParameterChanges *changes = data.inputParameterChanges) {
            const int32 queues = changes->getParameterCount();
            for (int32 q = 0; q < queues; ++q) {
                IParamValueQueue *queue = changes->getParameterData(q);
                if (!queue) continue;
                const ParamID id = queue->getParameterId();
                const int32 points = queue->getPointCount();
                for (int32 p = 0; p < points; ++p) {
                    int32 offset = 0;
                    ParamValue value = 0;
                    if (queue->getPoint(p, offset, value) == kResultOk) timeline.push_back({offset, 0, (int32)id, (float)value});
                }
            }
        }
        if (IEventList *events = data.inputEvents) {
            const int32 count = events->getEventCount();
            for (int32 i = 0; i < count; ++i) {
                Event event = {};
                if (events->getEvent(i, event) != kResultOk) continue;
                if (event.type == Event::kNoteOnEvent) {
                    const int velocity = std::max(1, std::min(127, (int)std::lround(event.noteOn.velocity * 127)));
                    timeline.push_back({event.sampleOffset, event.noteOn.velocity <= 0 ? 2 : 1, event.noteOn.pitch, (float)velocity});
                } else if (event.type == Event::kNoteOffEvent) {
                    timeline.push_back({event.sampleOffset, 2, event.noteOff.pitch, 0});
                }
            }
        }
        std::stable_sort(timeline.begin(), timeline.end(), [](const Timed &l, const Timed &r) { return l.offset < r.offset; });

        const bool hasOutput = data.numOutputs > 0 && data.outputs[0].numChannels >= 2 && data.outputs[0].channelBuffers32;
        float *left = hasOutput ? data.outputs[0].channelBuffers32[0] : nullptr;
        float *right = hasOutput ? data.outputs[0].channelBuffers32[1] : nullptr;
        const int32 frames = data.numSamples;
        int32 position = 0;
        auto renderTo = [&](int32 until) {
            until = std::max(0, std::min(frames, until));
            if (hasOutput && until > position) lysynth_render(core, left + position, right + position, until - position, 0);
            position = std::max(position, until);
        };
        for (const Timed &item : timeline) {
            renderTo(item.offset);
            switch (item.kind) {
            case 0: applyParameter((ParamID)item.a, item.b); break;
            case 1: lysynth_midi(core, 0x90, (uint8_t)item.a, (uint8_t)item.b, 0); break;
            case 2: lysynth_midi(core, 0x80, (uint8_t)item.a, 0, 0); break;
            }
        }
        renderTo(frames);
        if (hasOutput) data.outputs[0].silenceFlags = 0;
        return kResultOk;
    }

    tresult PLUGIN_API getState(IBStream *state) SMTG_OVERRIDE {
        if (!state) return kInvalidArgument;
        int32_t length = 0;
        uint8_t *bytes = lunatk_box_copy_state(box, &length);
        if (!bytes) return kResultFalse;
        int32 written = 0;
        tresult result = state->write(bytes, length, &written);
        free(bytes);
        return result == kResultOk && written == length ? kResultOk : kResultFalse;
    }

    tresult PLUGIN_API setState(IBStream *state) SMTG_OVERRIDE {
        if (!state) return kInvalidArgument;
        std::vector<uint8_t> bytes;
        uint8_t chunk[4096];
        int32 read = 0;
        while (state->read(chunk, sizeof(chunk), &read) == kResultOk && read > 0) bytes.insert(bytes.end(), chunk, chunk + read);
        if (bytes.empty() || !lunatk_box_load_state(box, bytes.data(), (int32_t)bytes.size())) return kResultFalse;
        // The controller's knobs follow the loaded patch.
        const int32 count = lunatk_param_count();
        for (int32 i = 0; i < count; ++i) {
            LunatkParamInfo info = {};
            if (!lunatk_param_info(i, &info)) continue;
            if (Parameter *parameter = parameters.getParameter((ParamID)info.id))
                parameter->setNormalized(parameter->toNormalized(lunatk_box_param_value(box, info.id)));
        }
        return kResultOk;
    }

    IPlugView *PLUGIN_API createView(FIDString name) SMTG_OVERRIDE {
        if (name && strcmp(name, ViewType::kEditor) == 0) return new LunatkView(this, box);
        return nullptr;
    }

    // MIDI the host turns into parameters.
    tresult PLUGIN_API getMidiControllerAssignment(int32 busIndex, int16, CtrlNumber number, ParamID &id) SMTG_OVERRIDE {
        if (busIndex != 0) return kResultFalse;
        switch (number) {
        case kPitchBend: id = kPitchBendID; return kResultTrue;
        case kCtrlModWheel: id = kModWheelID; return kResultTrue;
        case kCtrlSustainOnOff: id = kSustainID; return kResultTrue;
        case kAfterTouch: id = kAftertouchID; return kResultTrue;
        default: return kResultFalse;
        }
    }

    /// An edit from the editor: begin, perform, end, as a knob turn.
    void editorEdit(int32 id, float plain, int32 phase) {
        Parameter *parameter = parameters.getParameter((ParamID)id);
        if (!parameter) return;
        const ParamValue normalized = parameter->toNormalized(plain);
        if (phase == 0) beginEdit((ParamID)id);
        else if (phase == 1) { parameter->setNormalized(normalized); performEdit((ParamID)id, normalized); }
        else endEdit((ParamID)id);
    }

    OBJ_METHODS(LunatkVST, SingleComponentEffect)
    DEFINE_INTERFACES
        DEF_INTERFACE(IMidiMapping)
    END_DEFINE_INTERFACES(SingleComponentEffect)
    REFCOUNT_METHODS(SingleComponentEffect)

private:
    struct Timed { int32 offset; int kind; int32 a; float b; };

    void applyParameter(ParamID id, float normalized) {
        switch (id) {
        case kPitchBendID: {
            const int value = std::max(0, std::min(16383, (int)std::lround(normalized * 16383)));
            lysynth_midi(core, 0xE0, (uint8_t)(value & 0x7F), (uint8_t)(value >> 7), 0);
            return;
        }
        case kModWheelID: lysynth_midi(core, 0xB0, 1, (uint8_t)std::lround(normalized * 127), 0); return;
        case kSustainID: lysynth_midi(core, 0xB0, 64, normalized >= 0.5f ? 127 : 0, 0); return;
        case kAftertouchID: lysynth_midi(core, 0xD0, (uint8_t)std::lround(normalized * 127), 0, 0); return;
        default:
            if (Parameter *parameter = parameters.getParameter(id))
                lysynth_set_param(core, (int)id, (float)parameter->toPlain(normalized));
        }
    }

    void *box = nullptr;
    LYSynth *core = nullptr;
    double bpm = 120;
    std::vector<Timed> timeline;
};

// Created with uuidgen for LUNATK; never change it, hosts store it.
FUID LunatkVST::cid(0x6C4A2B7E, 0x51F84D0C, 0x9E3A7B21, 0x4C8D5F16);

// MARK: - View

LunatkView::LunatkView(LunatkVST *owner, void *box) : owner(owner), box(box) {
    ViewRect initial(0, 0, 1180, 720);
    setRect(initial);
}

LunatkView::~LunatkView() {
    [editor removeFromSuperview];
    editor = nil;
}

static void lunatkEdit(void *context, int32_t id, float value, int32_t phase) {
    static_cast<LunatkVST *>(context)->editorEdit(id, value, phase);
}

void LunatkView::attachedToParent() {
    NSView *parent = (__bridge NSView *)systemWindow;
    if (!parent) return;
    editor = (__bridge_transfer NSView *)lunatk_box_make_view(box, owner, lunatkEdit);
    editor.frame = NSMakeRect(0, 0, rect.getWidth(), rect.getHeight());
    editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [parent addSubview:editor];
}

void LunatkView::removedFromParent() {
    [editor removeFromSuperview];
    editor = nil;
}

tresult PLUGIN_API LunatkView::onSize(ViewRect *newSize) {
    if (newSize) {
        setRect(*newSize);
        if (editor) editor.frame = NSMakeRect(0, 0, newSize->getWidth(), newSize->getHeight());
    }
    return kResultTrue;
}

// MARK: - Factory

BEGIN_FACTORY_DEF("NIGHTSHAPE", "https://nightshape.net", "")
    DEF_CLASS2(INLINE_UID_FROM_FUID(LunatkVST::cid), PClassInfo::kManyInstances, kVstAudioEffectClass, "LUNATK",
               0, PlugType::kInstrumentSynth, "1.0.0", kVstVersionString, LunatkVST::createInstance)
END_FACTORY
