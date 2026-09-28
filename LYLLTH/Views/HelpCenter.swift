import SwiftUI

enum LYHelpCategory: String, CaseIterable, Identifiable {
    case start = "Start Here"
    case projects = "Projects"
    case create = "Create"
    case arrange = "Arrange & Edit"
    case record = "Record"
    case mix = "Mix & Automate"
    case deliver = "Export & Share"
    case solve = "Troubleshooting"
    case reference = "Reference"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .start: return "sparkles"
        case .projects: return "folder"
        case .create: return "square.grid.3x3.fill"
        case .arrange: return "rectangle.split.3x1"
        case .record: return "record.circle"
        case .mix: return "slider.vertical.3"
        case .deliver: return "square.and.arrow.up"
        case .solve: return "wrench.and.screwdriver"
        case .reference: return "command"
        }
    }
}

struct LYHelpSection: Identifiable, Equatable {
    let id: String
    let title: String
    let paragraphs: [String]
    let steps: [String]
    let tip: String?
    let note: String?

    init(
        _ title: String,
        id: String? = nil,
        paragraphs: [String] = [],
        steps: [String] = [],
        tip: String? = nil,
        note: String? = nil
    ) {
        self.id = id ?? title.lowercased().replacingOccurrences(of: " ", with: "-")
        self.title = title
        self.paragraphs = paragraphs
        self.steps = steps
        self.tip = tip
        self.note = note
    }
}

struct LYHelpArticle: Identifiable, Equatable {
    let id: String
    let category: LYHelpCategory
    let title: String
    let summary: String
    let keywords: [String]
    let sections: [LYHelpSection]
    let related: [String]

    var searchableText: String {
        ([title, summary, category.rawValue] + keywords + sections.flatMap {
            [$0.title] + $0.paragraphs + $0.steps + [$0.tip, $0.note].compactMap { $0 }
        }).joined(separator: " ").lowercased()
    }
}

enum LYHelpLibrary {
    static let articles: [LYHelpArticle] = [
        article("welcome", .start, "Welcome to LYLLTH", "The shortest route from a blank song to a finished bounce.",
                keywords: ["overview", "begin", "first song", "tour"], related: ["five-minute-song", "main-window", "core-concepts"],
                sections: [
                    section("What LYLLTH is", "LYLLTH is a pattern sequencer, linear arranger, recorder, mixer and instrument host in one macOS workspace. Build the repeating idea in SEQUENCER, place it in the song, then shape the full performance in ARRANGE."),
                    section("The basic route", steps: ["Choose DEMO SONG from the project menu if you want a working session to pull apart.", "Create or edit a pattern in SEQUENCER.", "Choose PLACE IN SONG, then switch to ARRANGE.", "Record or import audio, build the mix, and press EXPORT."], tip: "Press Command-1 for SEQUENCER and Command-2 for ARRANGE. Those two keys are the quickest way around LYLLTH."),
                    section("Help while you work", "Point at a control and pause for a short explanation. Open this guide with Command-? whenever you need the full procedure. Search accepts control names, jobs and symptoms—try ‘punch’, ‘missing audio’ or ‘no sound’.")
                ]),
        article("five-minute-song", .start, "Make a song in five minutes", "A complete first pass: pattern, arrangement, mix and export.",
                keywords: ["quick start", "tutorial", "beat", "bounce"], related: ["sequencer", "arrangement", "export-mix"],
                sections: [
                    section("1. Start the pattern", steps: ["Open the project menu and choose NEW, or choose DEMO SONG to start with material already in place.", "Stay in SEQUENCER. Click cells to turn drum steps on and off.", "Open a drum sound from the LIBRARY or click the sound name in the track header."], tip: "Right-click a sequencer cell for velocity, pitch, probability and the other per-step moves."),
                    section("2. Put it in the song", steps: ["Choose PLACE IN SONG below the pattern controls.", "Press Command-2 to open ARRANGE.", "Select the pattern region and press Command-D to place it again."], note: "A pattern is one piece of musical content. Every place it appears in the arrangement follows the same pattern edits."),
                    section("3. Finish a rough mix", steps: ["Use each channel fader to set balance. Click M or S to mute or solo.", "Open the INSPECTOR to add effects, sends or a bus destination.", "Drag the loop brace across the section you want to check repeatedly."], tip: "Turn the master down before fixing every loud track. Headroom makes later choices easier."),
                    section("4. Export", steps: ["Click EXPORT or press Command-E.", "Choose WAV 24-bit for a normal master, WAV 32-bit float for further mastering, or M4A for a small listening copy.", "If the loop brace is active, the export uses that range. Remove it to export the whole song."])
                ]),
        article("main-window", .start, "Find your way around", "What each part of the LYLLTH window is for.",
                keywords: ["interface", "window", "browser", "inspector", "mixer", "transport"], related: ["transport-loop", "sequencer", "arrangement"],
                sections: [
                    section("Across the top", "The transport holds play, stop, record, tempo, song key, metronome, count-in, takes, punch, monitoring, latency and loop controls. The strip below it holds the project menu, the SEQUENCER / ARRANGE switch, KIT, DRUM SYNTH, EXPORT and the panel buttons."),
                    section("The side panels", "LIBRARY is the source browser: NIGHTSHAPE instruments and effects, Audio Units, and project media. INSPECTOR shows the selected channel in detail. Both can be hidden from the three panel buttons near EXPORT."),
                    section("Add a track", "ADD TRACK sits at the top of the track list in both SEQUENCER and ARRANGE, and at the foot of the arrangement. Command-T opens it from anywhere. A new drum track opens DRUM SYNTH and a new synth track opens LUNATK, so you pick its sound straight away."),
                    section("The work area", "SEQUENCER is for repeating patterns. ARRANGE is the song timeline for pattern regions, note clips, recorded or imported audio, automation and folders. The mixer sits below ARRANGE and can be collapsed when you need more timeline height."),
                    section("The status bar", "The bottom edge reports the project format and any action that needs attention. If LYLLTH cannot load audio, start the engine or complete an operation, read this line before changing anything else.", tip: "Hide the panels you are not using. A wide arrangement is easier to edit than a crowded one.")
                ]),
        article("core-concepts", .start, "Patterns, clips and the song", "The few ideas that make the rest of LYLLTH predictable.",
                keywords: ["concept", "region", "event", "track", "song mode", "pattern mode"], related: ["sequencer", "note-editing", "audio-editing"],
                sections: [
                    section("Pattern", "A pattern contains the steps for pattern-based tracks. SEQUENCER loops the selected pattern. PLACE IN SONG creates a region in ARRANGE; duplicating that region reuses the same musical content."),
                    section("Note clip", "A note clip belongs to a melodic instrument track and opens in the piano roll. Its right edge can repeat the notes without making copies inside the clip."),
                    section("Audio event", "An audio event points to a recording or imported file in the project. The event stores its position, fades, gain, pitch and stretch mode without changing the source file."),
                    section("Track and channel", "A track holds events and notes; its channel holds the sound, effects, sends, routing, automation mode and level. Freezing prints a track for lighter playback and keeps the original state available for unfreeze.")
                ]),

        article("project-files", .projects, "Create, save and recover projects", "How .lyllth projects keep the song and its audio together.",
                keywords: ["new", "open", "save", "save as", "autosave", "crash", "recovery", "package"], related: ["project-media", "drumkit-continuity", "missing-media"],
                sections: [
                    section("Project format", "A .lyllth file is a self-contained project package. It stores the song, project media, checksums and a recovery copy. Save before a long recording so the project has a permanent home."),
                    section("Normal file work", steps: ["Use Command-N for a blank song.", "Use Command-O to open a .lyllth project.", "Use Command-S often; macOS also saves document changes as you work.", "Use Save As when you need a separate version rather than another edit of the same song."]),
                    section("Recovery", "LYLLTH keeps an edit journal outside the project and a recovery copy inside saved packages. If a newer recoverable state is found after an interruption, the app offers it before normal work continues.", tip: "Make named versions before destructive arrangement changes: ‘Song 03 vocals’ is easier to trust than ‘Song final final’.")
                ]),
        article("drumkit-continuity", .projects, "Move projects between LYLLTH and DrumKit", "Use one .fkit project to continue a beat on iPhone or Mac.",
                keywords: ["iphone", "fkit", "drumkit", "continuity", "import", "export"], related: ["project-files", "export-mix", "project-media"],
                sections: [
                    section("Open an iPhone project", steps: ["Choose Open DrumKit Project from the project menu, or press Shift-Command-O.", "Select the .fkit file.", "Read the import note if a part of the LYLLTH song has no DrumKit equivalent."]),
                    section("Send a project back", steps: ["Choose Save as DrumKit Project, or press Option-Command-S.", "Choose a destination for the .fkit file.", "Open that file in NIGHTSHAPE DRUMKIT on iPhone."], note: "DrumKit does not contain every Mac feature. Piano-roll clips, hosted Audio Units and Mac-only routing may be left out; LYLLTH reports those differences instead of silently pretending they transferred."),
                    section("Keep the handoff clean", "Use DrumKit sounds and pattern tracks for material that must move both ways. Keep a .lyllth master when the Mac session grows beyond the iPhone format.")
                ]),
        article("project-media", .projects, "Manage project audio", "Find, relink and clean up the files used by the song.",
                keywords: ["media", "audio pool", "unused", "trash", "relink", "project browser"], related: ["missing-media", "audio-import", "project-files"],
                sections: [
                    section("See the media", "Open LIBRARY, then choose PROJECT. LYLLTH lists audio owned by the project, flags anything missing and separates files no longer used by an event or take."),
                    section("Relink a missing file", steps: ["Select the missing item in PROJECT.", "Choose the replacement file when asked.", "Save the project so the repaired media is written into the package."], note: "Relink by content, not just by filename. The wrong take with the right name will still be the wrong performance."),
                    section("Remove unused files", "Choose the unused-media action in PROJECT only after checking the list. Files are moved to the Trash and the saved package is not rewritten until the next save.", tip: "Clean unused takes after the comp is settled, not during the recording session.")
                ]),

        article("sequencer", .create, "Build patterns in the sequencer", "Program drums and repeating parts one step at a time.",
                keywords: ["steps", "cells", "pattern", "velocity", "probability", "flam", "ratchet"], related: ["pattern-workflow", "drum-sounds", "arrangement"],
                sections: [
                    section("Enter steps", "Click a cell to turn it on or off. The moving playhead shows the current step while PATTERN playback loops the pattern. Select a track before changing its sound or detailed channel settings. Each track has M and S; arm tracks for recording in ARRANGE."),
                    section("Shape a step", "Right-click a cell to open NIGHTSHAPE step actions. Use the step values for velocity, level, filter, resonance, effect, pan, pitch, length, probability, flam, ratchet and micro-timing where the track supports them."),
                    section("Keep it playable", "A strong pattern usually needs fewer accents than you think. Set the main pulse first, then add quiet notes, chance and timing changes around it.", tip: "Use probability on decoration, not on the hit that tells the listener where beat one is.")
                ]),
        article("pattern-workflow", .create, "Create, duplicate and place patterns", "Turn one loop into sections without losing the original idea.",
                keywords: ["new pattern", "duplicate pattern", "place in song", "variation", "section"], related: ["sequencer", "arrangement", "core-concepts"],
                sections: [
                    section("Make a variation", steps: ["Choose DUPLICATE in the pattern controls.", "Change the copy: remove the kick, open the hats or alter the chord track.", "Choose PLACE IN SONG when the variation is ready."], tip: "Duplicate before editing a chorus or fill. Editing a pattern already used in the song changes every place that pattern appears."),
                    section("Switch patterns", "The pattern numbers in the SEQUENCER header pick a pattern. Past eight patterns they become ‹ 03 / 12 ›: click the arrows to step through them."),
                    section("Start clean", "NEW creates an empty pattern on every track. This is useful for breakdowns and song sections that should not inherit the previous groove."),
                    section("Edit from the arrangement", "Double-click a pattern region, or select it and press Return, to open that pattern in SEQUENCER. Press Command-2 when you are ready to return to the song.")
                ]),
        article("drum-sounds", .create, "Choose and shape drum sounds", "Swap the whole kit, or open the synth behind every drum sound.",
                keywords: ["drum synth", "sound browser", "kit", "kits", "preset", "audition", "change drum sound", "drum sounds", "noir signal", "save kit"], related: ["drum-kits", "sequencer", "drumkit-continuity"],
                sections: [
                    section("Change a sound without opening anything", "Every drum and synth track shows its sound under its name, with ‹ and › on either side. Click them to step to the previous or next sound of the same kind: a kick steps through kicks. Each one plays as it lands. Command-[ and Command-] do the same on the selected track."),
                    section("Open DRUM SYNTH", "Click DRUM SYNTH in the strip at the top of the window, click a drum track's sound name, or press Shift-Command-D. Opening it from a track sets LOAD INTO to that track."),
                    section("Find a sound", steps: ["Pick a category on the left: KICK, SNARE, CLOSED HAT and so on.", "Click a sound to hear it, or press Up and Down to play through the list. Left and Right change category. Return plays the sound again.", "Double-click it, press LOAD or press Command-Return to put it on the track shown in LOAD INTO.", "Type in the search box to look through every category at once."], tip: "Change LOAD INTO to fill several tracks from the page without closing it. A dot marks the sound already on that track."),
                    section("Shape it", "SIMPLE shows the controls that matter most: the oscillators, sub and noise color, the envelope, the pitch LFO and the output. FULL shows every control the synth has. Draw the volume shape on VOLUME, or drag across the filter display for cutoff and resonance. Each change plays back when you let go."),
                    section("Keep what you made", "LOAD EDITED puts your version on the track. The song keeps its own copy, so it sounds the same on another Mac. SAVE AS adds it to YOUR SOUNDS, which appear at the top of their category in every song. RESET goes back to the saved sound.", note: "Editing a factory sound never changes that sound on other tracks. Your version is loaded as a copy.")
                ]),
        article("drum-kits", .create, "Swap the whole kit", "Change every drum sound at once and keep the beat.",
                keywords: ["kit", "kits", "drum kit", "factory kit", "save kit", "swap drums", "noir signal", "retro cathedral", "electric grid", "chrome bloom", "iron pulse"], related: ["drum-sounds", "sequencer"],
                sections: [
                    section("Load a kit", steps: ["Click KIT in the strip at the top, or press Shift-Command-K. It shows the kit you have loaded.", "Click a kit. Every drum track takes its new sound; the patterns, levels and effects stay exactly as they were."]),
                    section("How sounds find their tracks", "The kick goes on the kick, the snare on the snare, a hat on each hat track. A kit with one tom puts it on both tom tracks. A kit you saved goes back onto the tracks with the same names."),
                    section("Save your own", "Set up the sounds you like, open KIT and press SAVE CURRENT SOUNDS AS A KIT. Edited sounds are saved inside the kit. Your kits are there in every song. Click × and then DELETE? to remove one.", tip: "The five factory kits are the same as in DrumKit on iPhone. KIT shows CUSTOM once you change a sound, so you can always tell whether a kit is still intact.")
                ]),
        article("lunatk", .create, "Play and program LUNATK", "Use LYLLTH’s built-in synth for melodic and harmonic parts.",
                keywords: ["synth", "instrument", "preset", "oscillator", "modulation", "arp", "performer"], related: ["musical-typing", "note-editing", "midi-routing"],
                sections: [
                    section("Open the instrument", "Add an instrument track or select an existing one, then click its sound name, click LUNATK in the library, or press Shift-Command-L. Choose a factory sound before changing the engine; it gives every page a useful starting point."),
                    section("Browse sounds by ear", "Click the sound name at the top of LUNATK to open SOUNDS. Click a sound and it plays a short note on the track; the browser stays open so you can keep clicking. Double-click, or close the browser, to keep the one you have. The ‹ › beside the name step through the category and play each one too."),
                    section("Follow the signal", "Oscillators, sub and noise feed the filters, then the voice effects and output. Modulation routes connect envelopes, LFOs, velocity, macros and performance sources to controls."),
                    section("Stay in time", "Song-synced LFOs, the arpeggiator and performers follow LYLLTH’s transport position. Choose SONG sync for a phrase that must land on the same bar every time; choose note restart for a phrase that should begin with each key.", tip: "Turn one macro all the way down and up before recording it. You will know its safe range before automation commits the move.")
                ]),
        article("musical-typing", .create, "Use Musical Typing and MIDI input", "Play the selected instrument from the Mac keyboard or a connected controller.",
                keywords: ["command k", "computer keyboard", "controller", "midi keyboard", "octave"], related: ["lunatk", "midi-routing", "record-midi"],
                sections: [
                    section("Computer keyboard", "Press Command-K to open Musical Typing. The letter keys play notes; Z and X move the octave. The selected instrument track receives the notes."),
                    section("MIDI controller", "Connect the controller before or during the session. The MIDI indicator in the workspace strip shows available input; the selected synth track responds according to its MIDI routing."),
                    section("If nothing plays", "Select an instrument track, confirm its channel is not muted, and check that audio playback works. Then check the controller source and channel in the track’s MIDI routing.", tip: "Record a difficult passage slowly, then return the project tempo to normal. MIDI notes remain editable after the take.")
                ]),
        article("note-editing", .create, "Edit notes in the piano roll", "Draw, move, resize, duplicate and quantize note clips.",
                keywords: ["piano roll", "quantize", "note clip", "transpose", "duplicate notes", "snap"], related: ["record-midi", "midi-expression", "arrangement"],
                sections: [
                    section("Open and draw", "Double-click a note clip in ARRANGE. Click empty grid space to add a note. Drag a note to move it; drag its right edge to change its length. Click the keyboard at the left to audition a pitch."),
                    section("Select and edit", steps: ["Command-A selects every note.", "Command-D duplicates the selection after its current span.", "Delete removes selected notes.", "Left and Right move notes by the snap value. Up and Down transpose by a semitone; add Shift for an octave.", "Press Q to quantize the selected notes, or all notes when nothing is selected."]),
                    section("Grid and length", "Choose a snap value from quarter notes through thirty-seconds, including triplets, or turn snap off. LENGTH changes the musical content cycle; stretching the clip in ARRANGE can repeat that cycle.", tip: "Quantize the notes that define the groove, then leave intentional pickups and pushes alone.")
                ]),

        article("arrangement", .arrange, "Build the arrangement", "Place patterns, note clips and audio on the song timeline.",
                keywords: ["timeline", "song", "region", "edit cursor", "ruler", "track list", "right click", "context menu", "split", "quantize", "make unique", "mute region"], related: ["pattern-workflow", "audio-editing", "transport-loop"],
                sections: [
                    section("Navigate", "Press Command-2 to open ARRANGE. Scroll sideways through time; the track names and M, S and record controls remain visible. Use the horizontal zoom control or pinch. Option-pinch changes track height."),
                    section("Song FX moves", steps: ["Double-click an empty spot on the SONG FX lane above the tracks to add a filter sweep or FRACTURE move.", "Click the move to choose what it does and which track it works on, or MAIN.", "Drag the move to place it. Drag its left or right edge to shorten or lengthen it.", "Double-click the move to remove it."]),
                    section("Work with pattern regions", "Select a pattern region. Press Command-D to place it again, Delete to remove that placement, or Return to edit its pattern. Removing a region does not delete the pattern from SEQUENCER."),
                    section("Use the ruler", "Click the ruler to place the purple edit cursor. Drag in the ruler to draw, move or resize the loop brace. Double-click the brace to remove it.", tip: "Keep the edit cursor where the next split or paste belongs; it is a destination, not just a playhead."),
                    section("Right-click a region", "Right-click any region, or Control-click it, for everything you can do to it. What you get depends on what you clicked.", steps: ["Audio events: cut, copy, duplicate, split where you clicked or at the cursor, crossfade, mute, loop, lock, rename, transpose, gain and normalize, fades, stretch, SIREN, and BOUNCE IN PLACE.", "Note clips: open the piano roll, split, quantize, transpose, make every note harder or softer, mute and rename.", "Pattern regions: edit in SEQUENCER, place again, split, mute, rename the pattern, and MAKE UNIQUE.", "An empty part of a lane: paste or import audio there, start a note clip there, or move the play cursor there."], tip: "SPLIT HERE cuts where you right-clicked, so you don't have to move the cursor first.", note: "A split or duplicated pattern region is another placement of the same pattern, so editing the pattern changes both. MAKE UNIQUE gives a placement its own copy you can change on its own.")
                ]),
        article("audio-import", .arrange, "Import audio", "Copy an audio file into the project and place it on the timeline.",
                keywords: ["wav", "aiff", "file", "drag", "import audio", "sample"], related: ["audio-editing", "project-media", "warp"],
                sections: [
                    section("Place a file", steps: ["Select an audio track.", "Click the ruler where the file should begin.", "Choose IMPORT AUDIO in ARRANGE and select the file."]),
                    section("Project ownership", "LYLLTH copies imported audio into the project media store. The arrangement event points to that project-owned copy, so moving or renaming the original does not break the song after it has been saved."),
                    section("Before editing", "Check the first transient against the grid and trim or split silence if necessary. Choose the stretch mode only after deciding whether the file should follow tempo.", tip: "Keep an unprocessed source event on a muted safety track before radical pitch or stretch work.")
                ]),
        article("audio-editing", .arrange, "Edit audio events", "Cut and shape audio without changing the source recording.",
                keywords: ["split", "copy", "paste", "duplicate", "gain", "pitch", "fade", "event"], related: ["crossfade-consolidate", "siren-tune", "shortcuts"],
                sections: [
                    section("Basic edits", "Select an audio event. Command-C copies, Command-X cuts, Command-V pastes at the edit cursor, Command-D duplicates after the event, and Delete removes it. Press S to split at the purple edit cursor."),
                    section("Pitch and event gain", "Press + or = to raise pitch and - to lower it. Shift changes four semitones; Command changes an octave; Command-Shift resets pitch. Use / to lower event gain and * to raise it. Modifier keys make larger moves."),
                    section("Move and resize", "Drag an event to move it. Use its edge controls for bounds and fades. These changes stay on the event until you consolidate; the project source remains intact.", tip: "Set event gain before the channel fader. The fader should mix the track, not rescue one quiet clip."),
                    section("Tune and time a performance", "Double-click an event, or click SIREN in the event bar, to open it note by note. SIREN retunes, flattens, nudges and lines up sung parts without touching the recording. An event with SIREN edits shows a dot after SIREN in the event bar.")
                ]),
        article("crossfade-consolidate", .arrange, "Crossfade, consolidate and freeze", "Clean edits, print event changes and lighten a busy session.",
                keywords: ["xfade", "render", "bounce in place", "freeze track", "unfreeze", "cpu"], related: ["audio-editing", "warp", "large-sessions"],
                sections: [
                    section("Crossfade an edit", steps: ["Overlap two neighboring audio events on the same track.", "Select one of the pair.", "Choose XFADE in the event actions."], tip: "A short crossfade removes clicks. A longer one changes the performance, so listen across the entire overlap."),
                    section("Consolidate", "CONSOLIDATE prints the selected event’s gain, fades, pitch and stretch into a new source. Use it when the edit is settled or when you need one portable piece of audio."),
                    section("Freeze a track", "Click the freeze control in the track header to render the track for lighter playback. Click it again to restore the editable instrument and effects.", note: "Unfreeze before changing the instrument, notes or effect chain. Keep the project saved before freezing several tracks at once.")
                ]),
        article("warp", .arrange, "Make audio follow the song", "Choose source speed, tempo follow or beat mapping for an audio event.",
                keywords: ["stretch", "tempo", "beat map", "warp marker", "time stretch", "source speed"], related: ["audio-import", "audio-editing", "crossfade-consolidate"],
                sections: [
                    section("Choose the right mode", "OFF plays at the source speed. TEMPO follows the project tempo. BEAT MAP locks detected beats to the musical grid. Select the event and choose the mode in its arrangement controls."),
                    section("Check the anchors", "Beat mapping works best when the first useful downbeat is clear and transient detection follows the performance. Listen at the start, middle and end; a correct first bar does not guarantee a correct last bar."),
                    section("Commit only when ready", "Keep the event flexible while arranging. Consolidate after pitch, fades and timing are approved.", tip: "For sustained pads and ambience, TEMPO often sounds more natural than forcing every detected movement onto the beat grid.")
                ]),
        article("transport-loop", .arrange, "Use the transport, loop and count-in", "Control playback and define the range used by punch, takes and export.",
                keywords: ["play", "stop", "space", "metronome", "click", "count", "loop brace", "tempo", "playhead", "play cursor", "start position", "jump"], related: ["record-audio", "punch-takes", "export-mix"],
                sections: [
                    section("Playback", "Press Space to play or stop. SONG plays the arrangement; PATTERN loops the pattern open in SEQUENCER."),
                    section("Where the song starts", steps: ["Click the ruler, or an empty part of a lane, to put the purple play cursor there.", "Press Space. The song starts at the cursor.", "Click somewhere else while it plays and the song jumps there straight away."], tip: "Stopping leaves the cursor where it was, so Space plays the same passage again. Click near bar 1 to start from the top.", note: "With LOOP on, the song plays inside the loop. A cursor outside the loop starts at the loop's beginning."),
                    section("Loop range", "Turn LOOP on to cycle the brace in the arrangement ruler. If no brace exists, LYLLTH starts with the first four bars. The same range can define punch recording and a limited export."),
                    section("Click and count", "CLICK turns on the metronome. COUNT adds a one-bar lead-in before recording. Set tempo before tracking time-sensitive audio whenever possible.", tip: "Use count-in for the first take and a quiet lead-in on later punches; the performer hears context without recording over it.")
                ]),

        article("record-audio", .record, "Record audio", "Arm a track, choose an input and capture a take safely.",
                keywords: ["microphone", "input", "record arm", "monitor", "waveform", "audio track", "record vocals", "record guitar", "record voice"], related: ["punch-takes", "latency", "recording-problems"],
                sections: [
                    section("Set up", steps: ["Add or select an audio track.", "Choose the input in the channel settings and click the track’s record-arm control.", "Set the input level at the interface so normal peaks stay clear of clipping.", "Use headphones before enabling MON."], note: "Monitoring through speakers can feed the microphone and produce a loud loop."),
                    section("Record", steps: ["Place the playhead or define a loop range.", "Turn on CLICK and COUNT if needed.", "Press the transport record control, perform, then stop."], tip: "Record ten seconds and play it back before a long take. That catches the wrong input, a muted monitor path and poor gain early."),
                    section("After the take", "The recording becomes project media and appears as an event in ARRANGE. Save the project before removing the interface or moving to another Mac.")
                ]),
        article("multichannel-recording", .record, "Record several inputs", "Capture more than one armed input into aligned tracks.",
                keywords: ["multitrack", "multiple inputs", "interface", "band", "simultaneous"], related: ["record-audio", "latency", "punch-takes"],
                sections: [
                    section("Prepare the tracks", steps: ["Create one audio track for each source.", "Choose a different hardware input on each track.", "Arm every track that should record and leave the others safe.", "Name the tracks before the take so the recordings are easy to identify later."]),
                    section("Check the system", "Confirm the interface sample rate matches the project and every source reaches its intended meter. Use the same monitoring plan for the whole group."),
                    section("Keep alignment", "LYLLTH starts armed tracks from the same transport position. Do not move one raw event by eye to fix monitoring delay; set latency correction, then judge the recorded alignment.", tip: "For a band take, run a short clap or stick count before the music. It gives every track an obvious alignment check.")
                ]),
        article("punch-takes", .record, "Punch in and record loop takes", "Replace a range or collect repeated passes without losing earlier performances.",
                keywords: ["punch in", "punch out", "takes", "loop record", "comp", "cycle"], related: ["take-comping", "transport-loop", "record-audio"],
                sections: [
                    section("Punch a section", steps: ["Draw the loop brace around the part to replace.", "Turn on PUNCH and arm the destination track.", "Start before the range. LYLLTH records only inside the brace."]),
                    section("Collect loop takes", steps: ["Define the loop brace and turn on LOOP.", "Turn on TAKES.", "Record through several passes. LYLLTH keeps a take for each completed loop."], tip: "Leave a little musical context before and after the hard line. A singer or player performs the entry more naturally when the phrase is already moving."),
                    section("Keep the originals", "Loop takes remain attached to the recording lane until you choose the active material. Avoid cleaning unused project audio before the comp is final.")
                ]),
        article("take-comping", .record, "Choose and comp takes", "Build one performance from recorded passes.",
                keywords: ["take lane", "alternate take", "comping", "active take", "recording lanes"], related: ["punch-takes", "audio-editing", "project-media"],
                sections: [
                    section("Open the takes", "Select the recorded track or event and open its take control in the inspector. Choose an alternate take to hear it in the same song position."),
                    section("Build the comp", "Choose the strongest complete take first. Split only where another pass clearly improves the phrase, then use short crossfades at the joins."),
                    section("Commit carefully", "Keep the full takes until the edit has survived a few full-song listens. Consolidate the comp only when the boundaries and fades are final.", tip: "Comp for meaning and timing before chasing microscopic pitch or noise differences.")
                ]),
        article("siren-tune", .record, "Tune a vocal with SIREN", "Fix pitch one note at a time without changing who is singing.",
                keywords: ["siren", "pitch correction", "tuning", "autotune", "melodyne", "vocal", "flat", "sharp", "out of tune", "cents"], related: ["siren-notes", "siren-align", "siren-problems"],
                sections: [
                    section("Open SIREN", steps: ["Select the audio event in ARRANGE.", "Click SIREN in the event bar, or double-click the event.", "Wait while SIREN listens. A three-minute lead takes a few seconds the first time; after that it opens straight away."], note: "SIREN works on one voice at a time, such as a lead vocal, a double or a bass line. It can't separate a chord or a choir, and reverb recorded into the take confuses it."),
                    section("Read the screen", "Each shape is a note SIREN heard. It gets thicker where the singer gets louder. The white line through it is the pitch you will hear, with every scoop and wobble drawn in. The number above a note is how far its center sits from the nearest semitone, in cents. It turns pink past ten cents. Rows outside the song key are shaded darker."),
                    section("Fix one note", steps: ["Click the note.", "Drag it up or down. It moves in whole semitones.", "Hold Option while dragging to move it by cents instead.", "Use the Up and Down arrow keys for a semitone at a time, or Option-arrow for ten cents."], tip: "Fix the notes people will notice: long ones, loud ones, the last note of a line. A quick passing note that is twenty cents flat usually sounds like singing."),
                    section("Fix a whole take", steps: ["Select the notes you want, or select nothing to work on all of them.", "Set PITCH. At 100% every note center lands on pitch; at 60% each one moves most of the way there.", "Set DRIFT. This smooths the wandering inside each note, vibrato included.", "Click CHROMATIC to switch to the song key if notes should only land on scale tones.", "Press CORRECT ALL. With notes selected, the button shows how many it will change."], tip: "Start with PITCH at 100% and DRIFT around 30%. That keeps the vibrato and still pulls sagging held notes up.", note: "DRIFT at 100% holds every note dead flat, which gives the hard-tuned robot sound."),
                    section("Check your work", "Press A / B to hear the take as it was sung. Your edits stay in place while you listen. RESET puts the selected notes back, and RESET ALL puts back the whole take. SIREN never changes the recording itself.")
                ]),
        article("siren-notes", .record, "Split, join and move notes in SIREN", "Correct what SIREN heard, then fix timing by hand.",
                keywords: ["siren", "split note", "join note", "timing", "nudge", "select notes", "legato"], related: ["siren-tune", "siren-align", "audio-editing"],
                sections: [
                    section("When SIREN gets the notes wrong", "SIREN splits a phrase wherever the pitch jumps and holds. A slow slide between two notes can come out as one long note, and a scoop at the start of a note can become a note of its own. Fix those before you tune, or the correction pulls the wrong part of the line."),
                    section("Split and join", steps: ["Double-click a note where it should break in two.", "Select two or more notes that touch and press JOIN to make them one."], tip: "Split a long slide at the point where the singer arrives. The arrival gets tuned and the slide into it stays natural."),
                    section("Move a note in time", steps: ["Drag the note sideways. Once a drag starts moving one way, it stays locked to that direction.", "The notes either side stretch or squeeze to make room, so nothing overlaps."], note: "Small moves sound best. Moving a word by a sixteenth is fine. Moving it by a beat usually means a different take is the better fix."),
                    section("Select quickly", "Click a note to select it. Shift-click or Command-click adds to the selection. Drag across empty space to draw a box around several notes. Command-A selects every note in the take.")
                ]),
        article("siren-align", .record, "Line up a double with ALIGN", "Make a double, a harmony or a gang vocal follow the lead's timing.",
                keywords: ["siren", "align", "vocalign", "double", "doubles", "harmony", "stack", "timing", "tight", "guide"], related: ["siren-tune", "siren-notes", "take-comping"],
                sections: [
                    section("Before you align", steps: ["Comp the lead first. The guide should be the version that ends up in the song.", "Put the guide and the double on separate tracks, overlapping by at least a second.", "Turn STRETCH off on both events. ALIGN works at the speed they were recorded."]),
                    section("Align", steps: ["Open SIREN on the double, not on the guide.", "Click ALIGN at the top of the window.", "Choose the lead from GUIDE. Only events that overlap this one are listed.", "Set TIGHT, then press ALIGN."], tip: "TIGHT at 75–85% suits stacked doubles: the words land together and the double keeps a little of its own feel. Use 100% for backing vocals that have to sound like one voice."),
                    section("Pitch too", "Switch TIMING ONLY to PITCH TOO before pressing ALIGN and every note of the double also moves to the pitch the guide sings at the same moment. Leave it off for harmonies. They are meant to sit on other notes."),
                    section("After aligning", "The notes stay editable. You can still drag a word by hand or tune a note after ALIGN has done its work. CLEAR removes only the alignment and keeps any tuning.", note: "If the double drags or smears, lower TIGHT and align again. A word may not match because the guide took a breath where the double kept singing. Leave that word alone or drag it by hand.")
                ]),
        article("record-midi", .record, "Record MIDI notes", "Capture a keyboard performance into an editable note clip.",
                keywords: ["midi recording", "note capture", "controller", "musical typing", "instrument track"], related: ["musical-typing", "note-editing", "midi-expression"],
                sections: [
                    section("Record a pass", steps: ["Select an instrument track and confirm the desired sound.", "Arm the track.", "Check the MIDI indicator to confirm LYLLTH sees the controller.", "Enable count-in if needed, then record from the controller or Musical Typing."]),
                    section("Edit without flattening it", "Open the resulting note clip in the piano roll. Correct obvious timing or pitch mistakes first; only quantize the notes that need it."),
                    section("Expression", "Velocity and note expression remain part of the MIDI performance. Use track routing and automation for moves that belong to the channel rather than one note.")
                ]),
        article("latency", .record, "Set monitoring and recording latency", "Keep performers comfortable and recorded audio on the grid.",
                keywords: ["delay", "late recording", "early recording", "buffer", "monitoring", "compensation"], related: ["record-audio", "recording-problems", "audio-units"],
                sections: [
                    section("Monitoring", "MON routes the selected input through LYLLTH. Use headphones. If the interface offers direct monitoring, compare both paths and use one—not both—to avoid a doubled signal."),
                    section("Manual correction", "LAT cycles the recording latency correction in milliseconds. Record a sharp test sound against the click, inspect the result, then adjust LAT until the recorded transient lands where it was performed."),
                    section("Plugin delay", "Hosted effects can add processing delay. LYLLTH compensates the mix path; very heavy look-ahead chains can still feel slow while playing live. Bypass them or freeze other tracks while recording.", tip: "Fix the monitoring path before moving recorded events. Moving clips hides the setup problem and makes the next take wrong again.")
                ]),

        article("mixer-routing", .mix, "Mix, route and use buses", "Balance tracks, build shared effects and control the signal path.",
                keywords: ["mixer", "fader", "pan", "send", "bus", "output", "main", "solo", "mute"], related: ["nightshape-effects", "audio-units", "folders-groups"],
                sections: [
                    section("Balance first", "Use the channel faders for level and pan for placement. Mute isolates a problem by subtraction; solo focuses a track. Clear a clip indicator after lowering the source of the overload."),
                    section("Sends and buses", "Add a send when several tracks should share an effect such as reverb. Route a track’s output to a bus when the entire channel should pass through a group processor before MAIN."),
                    section("Read the path", "Track source → channel effects → sends and output destination → bus or MAIN. Open the inspector to see and change the selected channel’s effects, sends and destination.", tip: "Use one short shared reverb before giving every channel its own space. The mix will feel more connected and use less processing.")
                ]),
        article("nightshape-effects", .mix, "Use NIGHTSHAPE effects", "Add, reorder, bypass and automate the built-in processors.",
                keywords: ["fx", "eq", "compressor", "reverb", "delay", "decimator", "filter", "saturation", "add effect", "insert", "plus", "menu"], related: ["de-esser", "noise-gate", "audio-units"],
                sections: [
                    section("Add an effect", steps: ["Click the + under AUDIO FX in the channel strip.", "Point at a folder: TONE, DYNAMICS, SPACE, MOTION, DESTRUCTION or OUTPUT. It opens to the right.", "Click an effect. It goes on the end of the chain and its window opens."], tip: "Start typing as soon as the menu opens. The search looks through every folder, and Return adds the first match.", note: "Effects already on the channel say ON. Clicking one opens it; the − beside it takes it off."),
                    section("Build the chain", "Click an effect's name in the strip to open it. Drag effects up or down to change the order. Sound goes through them from top to bottom."),
                    section("Bypass and compare", "Use the effect’s power control for a level-matched comparison. A louder result can sound better even when the processing is not helping."),
                    section("Share ambience", "Use the channel’s reverb send or a bus for common space. Insert an effect when it should change only that track.", tip: "Make EQ cuts while the whole song plays. A sound that is impressive alone can be too large for its job.")
                ]),
        article("de-esser", .mix, "Tame harsh esses with the DE-ESSER", "Pull down S and T sounds without dulling the rest of the voice.",
                keywords: ["de-esser", "deesser", "sibilance", "esses", "harsh", "hiss", "vocal", "s sounds"], related: ["noise-gate", "nightshape-effects", "siren-tune"],
                sections: [
                    section("Set it up", steps: ["Add DE-ESSER from DYNAMICS in the + menu. LEAD VOCAL is a good start.", "Turn on LISTEN and sweep FREQUENCY until you hear mostly the hiss of the esses. Turn LISTEN off.", "Lower THRESHOLD until the meter reads a few dB of cut on each S, and nothing between them.", "Set RANGE to the most it should ever take off."], tip: "Most voices sit between 5 and 8 kHz. Lower voices and darker mics often need 4 to 5 kHz."),
                    section("Read the window", "The line across the top is the output. It dips at the band you picked, by as much as it is cutting right now. The meter on the right shows the band's level against THRESHOLD, and the number above it is the cut in dB."),
                    section("Choose a mode", "BAND dips only the band around FREQUENCY and leaves everything else alone. SHELF pulls down everything above FREQUENCY, for bright cymbals or an airy mix. WIDE turns the whole signal down while an S sounds, which is gentler on a thin voice but moves the level more."),
                    section("Where to put it", "Put it after EQ, so a treble boost does not add esses it then has to catch, and before a compressor, so the compressor does not react to them. It never touches audio below THRESHOLD.", note: "Too much makes a singer sound like they have a lisp. If the S turns into a TH, back RANGE off.")
                ]),
        article("noise-gate", .mix, "Clean up a track with the NOISE GATE", "Silence the hum, bleed and breaths between the parts you want.",
                keywords: ["noise gate", "gate", "bleed", "hum", "hiss", "tighten drums", "threshold", "hold", "hysteresis", "key"], related: ["de-esser", "nightshape-effects", "no-sound"],
                sections: [
                    section("Set it up", steps: ["Add NOISE GATE from DYNAMICS in the + menu.", "Play the track and watch the KEY meter. Set THRESHOLD above the noise between notes and below the quietest note you want to keep.", "Set RELEASE by ear: short for tight drums, longer for a voice or guitar so notes can ring out.", "Raise HOLD if the gate chatters on and off during a note."]),
                    section("Read the window", "The shape shows what the gate does to a note: it opens during ATTACK, stays open for HOLD, then falls in a straight line over RELEASE, down to RANGE. The meter shows the key level against THRESHOLD. The lamp says OPEN or SHUT."),
                    section("Keep bleed out", "On the KEY page, KEY LOW and KEY HIGH filter what the gate listens to, not what you hear. A snare gate with KEY LOW at 200 Hz ignores the kick bleeding into its mic. KEY LISTEN plays the filtered key so you can check it."),
                    section("Hysteresis and range", "HYSTERESIS makes it close a few dB lower than it opens, so a note hovering at the threshold does not flutter. RANGE sets how far it closes. At the top of its travel it reads SILENT; 10 to 20 dB just turns the noise down.", tip: "On vocals, a RANGE of 15 to 25 dB sounds natural. Silence between phrases can sound more wrong than the breaths did.")
                ]),
        article("audio-units", .mix, "Host Audio Unit instruments and effects", "Load third-party plug-ins, edit them and recover from a failed scan.",
                keywords: ["au", "plugin", "third party", "validation", "quarantine", "delay compensation", "instrument"], related: ["plugin-problems", "latency", "mixer-routing"],
                sections: [
                    section("Load a plug-in", "For an effect, click the + under AUDIO FX in the channel strip and open AUDIO UNITS. Plug-ins are listed by maker. For an instrument, open LIBRARY and choose AU INST with the track selected. The editor opens once it loads, and again from the channel inspector."),
                    section("Timing and state", "LYLLTH stores the plug-in state with the project and accounts for reported processing delay in playback and export. Save after configuring a complex instrument or effect."),
                    section("Quarantine", "A plug-in that fails to load three times is quarantined, so it cannot hold up every session. That includes one that made LYLLTH quit while it loaded. Quarantined plug-ins are listed at the bottom of AU INST and AU FX in LIBRARY. Click one to reset it, or use RESET QUARANTINE under Settings ▸ Plug-ins.", tip: "Add or update one plug-in at a time. If the session changes behavior, you will know which component to check.")
                ]),
        article("automation", .mix, "Draw and write automation", "Move channel and effect controls across the song.",
                keywords: ["lane", "read", "touch", "latch", "write", "volume automation", "parameter"], related: ["automation-modes", "nightshape-effects", "mixer-routing"],
                sections: [
                    section("Show a lane", "Click the automation control in a track header, add a lane and choose its target. Click the lane to add points; move points to shape the change. Turn a lane off to hold the control at its current setting without deleting the points."),
                    section("Choose useful targets", "Automate a move that belongs to the song: a vocal lift, a filter opening, a delay throw or a fade. Keep sound-design motion inside the instrument when it should repeat with every note."),
                    section("Keep curves clean", "Use the fewest points that describe the move. Dense points are harder to edit and can turn a smooth gesture into chatter.", tip: "Write a performance, then simplify it. The first pass finds the feeling; the edit keeps only the movement the song needs.")
                ]),
        article("automation-modes", .mix, "Choose an automation write mode", "Know exactly when LYLLTH reads or replaces automation.",
                keywords: ["read mode", "touch mode", "latch mode", "write mode", "overwrite"], related: ["automation", "shortcuts", "project-files"],
                sections: [
                    section("READ", "Plays existing automation and writes nothing. Leave finished tracks in READ."),
                    section("TOUCH", "Writes while you hold or move the control, then returns to the existing automation when you let go. Use it to repair a short section."),
                    section("LATCH", "Starts writing when you touch the control and keeps the last value after release until playback stops. Use it for a move that should settle at a new level."),
                    section("WRITE", "Writes across the whole pass, including the current static value before you touch anything. Use it deliberately; it can replace a finished lane.", note: "Return the track to READ after every write pass. That one habit prevents most accidental automation loss.")
                ]),
        article("midi-routing", .mix, "Understand MIDI input", "Know where controller notes go and how to avoid playing the wrong track.",
                keywords: ["midi input", "controller", "channel", "source", "selected track", "external"], related: ["musical-typing", "midi-expression", "record-midi"],
                sections: [
                    section("The selected track", "Incoming MIDI plays the selected instrument track. The MIDI indicator near the top of the workspace shows how many input devices LYLLTH can see."),
                    section("Change instruments deliberately", "Select the destination track before playing or recording. If another synth responds, stop and confirm which track is highlighted before changing the controller or sound."),
                    section("Controller setup", "Set the controller to a normal note-playing mode and make sure another app is not holding its MIDI port. LYLLTH follows note input; sound still comes from the instrument loaded on the selected track.", tip: "Name the track for its musical job—‘BASS’ or ‘LEAD’—so the destination is obvious before a take.")
                ]),
        article("midi-expression", .mix, "Keep MIDI expression intact", "Understand what belongs to a note and what belongs to the channel.",
                keywords: ["velocity", "pitch bend", "pressure", "aftertouch", "timbre", "cc", "expression"], related: ["midi-routing", "note-editing", "lunatk"],
                sections: [
                    section("Note expression", "Velocity belongs to the note. A clip can also retain per-note pitch, pressure and timbre data from an expressive performance."),
                    section("What the piano roll changes", "The piano roll edits note position, length and pitch. It does not turn detailed expression into a separate drawing lane, so keep the original performance when those gestures matter."),
                    section("Channel movement", "Use automation when the move should affect the complete instrument or mix channel. Use note expression when two held notes need different movement at the same moment.", tip: "Duplicate the clip before heavily quantizing an expressive take.")
                ]),
        article("folders-groups", .mix, "Organize tracks with folders and groups", "Keep a large arrangement readable and make related channels move together.",
                keywords: ["folder", "collapse", "group", "link", "large session", "navigation"], related: ["large-sessions", "mixer-routing", "arrangement"],
                sections: [
                    section("Folders", "Put related tracks in a folder and collapse it from ARRANGE when the detail is not needed. The folder changes visibility; it does not replace audio routing."),
                    section("Groups", "Link channels when mute, solo or mix moves should stay coordinated. Use a bus when the audio itself must pass through one shared channel."),
                    section("Name by job", "Use stable names such as DRUMS, BASS, VOCALS and PRINTS. Color and position help, but a clear name survives exports, stems and handoffs.", tip: "Keep buses beside the tracks they collect and put print or reference tracks at the bottom of the song.")
                ]),

        article("export-mix", .deliver, "Export a mix", "Choose the right master format and range.",
                keywords: ["bounce", "wav", "m4a", "aac", "24 bit", "32 bit float", "tail"], related: ["export-stems-midi", "transport-loop", "drumkit-continuity"],
                sections: [
                    section("Choose a format", "WAV 24-bit is the normal choice for a finished master. WAV 32-bit float preserves extra headroom for mastering or further processing. M4A AAC is a compact listening copy."),
                    section("Choose the range", "With an active loop brace, LYLLTH exports that range. Without one, it exports the full song. A three-second tail preserves reverb and delay after the last event."),
                    section("Check the result", steps: ["Listen to the beginning for count-ins or clipped attacks.", "Check the loudest section for distortion.", "Listen through the end of the tail.", "Confirm the file opens in a player outside LYLLTH."], tip: "Export a full-quality WAV first. Make smaller delivery formats from the approved master, not from another compressed copy.")
                ]),
        article("export-stems-midi", .deliver, "Export stems and MIDI", "Hand the song to another mixer, collaborator or instrument host.",
                keywords: ["stems zip", "midi file", "handoff", "bar one", "gm drum map"], related: ["export-mix", "folders-groups", "drumkit-continuity"],
                sections: [
                    section("Stems", "STEMS exports each track alone into a ZIP. Every file starts at bar one so the set lines up when dropped into another DAW. The archive includes a README."),
                    section("MIDI", "MIDI export writes note material one track per sound and uses the General MIDI drum map for drum parts. Audio, plug-in sound and channel effects are not part of a MIDI file."),
                    section("Prepare a handoff", "Name tracks clearly, remove accidental mutes and include a rough mix. Tell the recipient the tempo, sample rate and whether the stems include master processing.", tip: "Import the stems into a blank session and press play. That is the fastest proof that the handoff is complete and aligned.")
                ]),

        article("no-sound", .solve, "No sound", "Trace silence from the transport to the main output.",
                keywords: ["silent", "cannot hear", "audio engine", "output", "muted"], related: ["recording-problems", "plugin-problems", "mixer-routing"],
                sections: [
                    section("Start with the obvious path", steps: ["Press Space and confirm the playhead moves.", "Check that the track and MAIN are not muted and no unrelated solo is active.", "Raise the track and MAIN faders to a safe normal position.", "Confirm the correct macOS output device is available and its volume is up."]),
                    section("Check the source", "For patterns, confirm the pattern is placed in SONG or switch to PATTERN playback. For a note clip, confirm the instrument is loaded. For audio, open PROJECT and check that the file is present."),
                    section("Narrow it down", "Bypass channel effects and hosted Audio Units one at a time. If one plug-in stops the path, save the project, remove or reset that plug-in, then test again."),
                    section("A gate that never opens", "A NOISE GATE with THRESHOLD above the part stays shut the whole time. Open its window and watch the lamp while the track plays. If it reads SHUT, lower THRESHOLD or check that KEY LOW and KEY HIGH are not filtering out the part itself.")
                ]),
        article("recording-problems", .solve, "Recording does not start or lands late", "Fix missing input, an unarmed track or a timing offset.",
                keywords: ["won't record", "no waveform", "permission", "microphone", "late", "early", "offset"], related: ["record-audio", "latency", "punch-takes"],
                sections: [
                    section("No recording", steps: ["Select an audio track and arm it.", "Choose a live hardware input and confirm its meter moves.", "Allow microphone access in macOS System Settings if LYLLTH has not been authorized.", "If PUNCH is on, confirm the transport reaches the loop brace."]),
                    section("The take is early or late", "Turn off heavy monitoring plug-ins, then record a sharp sound against the click. Adjust LAT by the measured direction and test again. Do not correct the setup by moving every new event."),
                    section("The take is empty", "Check the interface’s hardware routing and gain. A moving macOS input meter does not guarantee the selected LYLLTH channel is the same input.")
                ]),
        article("plugin-problems", .solve, "An Audio Unit will not load", "Recover from validation failure, a missing plug-in or a bad saved state.",
                keywords: ["plugin crash", "au failure", "quarantined", "scan", "validation", "missing plugin"], related: ["audio-units", "no-sound", "large-sessions"],
                sections: [
                    section("Check availability", "Confirm the Audio Unit is installed for the current Mac architecture and appears in AU INST or AU FX. Restart LYLLTH after installing or updating a plug-in."),
                    section("Reset quarantine", "Open LIBRARY → PROJECT and find the failed Audio Unit. Use RESET only after updating, reinstalling or otherwise addressing the failure, then try one load."),
                    section("Open the song safely", "If a project loads but the plug-in does not, keep the channel bypassed and save a copy before replacing it. Preserving the original project keeps the stored state available for a later recovery.", tip: "Freeze or print a crucial third-party instrument before an OS or plug-in update.")
                ]),
        article("missing-media", .solve, "Missing or wrong audio", "Repair a project whose source file cannot be found or does not match.",
                keywords: ["offline", "file not found", "relink", "wrong take", "checksum"], related: ["project-media", "project-files", "audio-import"],
                sections: [
                    section("Find the problem", "Open LIBRARY → PROJECT. Missing items are identified there; the arrangement remains intact so the file can be reconnected without rebuilding edits."),
                    section("Relink", "Choose the missing item, select the correct source, then save. Prefer the original file with matching length and content rather than a different file that happens to share the name."),
                    section("Prevent it", "Keep active work in the .lyllth package and let LYLLTH copy imported or recorded material into project media. Do not edit the package contents in Finder.")
                ]),
        article("siren-problems", .solve, "SIREN hears the wrong thing", "Fix notes it missed, edits you can't hear and a double that won't line up.",
                keywords: ["siren", "wrong notes", "no notes", "pitch correction not working", "align problem", "warble", "artifacts"], related: ["siren-tune", "siren-notes", "siren-align"],
                sections: [
                    section("No sung notes found", "SIREN needs one clear voice. Chords, two singers in one take or a vocal with heavy reverb recorded in leave it nothing steady to follow. Use the dry take. If the part was recorded with effects on the input, those effects are in the file now."),
                    section("A note is in the wrong place", "If a note sits an octave off the singer, or a slide became one long note, split or join it before tuning. Breaths and consonants are left alone on purpose. SIREN only changes notes that have a pitch."),
                    section("You can't hear the edit", steps: ["Check the A / B button. BYPASSED means the original is playing.", "Check the event still uses the same take. Edits belong to the recording they were made on, so switching takes leaves the edits behind.", "Give it a second after letting go of a note. SIREN rebuilds the take each time you finish a move."]),
                    section("It sounds warbly or thin", "Big moves cost quality. A note pushed up four semitones sounds more processed than one nudged by thirty cents. If DRIFT is high on a note with strong vibrato, bring it down: flattening a wide vibrato is the hardest thing to hide.", tip: "If a fix sounds processed, lower PITCH or DRIFT on that note and listen again with the whole mix playing.")
                ]),
        article("large-sessions", .solve, "A large session is slow", "Reduce processing load without dismantling the song.",
                keywords: ["cpu", "overload", "dropout", "glitch", "performance", "freeze", "navigation"], related: ["crossfade-consolidate", "folders-groups", "audio-units"],
                sections: [
                    section("Lower the live load", steps: ["Freeze settled instrument or effect-heavy tracks.", "Bypass analyzers and unused Audio Units.", "Use shared buses instead of many identical reverbs.", "Collapse folders and hide panels that are not needed for the current edit."]),
                    section("Find one offender", "If the problem began recently, bypass the last plug-ins added and test the dense section. One look-ahead processor or oversampled synth can cost more than many ordinary channels."),
                    section("Protect the recording path", "For tracking, freeze the mix, bypass high-latency processors and use a simple monitoring chain. Restore the full mix after the take.", tip: "Make performance changes one at a time and replay the same difficult section after each change.")
                ]),

        article("shortcuts", .reference, "Keyboard shortcuts", "The commands worth keeping under your hands.",
                keywords: ["keys", "key commands", "hotkeys", "command", "reference"], related: ["arrangement", "note-editing", "project-files"],
                sections: [
                    section("Global", steps: ["Space — Play or stop", "Command-1 — Sequencer", "Command-2 — Arrangement", "Command-K — Musical Typing", "Command-E — Export", "Command-? — LYLLTH Help", "Shift-Command-O — Open DrumKit project", "Option-Command-S — Save as DrumKit project"]),
                    section("Tracks and sounds", steps: ["Command-T — Add a track", "Command-[ / Command-] — Previous or next sound on the selected track", "Shift-Command-D — DRUM SYNTH", "Shift-Command-K — Kits", "Shift-Command-L — LUNATK", "Up / Down in DRUM SYNTH — Play through the sounds", "Left / Right in DRUM SYNTH — Change category", "Command-Return in DRUM SYNTH — Load onto the track"]),
                    section("Arrangement", steps: ["Command-C / Command-X / Command-V — Copy, cut or paste audio", "Command-D — Duplicate the selected audio event or place the selected pattern again", "Delete — Remove the selected event or pattern placement", "S — Split selected audio at the edit cursor", "Return — Edit the selected pattern in Sequencer", "+ or = / - — Transpose selected audio; Shift moves four semitones, Command an octave", "* / / — Raise or lower selected event gain"]),
                    section("Piano roll", steps: ["Command-A — Select all notes", "Command-D — Duplicate selected notes", "Delete — Delete selected notes", "Q — Quantize selection, or all notes if none are selected", "Left / Right — Move by the snap value", "Up / Down — Transpose one semitone", "Shift-Up / Shift-Down — Transpose one octave", "Command-scroll — Zoom"]),
                    section("Right-click menus", steps: ["Right-click or Control-click — Open the menu for a region or lane", "Escape — Close it"]),
                    section("SIREN", steps: ["Double-click an audio event — Open it in SIREN", "Drag a note up or down — Retune by semitones; hold Option for cents", "Up / Down — Move selected notes a semitone", "Option-Up / Option-Down — Move selected notes ten cents", "Double-click a note — Split it", "Command-A — Select every note"]),
                    section("Standard macOS document commands", "Command-N, Command-O, Command-S, Save As, undo and redo follow the macOS document menus.", tip: "If a key seems inactive, click the area you intend to edit. LYLLTH routes editing keys to the focused piano roll or arrangement.")
                ]),
        article("file-formats", .reference, "File formats and interchange", "What LYLLTH opens, saves and exports.",
                keywords: ["format", "lyllth", "fkit", "wav", "m4a", "zip", "midi"], related: ["project-files", "drumkit-continuity", "export-mix"],
                sections: [
                    section("Project", ".lyllth is the full Mac project package. .fkit is the shared NIGHTSHAPE DRUMKIT interchange format for iPhone continuity."),
                    section("Audio delivery", "WAV 24-bit is the normal finished master. WAV 32-bit float is for more processing headroom. M4A AAC is a compact listening file. Stems are delivered as aligned audio files in a ZIP."),
                    section("Performance data", "Standard MIDI files carry notes and compatible performance data, not the LUNATK sound, channel effects or recorded audio.")
                ]),
        article("signal-flow", .reference, "Signal flow and glossary", "A plain-language map of the terms used throughout LYLLTH.",
                keywords: ["glossary", "signal path", "definitions", "bus", "send", "insert", "stem"], related: ["core-concepts", "mixer-routing", "file-formats"],
                sections: [
                    section("Signal flow", "Source or instrument → track effects → channel level and pan → sends and output destination → bus or MAIN → export."),
                    section("Insert, send and bus", "An insert changes the whole channel in series. A send taps some of the channel into another path. A bus receives one or more routed signals so they can be processed or controlled together."),
                    section("Event, clip and region", "An audio event is a placed piece of recorded or imported audio. A note clip contains MIDI notes. A pattern region places one sequencer pattern in the song."),
                    section("Stem and master", "A stem is one aligned part of the mix for transfer. A master is the complete stereo result.")
                ]),
        article("tips", .reference, "Tips that save time", "Small habits that keep sessions fast, clear and recoverable.",
                keywords: ["tricks", "workflow", "best practice", "speed", "productivity"], related: ["shortcuts", "project-files", "large-sessions"],
                sections: [
                    section("While writing", steps: ["Duplicate a pattern before making the fill or chorus version.", "Use Command-1 and Command-2 instead of reaching for the workspace switch.", "Loop four or eight bars while choosing sounds, then remove the loop for a full-song check.", "Name tracks as soon as their job is clear."]),
                    section("While editing", steps: ["Set event gain before riding the channel fader.", "Keep one muted safety copy before a radical audio edit.", "Use the edit cursor as the destination for both split and paste.", "Consolidate only after fades, pitch and timing are approved."]),
                    section("While mixing", steps: ["Balance before adding processors.", "Use a shared bus for common space.", "Return automation to READ after every write pass.", "Freeze settled tracks before recording through a busy session."]),
                    section("Before sharing", steps: ["Save a named version.", "Export a WAV and listen outside LYLLTH.", "Test stems in a blank session.", "Keep the .lyllth master even when sending .fkit or MIDI."])
                ])
    ]

    static func search(_ query: String, category: LYHelpCategory? = nil) -> [LYHelpArticle] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let pool = category.map { selected in articles.filter { $0.category == selected } } ?? articles
        guard !terms.isEmpty else { return pool }

        return pool.compactMap { article -> (LYHelpArticle, Int)? in
            let title = article.title.lowercased()
            let summary = article.summary.lowercased()
            let keywords = article.keywords.joined(separator: " ").lowercased()
            guard terms.allSatisfy({ article.searchableText.contains($0) }) else { return nil }
            let score = terms.reduce(0) { partial, term in
                partial + (title.contains(term) ? 12 : 0)
                    + (keywords.contains(term) ? 7 : 0)
                    + (summary.contains(term) ? 4 : 0)
            }
            return (article, score)
        }
        .sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.title < rhs.0.title : lhs.1 > rhs.1
        }
        .map(\.0)
    }

    static func article(withID id: String?) -> LYHelpArticle? {
        guard let id else { return nil }
        return articles.first { $0.id == id }
    }

    private static func article(
        _ id: String,
        _ category: LYHelpCategory,
        _ title: String,
        _ summary: String,
        keywords: [String],
        related: [String],
        sections: [LYHelpSection]
    ) -> LYHelpArticle {
        LYHelpArticle(id: id, category: category, title: title, summary: summary,
                      keywords: keywords, sections: sections, related: related)
    }

    private static func section(
        _ title: String,
        _ paragraph: String? = nil,
        steps: [String] = [],
        tip: String? = nil,
        note: String? = nil
    ) -> LYHelpSection {
        LYHelpSection(title, paragraphs: paragraph.map { [$0] } ?? [], steps: steps, tip: tip, note: note)
    }
}

/// Help text with every run of digits in the NIGHTSHAPE number face, the
/// one numbers use everywhere in the apps. Only digits switch, so periods
/// and dashes in a sentence stay in the text's own face.
private func numbered(_ string: String, _ font: Font, size: CGFloat) -> Text {
    var result = Text("")
    var run = ""
    var runIsDigits = false
    func flush() {
        guard !run.isEmpty else { return }
        result = result + Text(run).font(runIsDigits ? LYLLTHTheme.value(size) : font)
        run = ""
    }
    for character in string {
        let isDigit = character.isNumber
        if isDigit != runIsDigits { flush(); runIsDigits = isDigit }
        run.append(character)
    }
    flush()
    return result
}

struct LYHelpCenterView: View {
    @State private var query = ""
    @State private var category: LYHelpCategory? = .start
    @State private var selectedArticleID = "welcome"
    @FocusState private var searchFocused: Bool
    @AppStorage(LYPreferenceKey.interfaceTextScale) private var textScale = 1.0
    @AppStorage(LYPreferenceKey.highContrast) private var highContrast = false

    private var results: [LYHelpArticle] {
        LYHelpLibrary.search(query, category: query.isEmpty ? category : nil)
    }

    private var selectedArticle: LYHelpArticle {
        LYHelpLibrary.article(withID: selectedArticleID) ?? results.first ?? LYHelpLibrary.articles[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                categoryColumn
                    .frame(width: 184)
                Rectangle().fill(LYLLTHTheme.line).frame(width: 1)
                resultColumn
                    .frame(width: 276)
                Rectangle().fill(LYLLTHTheme.line).frame(width: 1)
                articleColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(LYLLTHTheme.background)
        .preferredColorScheme(.dark)
        .onChange(of: results.map(\.id)) { _, ids in
            if !ids.contains(selectedArticleID), let first = ids.first { selectedArticleID = first }
        }
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
        .id("\(textScale)-\(highContrast)")
    }

    private var header: some View {
        HStack(spacing: 18) {
            HStack(spacing: 9) {
                Text("LYLLTH")
                    .font(LYLLTHTheme.wordmark(22))
                    .foregroundStyle(LYLLTHTheme.text)
                Text("HELP")
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .tracking(2.2)
                    .foregroundStyle(LYLLTHTheme.teal)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(query.isEmpty ? LYLLTHTheme.metadata : LYLLTHTheme.teal)
                TextField("Search controls, tasks or problems", text: $query)
                    .textFieldStyle(.plain)
                    .font(LYLLTHTheme.body(12))
                    .foregroundStyle(LYLLTHTheme.text)
                    .focused($searchFocused)
                    .accessibilityLabel("Search LYLLTH Help")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(LYLLTHTheme.metadata)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear help search")
                }
                Text("⌘F")
                    .font(LYLLTHTheme.value(9))
                    .foregroundStyle(LYLLTHTheme.metadata)
            }
            .padding(.horizontal, 12)
            .frame(width: 390, height: 32)
            .background(LYLLTHTheme.deck)
            .overlay(Rectangle().stroke(searchFocused ? LYLLTHTheme.teal.opacity(0.8) : LYLLTHTheme.lineStrong, lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .bottom) { LYHairline() }
    }

    private var categoryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GUIDE")
                .font(LYLLTHTheme.label(9, weight: .bold))
                .tracking(2)
                .foregroundStyle(LYLLTHTheme.metadata)
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(LYHelpCategory.allCases) { item in
                        let isSelected = category == item && query.isEmpty
                        Button {
                            query = ""
                            category = item
                            if let first = LYHelpLibrary.search("", category: item).first {
                                selectedArticleID = first.id
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isSelected ? LYLLTHTheme.teal : LYLLTHTheme.metadata)
                                    .frame(width: 15)
                                Text(item.rawValue.uppercased())
                                    .font(LYLLTHTheme.label(9.5, weight: isSelected ? .bold : .medium))
                                    .tracking(0.8)
                                    .foregroundStyle(isSelected ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                            .background(isSelected ? LYLLTHTheme.panelRaised : Color.clear)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(isSelected ? LYLLTHTheme.teal : Color.clear).frame(width: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 8)
            Text("COMMAND-?  OPEN HELP")
                .font(LYLLTHTheme.label(7.5, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(LYLLTHTheme.metadata)
                .padding(14)
        }
        .background(LYLLTHTheme.deck)
    }

    private var resultColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(query.isEmpty ? (category?.rawValue.uppercased() ?? "ALL TOPICS") : "SEARCH RESULTS")
                    .font(LYLLTHTheme.label(9, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(LYLLTHTheme.metadata)
                Spacer()
                Text("\(results.count)")
                    .font(LYLLTHTheme.value(10))
                    .foregroundStyle(LYLLTHTheme.metadata)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .overlay(alignment: .bottom) { LYHairline() }

            if results.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("NO MATCH")
                        .font(LYLLTHTheme.label(11, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(LYLLTHTheme.text)
                    numbered("Try the name of a control, a job such as ‘record vocals’, or a symptom such as ‘late take’.", LYLLTHTheme.body(12), size: 12)
                        .lineSpacing(3)
                        .foregroundStyle(LYLLTHTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { article in
                            articleRow(article)
                        }
                    }
                }
            }
        }
        .background(LYLLTHTheme.panel)
    }

    private func articleRow(_ article: LYHelpArticle) -> some View {
        let selected = article.id == selectedArticleID
        return Button {
            selectedArticleID = article.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                numbered(article.title.uppercased(), LYLLTHTheme.label(10, weight: selected ? .bold : .medium), size: 10)
                    .tracking(0.9)
                    .foregroundStyle(selected ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                    .multilineTextAlignment(.leading)
                numbered(article.summary, LYLLTHTheme.body(11.5), size: 11.5)
                    .foregroundStyle(LYLLTHTheme.metadata)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(selected ? LYLLTHTheme.panelRaised : Color.clear)
            .overlay(alignment: .leading) {
                Rectangle().fill(selected ? LYLLTHTheme.indigo : Color.clear).frame(width: 2)
            }
            .overlay(alignment: .bottom) { LYHairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var articleColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedArticle.category.rawValue.uppercased())
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(LYLLTHTheme.teal)
                numbered(selectedArticle.title.uppercased(), LYLLTHTheme.label(26, weight: .bold), size: 26)
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.text)
                    .padding(.top, 8)
                numbered(selectedArticle.summary, LYLLTHTheme.body(15), size: 15)
                    .foregroundStyle(LYLLTHTheme.secondary)
                    .lineSpacing(4)
                    .padding(.top, 10)

                if selectedArticle.sections.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IN THIS ARTICLE")
                            .font(LYLLTHTheme.label(8.5, weight: .bold))
                            .tracking(1.8)
                            .foregroundStyle(LYLLTHTheme.metadata)
                        ForEach(selectedArticle.sections) { section in
                            HStack(spacing: 8) {
                                Rectangle().fill(LYLLTHTheme.indigo).frame(width: 9, height: 1)
                                numbered(section.title, LYLLTHTheme.body(12.5), size: 12.5)
                                    .foregroundStyle(LYLLTHTheme.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LYLLTHTheme.deck)
                    .overlay(Rectangle().stroke(LYLLTHTheme.line, lineWidth: 1))
                    .padding(.top, 22)
                }

                ForEach(Array(selectedArticle.sections.enumerated()), id: \.element.id) { index, section in
                    helpSection(section, number: index + 1)
                }

                let related = selectedArticle.related.compactMap { LYHelpLibrary.article(withID: $0) }
                if !related.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("KEEP GOING")
                            .font(LYLLTHTheme.label(8.5, weight: .bold))
                            .tracking(1.8)
                            .foregroundStyle(LYLLTHTheme.metadata)
                        HStack(spacing: 8) {
                            ForEach(related) { item in
                                Button {
                                    query = ""
                                    category = item.category
                                    selectedArticleID = item.id
                                } label: {
                                    numbered(item.title.uppercased(), LYLLTHTheme.label(8.5, weight: .bold), size: 8.5)
                                        .tracking(0.6)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .foregroundStyle(LYLLTHTheme.secondary)
                                        .padding(.horizontal, 10)
                                        .frame(height: 28)
                                        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 30)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LYLLTHTheme.background)
    }

    private func helpSection(_ section: LYHelpSection, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", number))
                    .font(LYLLTHTheme.value(10))
                    .foregroundStyle(LYLLTHTheme.purple)
                numbered(section.title.uppercased(), LYLLTHTheme.label(15, weight: .bold), size: 15)
                    .tracking(0.9)
                    .foregroundStyle(LYLLTHTheme.text)
            }
            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                numbered(paragraph, LYLLTHTheme.body(13.5), size: 13.5)
                    .foregroundStyle(LYLLTHTheme.secondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                // The box is centered on the capitals of the step's first line,
                // whatever its font size, so number and text read level.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(LYLLTHTheme.value(11))
                        .foregroundStyle(LYLLTHTheme.teal)
                        .frame(width: 20, height: 20)
                        .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.65), lineWidth: 1))
                        .alignmentGuide(.firstTextBaseline) { box in
                            box.height / 2 + Self.stepSize * Self.interCapHeight / 2
                        }
                    numbered(step, LYLLTHTheme.body(Self.stepSize), size: Self.stepSize)
                        .foregroundStyle(LYLLTHTheme.secondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let tip = section.tip {
                callout("TIP", tip, color: LYLLTHTheme.teal)
            }
            if let note = section.note {
                callout("NOTE", note, color: LYLLTHTheme.purple)
            }
        }
        .padding(.top, 28)
    }

    private static let stepSize: CGFloat = 13.5
    /// Inter's capital height as a fraction of its point size.
    private static let interCapHeight: CGFloat = 0.727

    private func callout(_ label: String, _ body: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Rectangle().fill(color).frame(width: 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(color)
                numbered(body, LYLLTHTheme.body(12.5), size: 12.5)
                    .foregroundStyle(LYLLTHTheme.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LYLLTHTheme.panel)
        .overlay(Rectangle().stroke(LYLLTHTheme.line, lineWidth: 1))
    }
}
