import XCTest
import NightshapeAudioEngine
import AVFoundation
@testable import LYLLTH

final class SessionDocumentTests: XCTestCase {
    func testSessionPackageRoundTrip() throws {
        let source = LYLLTHSessionDocument(session: .starter())
        let wrapper = try source.packageFileWrapper(modifiedAt: source.session.modifiedAt)
        let decoded = try LYLLTHSessionDocument(fileWrapper: wrapper)

        XCTAssertEqual(decoded.session, source.session)
        XCTAssertEqual(wrapper.fileWrappers?["manifest.json"]?.isRegularFile, true)
        XCTAssertEqual(wrapper.fileWrappers?["Audio"]?.isDirectory, true)
    }

    func testStarterExposesFullDesktopSequencer() {
        let session = LYLLTHSession.starter()
        let musicalTracks = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }

        XCTAssertEqual(musicalTracks.count, 16)
        XCTAssertEqual(session.tracks.count, 18)
        XCTAssertEqual(session.songKey, .default)
        XCTAssertEqual(session.activePatternIndex, 0)
        XCTAssertTrue(musicalTracks.allSatisfy { track in
            let clips = track.clips.filter { $0.kind == .pattern || $0.kind == .midi }
            return clips.count == 2 && clips.allSatisfy {
                $0.steps?.count == 16 && $0.stepParameters?.count == 16
            }
        })
        XCTAssertEqual(musicalTracks.filter { $0.isChordTrack == true }.map(\.name), ["DARK POLY"])
        XCTAssertEqual(musicalTracks.first(where: { $0.name == "DARK POLY" })?.isMuted, true)
    }

    func testExpandingChordClipStopsAtNewBlankSpace() throws {
        var clip = try XCTUnwrap(
            LYLLTHSession.starter().tracks
                .first(where: { $0.name == "DARK POLY" })?
                .clips.first
        )

        clip.resizeSequencer(to: 32, isChordTrack: true)

        XCTAssertEqual(clip.steps?.count, 32)
        XCTAssertEqual(clip.stepParameters?.count, 32)
        XCTAssertEqual(clip.stepParameters?[0].chord, 0)
        XCTAssertEqual(clip.stepParameters?[16].chord, ChordLaneCompiler.rest)
        XCTAssertTrue(clip.steps?.dropFirst(16).allSatisfy { !$0 } == true)
    }

    func testVersionOneStarterMigrationRemovesHeldChordDrone() throws {
        var legacy = LYLLTHSession.starter()
        legacy.schemaVersion = 1
        let chordIndex = try XCTUnwrap(legacy.tracks.firstIndex(where: { $0.name == "DARK POLY" }))
        legacy.tracks[chordIndex].isMuted = false
        for clipIndex in legacy.tracks[chordIndex].clips.indices {
            var clip = legacy.tracks[chordIndex].clips[clipIndex]
            var steps = clip.steps ?? []
            var locks = clip.stepParameters ?? []
            steps += Array(repeating: false, count: 16)
            locks += Array(repeating: .default, count: 16)
            clip.steps = steps
            clip.stepParameters = locks
            clip.lengthBeats = 8
            legacy.tracks[chordIndex].clips[clipIndex] = clip
        }

        let project = FileWrapper(regularFileWithContents: try JSONEncoder().encode(legacy))
        let wrapper = FileWrapper(directoryWithFileWrappers: ["project.json": project])
        let decoded = try LYLLTHSessionDocument(fileWrapper: wrapper)
        let migratedChord = try XCTUnwrap(decoded.session.tracks.first(where: { $0.name == "DARK POLY" }))

        XCTAssertEqual(decoded.session.schemaVersion, LYLLTHSession.currentSchemaVersion)
        XCTAssertTrue(migratedChord.isMuted)
        XCTAssertEqual(migratedChord.clips[0].stepParameters?[16].chord, ChordLaneCompiler.rest)
    }

    func testSmartSnapFollowsHorizontalZoom() {
        let state = LYArrangementEditorState.default

        XCTAssertEqual(
            state.gridBeats(bpm: 120, numerator: 4, denominator: 4, sampleRate: 48_000, beatWidth: 12),
            4
        )
        XCTAssertEqual(
            state.gridBeats(bpm: 120, numerator: 4, denominator: 4, sampleRate: 48_000, beatWidth: 40),
            0.5
        )
        XCTAssertEqual(
            state.gridBeats(bpm: 120, numerator: 4, denominator: 4, sampleRate: 48_000, beatWidth: 120),
            0.125
        )
    }

    func testSnapCanBeAbsoluteOrRelative() {
        var state = LYArrangementEditorState.default
        state.snapMode = .beat
        state.snapAlignment = .absolute
        XCTAssertEqual(
            state.snap(rawBeat: 3.7, originalBeat: 0.2, bpm: 120, numerator: 4, denominator: 4, sampleRate: 48_000, beatWidth: 40),
            4
        )

        state.snapAlignment = .relative
        XCTAssertEqual(
            state.snap(rawBeat: 3.7, originalBeat: 0.2, bpm: 120, numerator: 4, denominator: 4, sampleRate: 48_000, beatWidth: 40),
            4.2,
            accuracy: 0.000_001
        )
    }

    func testArrangementEditorStatePersistsInProject() throws {
        var session = LYLLTHSession.starter()
        session.arrangementEditor = LYArrangementEditorState(
            horizontalZoom: 83,
            verticalZoom: 91,
            waveformZoom: 2,
            snapMode: .samples,
            snapAlignment: .relative,
            division: 32,
            showsGrid: false,
            autoHorizontalZoom: false,
            autoVerticalZoom: true
        )

        let source = LYLLTHSessionDocument(session: session)
        let decoded = try LYLLTHSessionDocument(fileWrapper: source.packageFileWrapper())

        XCTAssertEqual(decoded.session.arrangementEditor, session.arrangementEditor)
    }

    func testLegacySessionWithoutKeyOrStepLocksStillDecodes() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "LEGACY",
          "createdAt": 0,
          "modifiedAt": 0,
          "bpm": 120,
          "numerator": 4,
          "denominator": 4,
          "sampleRate": 48000,
          "bitDepth": 24,
          "tracks": [{
            "id": "00000000-0000-0000-0000-000000000002",
            "name": "KICK",
            "kind": "drumkit",
            "accent": "teal",
            "volumeDB": -3,
            "pan": 0,
            "isMuted": false,
            "isSolo": false,
            "clips": [{
              "id": "00000000-0000-0000-0000-000000000003",
              "name": "PATTERN 01",
              "kind": "pattern",
              "startBeat": 0,
              "lengthBeats": 4,
              "steps": [true, false, false, false]
            }],
            "inserts": []
          }]
        }
        """
        let project = FileWrapper(regularFileWithContents: try XCTUnwrap(json.data(using: .utf8)))
        let wrapper = FileWrapper(directoryWithFileWrappers: ["project.json": project])
        let decoded = try LYLLTHSessionDocument(fileWrapper: wrapper)

        XCTAssertNil(decoded.session.songKey)
        XCTAssertNil(decoded.session.activePatternIndex)
        XCTAssertNil(decoded.session.tracks[0].clips[0].stepParameters)
        XCTAssertEqual(decoded.session.tracks[0].clips[0].steps, [true, false, false, false])
    }

    func testLegacyAudioClipGetsNonDestructiveEventDefaults() throws {
        let json = """
        {
          "name": "LEGACY AUDIO",
          "kind": "audio",
          "startBeat": 2,
          "lengthBeats": 4
        }
        """
        let clip = try JSONDecoder().decode(LYClip.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertEqual(clip.sourceStartSeconds, 0)
        XCTAssertNil(clip.sourceDurationSeconds)
        XCTAssertEqual(clip.eventGainDB, 0)
        XCTAssertEqual(clip.pitchSemitones, 0)
        XCTAssertEqual(clip.stretchMode, .off)
        XCTAssertTrue(clip.preservePitch)
    }

    func testAudioEventSplitKeepsSourceLoopAndOffsetsRightHalf() throws {
        let clip = LYClip(
            name: "VOCAL CHOP",
            kind: .audio,
            startBeat: 4,
            lengthBeats: 8,
            sourceRelativePath: "Audio/vocal.wav",
            sourceStartSeconds: 10,
            sourceDurationSeconds: 4,
            eventGainDB: -5.5,
            pitchSemitones: 7,
            stretchMode: .tempo,
            sourceBPM: 96
        )

        let result = try XCTUnwrap(LYAudioEventEditor.split(clip, atBeat: 6))

        XCTAssertEqual(result.left.startBeat, 4)
        XCTAssertEqual(result.left.lengthBeats, 2)
        XCTAssertEqual(result.right.startBeat, 6)
        XCTAssertEqual(result.right.lengthBeats, 6)
        // Both halves keep the whole source loop; the right half enters it
        // where the cut fell, so either can be dragged out to repeat it.
        XCTAssertEqual(result.left.sourceStartSeconds, 10)
        XCTAssertEqual(result.left.sourceDurationSeconds, 4)
        XCTAssertEqual(result.right.sourceStartSeconds, 10)
        XCTAssertEqual(result.right.sourceDurationSeconds, 4)
        XCTAssertEqual(result.left.loopOffsetBeats, 0)
        XCTAssertEqual(result.right.loopOffsetBeats, 2)
        XCTAssertEqual(result.right.eventGainDB, -5.5)
        XCTAssertEqual(result.right.pitchSemitones, 7)
        XCTAssertNotEqual(result.left.id, result.right.id)
        XCTAssertNotEqual(result.left.id, clip.id)
    }

    func testCycleBeatsFollowsStretchMode() {
        var clip = LYClip(
            name: "LOOP",
            kind: .audio,
            startBeat: 0,
            lengthBeats: 4,
            sourceRelativePath: "loop.wav",
            sourceStartSeconds: 0,
            sourceDurationSeconds: 2.5,
            stretchMode: .tempo,
            sourceBPM: 96
        )
        // 2.5 s at 96 BPM is four beats, whatever the project tempo.
        XCTAssertEqual(LYAudioEventTiming.cycleBeats(for: clip, projectBPM: 120) ?? 0, 4, accuracy: 0.0001)
        clip.stretchMode = .off
        // Unstretched, it lasts 2.5 s of the project's beats.
        XCTAssertEqual(LYAudioEventTiming.cycleBeats(for: clip, projectBPM: 120) ?? 0, 5, accuracy: 0.0001)
    }

    func testSongCompilerRepeatsPatternAcrossLongRegion() {
        var session = LYLLTHSession.starter()
        session.isLoopEnabled = false
        var steps = Array(repeating: false, count: 16)
        steps[0] = true
        steps[8] = true
        let kick = LYClip(name: "P", kind: .pattern, startBeat: 0, lengthBeats: 12,
                          steps: steps, stepParameters: Array(repeating: .default, count: 16))
        session.tracks = [LYTrack(name: "KICK", kind: .drumkit, accent: .teal, clips: [kick])]

        let window = LYSongWindow.resolve(for: session, stepsPerBar: 16)
        XCTAssertEqual(window.barCount, 3)
        let frames = LYSongCompiler.frames(session: session, window: window, stepsPerBar: 16) { _, clip in
            (clip.steps ?? [], clip.stepParameters ?? [])
        }
        XCTAssertEqual(frames.count, 3)
        for frame in frames {
            XCTAssertEqual(frame.tracks[0].activeSteps.enumerated().filter(\.element).map(\.offset), [0, 8])
        }
    }

    func testSongWindowUsesLoopOnlyWhenEnabled() {
        var session = LYLLTHSession.starter()
        session.loopRange = LYLoopRange(startBeat: 4, lengthBeats: 8)
        session.isLoopEnabled = true
        let looped = LYSongWindow.resolve(for: session, stepsPerBar: 16)
        XCTAssertEqual(looped.startBar, 1)
        XCTAssertEqual(looped.barCount, 2)

        session.isLoopEnabled = false
        let whole = LYSongWindow.resolve(for: session, stepsPerBar: 16)
        XCTAssertEqual(whole.startBar, 0)
        XCTAssertGreaterThan(whole.barCount, 2)
    }

    func testTrackEffectsRoundTripWithDrumKitState() throws {
        var document = LYLLTHSessionDocument()
        var flanger = FlangerState.neutral
        flanger.depth = 0.9
        flanger.isBypassed = false
        var rack = LYFXRack()
        rack.flanger = flanger
        rack.order = [.eq, .flanger, .comp]
        rack.reverbSend = 0.4
        document.session.tracks[0].fx = rack
        document.session.tracks[0].isArmed = true

        let reopened = try LYLLTHSessionDocument(fileWrapper: document.packageFileWrapper())
        let restored = try XCTUnwrap(reopened.session.tracks[0].fx)
        XCTAssertEqual(restored.flanger?.depth, 0.9)
        XCTAssertEqual(restored.chain(isMain: false), [.eq, .flanger, .comp])
        XCTAssertEqual(restored.reverbSend, 0.4)
        XCTAssertTrue(restored.isEngaged(.flanger, isMain: false, reverb: .neutral))
        XCTAssertTrue(reopened.session.tracks[0].isArmed)
    }

    func testAudioEventDuplicateIsIndependentAndAdjacent() {
        let clip = LYClip(name: "HIT", kind: .audio, startBeat: 3, lengthBeats: 0.5)
        let copy = LYAudioEventEditor.duplicate(clip)

        XCTAssertNotEqual(copy.id, clip.id)
        XCTAssertEqual(copy.startBeat, 3.5)
        XCTAssertEqual(copy.lengthBeats, clip.lengthBeats)
    }

    func testTethrBeatMapPlannerProducesMonotonicPitchPreservingAnchors() {
        let markers = (0..<12).map { index in
            LYBeatMarker(
                index: index,
                sourceTime: Double(index) * 0.5 + (index.isMultiple(of: 2) ? 0.018 : -0.012),
                confidence: 0.9,
                strength: 0.8
            )
        }
        let map = LYBeatMap(
            sourceBPM: 120,
            beatInterval: 0.5,
            firstBeatTime: 0,
            sourceDuration: 6,
            markers: markers,
            confidence: 0.9,
            averageDriftMS: 32,
            maxDriftMS: 45
        )

        let anchors = LYBeatMapPlanner.anchors(for: map, targetBPM: 100)

        XCTAssertGreaterThan(anchors.count, 8)
        XCTAssertEqual(anchors.first, LYBeatMapAnchor(sourceTime: 0, timelineTime: 0))
        XCTAssertTrue(zip(anchors, anchors.dropFirst()).allSatisfy {
            $0.sourceTime < $1.sourceTime && $0.timelineTime < $1.timelineTime
        })
        let source = 2.75
        let timeline = LYBeatMapPlanner.timelineTime(forSourceTime: source, map: map, targetBPM: 100)
        XCTAssertEqual(
            LYBeatMapPlanner.sourceTime(forTimelineTime: timeline, map: map, targetBPM: 100),
            source,
            accuracy: 0.000_001
        )
    }

    func testTethrBeatMapAnalyzerTracksSyntheticTransientGrid() throws {
        let sampleRate = 8_000.0
        var samples = [Float](repeating: 0, count: Int(sampleRate * 8))
        for beat in 0..<16 {
            let start = Int(Double(beat) * 0.5 * sampleRate)
            for offset in 0..<48 where samples.indices.contains(start + offset) {
                samples[start + offset] = Float(1 - Double(offset) / 48)
            }
        }

        let map = try XCTUnwrap(
            LYBeatMapAnalyzer.detect(monoSamples: samples, sampleRate: sampleRate, sourceBPM: 120)
        )

        XCTAssertEqual(map.sourceBPM, 120)
        XCTAssertGreaterThanOrEqual(map.markers.count, 14)
        XCTAssertGreaterThan(map.confidence, 0.38)
        XCTAssertEqual(map.beatInterval, 0.5, accuracy: 0.000_001)
    }

    func testImportedAudioIsStoredInsideProjectPackage() throws {
        var document = LYLLTHSessionDocument(session: .starter())
        let imported = LYImportedAudio(
            fileName: "voice.wav",
            displayName: "VOICE",
            data: Data([0, 1, 2, 3]),
            duration: 2,
            sampleRate: 48_000,
            channelCount: 1,
            waveformPeaks: [0.1, 0.8, 0.3],
            sourceBPM: 120,
            beatMap: nil
        )

        let clipID = document.addImportedAudio(imported, toTrackID: nil, atBeat: 4)
        let wrapper = try document.packageFileWrapper()
        let reopened = try LYLLTHSessionDocument(fileWrapper: wrapper)
        let clip = try XCTUnwrap(
            reopened.session.tracks.flatMap(\.clips).first(where: { $0.id == clipID })
        )

        XCTAssertEqual(reopened.audioAssets["voice.wav"], imported.data)
        XCTAssertEqual(clip.sourceRelativePath, "voice.wav")
        XCTAssertEqual(clip.startBeat, 4)
        XCTAssertEqual(clip.sourceDurationSeconds, 2)
        XCTAssertEqual(clip.waveformPeaks, imported.waveformPeaks)
        XCTAssertEqual(clip.sourceSampleRate, 48_000)
        XCTAssertEqual(clip.sourceChannelCount, 1)
    }

    func testAudioEventRendererAppliesTempoDurationAndPitchPath() async throws {
        let sampleRate = 44_100.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate))
        )
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData?[0][frame] = Float(sin(2 * Double.pi * 220 * Double(frame) / sampleRate) * 0.2)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyllth-render-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let data = try Data(contentsOf: url)
        let clip = LYClip(
            name: "TEST",
            kind: .audio,
            startBeat: 0,
            lengthBeats: 2,
            sourceRelativePath: "test.wav",
            sourceDurationSeconds: 1,
            eventGainDB: -6,
            pitchSemitones: 12,
            stretchMode: .tempo,
            sourceBPM: 100
        )

        let rendered = try await LYAudioEventRenderer.render(
            data: data,
            fileExtension: "wav",
            clip: clip,
            projectBPM: 200
        )

        XCTAssertEqual(rendered.format.sampleRate, sampleRate)
        XCTAssertEqual(Double(rendered.frameLength) / sampleRate, 0.5, accuracy: 0.02)
        let peak = (0..<Int(rendered.frameLength)).map { abs(rendered.floatChannelData?[0][$0] ?? 0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.01)
        XCTAssertLessThan(peak, 0.2)
    }
}
