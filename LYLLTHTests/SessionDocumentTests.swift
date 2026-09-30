import XCTest
import NightshapeAudioEngine
import AVFoundation
@testable import LYLLTH

final class SessionDocumentTests: XCTestCase {
    @MainActor
    func testDocumentHistoryRegistersUndoAndRedo() {
        var applied = LYLLTHSession.starter()
        let projectID = applied.id
        let history = LYDocumentHistory()
        let manager = UndoManager()
        history.begin(applied)
        var edited = applied
        edited.bpm = 137
        history.record(edited, undoManager: manager) { applied = $0 }
        applied = edited
        history.flush()

        XCTAssertTrue(manager.canUndo)
        manager.undo()
        XCTAssertEqual(applied.bpm, 118)
        XCTAssertTrue(manager.canRedo)
        manager.redo()
        XCTAssertEqual(applied.bpm, 137)
        LYRecoveryJournal.discard(projectID: projectID)
    }

    func testSessionPackageRoundTrip() throws {
        let source = LYLLTHSessionDocument(session: .starter())
        let wrapper = try source.packageFileWrapper(modifiedAt: source.session.modifiedAt)
        let decoded = try LYLLTHSessionDocument(fileWrapper: wrapper)

        XCTAssertEqual(decoded.session, source.session)
        XCTAssertEqual(wrapper.fileWrappers?["manifest.json"]?.isRegularFile, true)
        XCTAssertEqual(wrapper.fileWrappers?["Audio"]?.isDirectory, true)
        XCTAssertEqual(wrapper.fileWrappers?["Recovery"]?.isDirectory, true)
        XCTAssertEqual(wrapper.fileWrappers?["Backups"]?.isDirectory, true)
    }

    func testCorruptPrimaryFallsBackToPackageRecoveryCopy() throws {
        let source = LYLLTHSessionDocument(session: .starter())
        let wrapper = try source.packageFileWrapper()
        var children = try XCTUnwrap(wrapper.fileWrappers)
        children["project.json"] = FileWrapper(regularFileWithContents: Data("not json".utf8))
        let damaged = FileWrapper(directoryWithFileWrappers: children)

        let recovered = try LYLLTHSessionDocument(fileWrapper: damaged)

        XCTAssertEqual(recovered.session.id, source.session.id)
        XCTAssertEqual(recovered.session.name, source.session.name)
        XCTAssertEqual(recovered.session.tracks, source.session.tracks)
    }

    func testCorruptPrimaryAndRecoveryFallBackToPreviousBackup() throws {
        let source = LYLLTHSessionDocument(session: .starter())
        let wrapper = try source.packageFileWrapper()
        var children = try XCTUnwrap(wrapper.fileWrappers)
        children["project.json"] = FileWrapper(regularFileWithContents: Data("bad".utf8))
        children["Recovery"] = FileWrapper(directoryWithFileWrappers: [
            "project.json": FileWrapper(regularFileWithContents: Data("also bad".utf8))
        ])

        let recovered = try LYLLTHSessionDocument(fileWrapper: FileWrapper(directoryWithFileWrappers: children))

        XCTAssertEqual(recovered.session.id, source.session.id)
        XCTAssertEqual(recovered.session.tracks, source.session.tracks)
    }

    func testMissingMediaOpensAsRelinkablePlaceholder() throws {
        var source = LYLLTHSessionDocument(session: .starter())
        let imported = LYImportedAudio(fileName: "voice.wav", displayName: "VOICE", data: Data([1, 2, 3]),
                                       duration: 1, sampleRate: 48_000, channelCount: 1,
                                       waveformPeaks: [0.5], sourceBPM: nil, beatMap: nil)
        _ = source.addImportedAudio(imported, toTrackID: nil, atBeat: 0)
        let wrapper = try source.packageFileWrapper()
        var children = try XCTUnwrap(wrapper.fileWrappers)
        children["Audio"] = FileWrapper(directoryWithFileWrappers: [:])

        var opened = try LYLLTHSessionDocument(fileWrapper: FileWrapper(directoryWithFileWrappers: children))

        XCTAssertEqual(opened.missingAudioNames, ["voice.wav"])
        XCTAssertEqual(opened.mediaIntegrityIssues, [LYMediaIntegrityIssue(kind: .missing, name: "voice.wav")])
        let replacement = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: replacement) }
        try Data([9, 8, 7]).write(to: replacement)
        try opened.relinkAudio(named: "voice.wav", from: replacement)
        XCTAssertTrue(opened.missingAudioNames.isEmpty)
        XCTAssertEqual(opened.audioData(for: "voice.wav"), Data([9, 8, 7]))
    }

    func testOrphanCleanupKeepsReferencedTakeSources() throws {
        var document = LYLLTHSessionDocument(session: .starter())
        let used = LYImportedAudio(fileName: "used.wav", displayName: "USED", data: Data([1]), duration: 1,
                                   sampleRate: 48_000, channelCount: 1, waveformPeaks: [], sourceBPM: nil, beatMap: nil)
        _ = document.addImportedAudio(used, toTrackID: nil, atBeat: 0)
        document.audioAssets["orphan.wav"] = Data([2])

        let discard = LYProjectMediaStore.discard
        LYProjectMediaStore.discard = { try FileManager.default.removeItem(at: $0) }
        defer { LYProjectMediaStore.discard = discard }
        XCTAssertEqual(document.orphanedAudioNames, ["orphan.wav"])
        XCTAssertEqual(try document.cleanupOrphanedAudio(), ["orphan.wav"])
        XCTAssertEqual(document.audioAssetNames, ["used.wav"])
    }

    func testUndoNamesDescribeProfessionalActions() {
        let original = LYLLTHSession.starter()
        var tempo = original
        tempo.bpm = 131
        XCTAssertEqual(LYUndoActionName.describe(from: original, to: tempo), "Change Tempo")
        var volume = original
        volume.tracks[0].volumeDB -= 2
        XCTAssertEqual(LYUndoActionName.describe(from: original, to: volume), "Adjust Track Volume")
        var clip = original
        clip.tracks[0].clips[0].lengthBeats += 1
        XCTAssertEqual(LYUndoActionName.describe(from: original, to: clip), "Edit Region")
    }

    func testMediaStoreIsFileBackedAndPackageRoundTrips() throws {
        var document = LYLLTHSessionDocument(session: .starter())
        let imported = LYImportedAudio(
            fileName: "large-take.wav", displayName: "TAKE", data: Data(repeating: 0x4A, count: 1024),
            duration: 1, sampleRate: 48_000, channelCount: 1, waveformPeaks: [0.5], sourceBPM: nil, beatMap: nil
        )
        _ = document.addImportedAudio(imported, toTrackID: nil, atBeat: 0)

        let workingURL = try XCTUnwrap(document.audioURL(for: "large-take.wav"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workingURL.path))
        XCTAssertEqual(document.audioData(for: "large-take.wav"), imported.data)

        let reopened = try LYLLTHSessionDocument(fileWrapper: document.packageFileWrapper())
        XCTAssertEqual(reopened.audioData(for: "large-take.wav"), imported.data)
    }

    func testRecordingAndAudioUnitStateRoundTrip() throws {
        var session = LYLLTHSession.starter()
        session.recordingSettings = LYRecordingSettings(
            preRollBars: 2,
            punchRange: LYLoopRange(startBeat: 8, lengthBeats: 4),
            loopTakes: true,
            inputChannel: 1,
            inputMonitoring: true,
            manualLatencyMS: 3.5
        )
        let take = LYAudioTake(name: "TAKE 01", sourceRelativePath: "take.caf", sourceStartSeconds: 0, durationSeconds: 2)
        var clip = LYClip(name: "REC", kind: .audio, startBeat: 8, lengthBeats: 4, sourceRelativePath: "take.caf")
        clip.takes = [take]
        clip.activeTakeID = take.id
        clip.compSegments = [LYCompSegment(startBeat: 0, lengthBeats: 4, takeID: take.id)]
        let audioIndex = try XCTUnwrap(session.tracks.firstIndex(where: { $0.kind == .audio }))
        session.tracks[audioIndex].clips = [clip]
        session.tracks[0].inserts.append(LYPluginSlot(
            format: .audioUnit,
            identifier: "1635083896-1684234849-1634758764",
            name: "TEST AU",
            manufacturer: "TEST",
            state: Data([1, 2, 3]),
            reportedLatencySeconds: 0.012,
            componentType: 1_635_083_896,
            componentSubType: 1_684_234_849,
            componentManufacturer: 1_634_758_764
        ))

        let reopened = try LYLLTHSessionDocument(fileWrapper: LYLLTHSessionDocument(session: session).packageFileWrapper())

        XCTAssertEqual(reopened.session.recordingSettings, session.recordingSettings)
        XCTAssertEqual(reopened.session.tracks[audioIndex].clips[0].takes, [take])
        XCTAssertEqual(reopened.session.tracks[0].inserts.last?.state, Data([1, 2, 3]))
        XCTAssertEqual(reopened.session.tracks[0].inserts.last?.reportedLatencySeconds, 0.012)
    }

    func testTakeLanePromotionBuildsNonDestructiveComp() throws {
        let first = LYAudioTake(name: "TAKE 01", sourceRelativePath: "take.caf",
                                sourceStartSeconds: 0, durationSeconds: 4)
        let second = LYAudioTake(name: "TAKE 02", sourceRelativePath: "take.caf",
                                 sourceStartSeconds: 4, durationSeconds: 4)
        var clip = LYClip(name: "REC", kind: .audio, startBeat: 0, lengthBeats: 8,
                          sourceRelativePath: "take.caf")
        clip.takes = [first, second]
        clip.activeTakeID = first.id
        clip.compSegments = [LYCompSegment(startBeat: 0, lengthBeats: 8, takeID: first.id)]

        let comp = LYTakeLaneEditor.promote(takeID: second.id, from: 2, to: 5, in: clip)

        XCTAssertEqual(comp.compSegments?.map(\.startBeat), [0, 2, 5])
        XCTAssertEqual(comp.compSegments?.map(\.lengthBeats), [2, 3, 3])
        XCTAssertEqual(comp.compSegments?.map(\.takeID), [first.id, second.id, first.id])
        XCTAssertEqual(comp.takes, clip.takes, "comping never rewrites source takes")
    }

    func testPerTrackAudioInputsRoundTrip() throws {
        var session = LYLLTHSession.starter()
        let audio = try XCTUnwrap(session.tracks.firstIndex(where: { $0.kind == .audio }))
        session.tracks[audio].audioInputChannel = 3
        let back = try JSONDecoder().decode(LYLLTHSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(back.tracks[audio].audioInputChannel, 3)
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

    func testOverlappingAudioEventsGetSymmetricCrossfade() throws {
        let first = LYClip(name: "A", kind: .audio, startBeat: 0, lengthBeats: 4, sourceRelativePath: "a.wav")
        let second = LYClip(name: "B", kind: .audio, startBeat: 3, lengthBeats: 4, sourceRelativePath: "b.wav")
        let result = try XCTUnwrap(LYAudioEventEditor.crossfade(first, second, bpm: 120))
        XCTAssertEqual(result.first.fadeOutSeconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.second.fadeInSeconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.first.fadeCurve, .equalPower)
    }

    func testWarpMarkersCanBeMovedInsertedAndRemoved() throws {
        let marker = LYBeatMarker(index: 1, sourceTime: 0.5, confidence: 0.5, strength: 0.5)
        let map = LYBeatMap(sourceBPM: 120, beatInterval: 0.5, firstBeatTime: 0, sourceDuration: 4,
                            markers: [marker], confidence: 0.8, averageDriftMS: 12, maxDriftMS: 20)
        let moved = LYWarpMarkerEditor.moving(marker.id, to: 0.6, in: map)
        XCTAssertEqual(moved.markers[0].sourceTime, 0.6)
        let inserted = LYWarpMarkerEditor.inserting(sourceTime: 1, beatIndex: 2, in: moved)
        XCTAssertEqual(inserted.markers.map(\.index), [1, 2])
        XCTAssertTrue(LYWarpMarkerEditor.removing(marker.id, from: inserted).markers.allSatisfy { $0.id != marker.id })
    }

    func testFoldersAndMixGroupsSurviveMigrationAndAffectGain() throws {
        var session = LYLLTHSession.blank()
        let ids = Array(session.tracks.prefix(2).map(\.id))
        _ = session.createFolder(name: "DRUMS", trackIDs: ids)
        _ = session.createMixGroup(name: "DRUM BUS", trackIDs: ids)
        session.mixGroups?[0].volumeOffsetDB = -3
        XCTAssertEqual(session.effectiveVolumeDB(for: session.tracks[0]), session.tracks[0].volumeDB - 3)
        let decoded = try JSONDecoder().decode(LYLLTHSession.self, from: JSONEncoder().encode(session)).migratedToCurrentSchema()
        XCTAssertEqual(decoded.trackFolders?.first?.trackIDs, ids)
        XCTAssertEqual(decoded.mixGroups?.first?.trackIDs, ids)
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

@MainActor
final class PatternPlacementTests: XCTestCase {
    /// A session whose patterns were all made in the sequencer and never placed.
    private func unplaced() -> LYLLTHSession {
        var session = LYLLTHSession.starter()
        for t in session.tracks.indices {
            session.tracks[t].clips.removeAll { $0.isPlacement }
            for c in session.tracks[t].clips.indices where session.tracks[t].clips[c].isSequenced {
                session.tracks[t].clips[c].isOffTimeline = true
            }
        }
        return session
    }

    func testUnplacedPatternsAreFlaggedAndPlacingThemFillsTheSong() {
        var session = unplaced()
        XCTAssertTrue(session.hasPatternsOutsideSong)
        XCTAssertFalse(session.isPatternInSong(0))

        session.placePatternInSong(0)

        XCTAssertFalse(session.hasPatternsOutsideSong)
        XCTAssertTrue(session.isPatternInSong(0))
        let drums = session.tracks.filter { $0.kind == .drumkit }
        XCTAssertFalse(drums.isEmpty)
        XCTAssertTrue(drums.allSatisfy { !$0.songRegions.isEmpty })
    }

    func testPlacingAgainAddsAPlacementAfterTheFirst() {
        var session = unplaced()
        session.placePatternInSong(0)
        session.placePatternInSong(0)
        let kick = session.tracks.first { $0.kind == .drumkit }!
        let regions = kick.songRegions.sorted { $0.startBeat < $1.startBeat }
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[1].patternSourceID, regions[0].id)
        XCTAssertGreaterThanOrEqual(regions[1].startBeat, regions[0].startBeat + regions[0].lengthBeats - 0.001)
    }
}

final class DrumRenderCacheTests: XCTestCase {
    func testCacheKeyIsStableAndFollowsSettings() throws {
        let preset = try XCTUnwrap(LYDrumSounds.presets.first)
        XCTAssertEqual(LYDrumSounds.cacheKey(for: preset), LYDrumSounds.cacheKey(for: preset))
        XCTAssertEqual(LYDrumSounds.cacheKey(for: preset).count, 16)
        let other = try XCTUnwrap(LYDrumSounds.presets.dropFirst().first)
        XCTAssertNotEqual(LYDrumSounds.cacheKey(for: preset), LYDrumSounds.cacheKey(for: other))
    }
}

final class BlankSongTests: XCTestCase {
    func testBlankSongHasTracksButNothingProgrammed() {
        let session = LYLLTHSession.blank()
        let musical = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }
        XCTAssertFalse(musical.isEmpty)
        for track in musical {
            XCTAssertEqual(track.patterns.count, 1, track.name)
            XCTAssertFalse(track.patterns[0].steps?.contains(true) ?? false, track.name)
            XCTAssertTrue(track.patterns[0].stepParameters?.allSatisfy { $0.chord == nil } ?? true, track.name)
            XCTAssertEqual(track.songRegions.count, 1, track.name)
        }
        XCTAssertFalse(session.hasPatternsOutsideSong)
    }
}

@MainActor
final class AudioUnitValidationTests: XCTestCase {
    private func storeURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("au-validation-\(UUID().uuidString).json")
    }

    func testThreeFailuresQuarantineAndSuccessClears() {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LYAudioUnitValidationStore(url: url)
        let error = NSError(domain: "test", code: 1)
        for _ in 0..<2 { store.registerFailure("aufx:test", error: error) }
        XCTAssertFalse(store.isQuarantined("aufx:test"))
        store.registerFailure("aufx:test", error: error)
        XCTAssertTrue(store.isQuarantined("aufx:test"))
        XCTAssertTrue(LYAudioUnitValidationStore(url: url).isQuarantined("aufx:test"), "quarantine survives relaunch")
        store.reset("aufx:test")
        XCTAssertFalse(LYAudioUnitValidationStore(url: url).isQuarantined("aufx:test"))
    }

    func testALoadThatNeverFinishedCountsAsAFailureNextLaunch() {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        LYAudioUnitValidationStore(url: url).beginLoad("aumu:crashy")
        // LYLLTH "crashed" here: the load never ended.
        let relaunched = LYAudioUnitValidationStore(url: url)
        XCTAssertEqual(relaunched.records["aumu:crashy"]?.consecutiveFailures, 1)
        XCTAssertEqual(LYAudioUnitValidationStore(url: url).records["aumu:crashy"]?.consecutiveFailures, 1,
                       "counted once, not on every later launch")
    }

    func testAFinishedLoadIsNotCountedAsACrash() {
        let url = storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LYAudioUnitValidationStore(url: url)
        store.beginLoad("aufx:fine")
        store.registerSuccess("aufx:fine")
        XCTAssertEqual(LYAudioUnitValidationStore(url: url).records["aufx:fine"]?.consecutiveFailures, 0)
    }
}

final class CompPlaybackTests: XCTestCase {
    private func loopRecording() -> (LYClip, LYAudioTake, LYAudioTake) {
        let first = LYAudioTake(name: "TAKE 01", sourceRelativePath: "rec.caf", sourceStartSeconds: 0, durationSeconds: 4)
        let second = LYAudioTake(name: "TAKE 02", sourceRelativePath: "rec.caf", sourceStartSeconds: 4, durationSeconds: 4)
        var clip = LYClip(name: "REC", kind: .audio, startBeat: 8, lengthBeats: 8,
                          sourceRelativePath: "rec.caf", sourceStartSeconds: 0, sourceDurationSeconds: 4)
        clip.takes = [first, second]
        clip.activeTakeID = first.id
        clip.compSegments = [LYCompSegment(startBeat: 0, lengthBeats: 8, takeID: first.id)]
        return (clip, first, second)
    }

    func testCompPlaysEachSectionFromItsTake() {
        let (clip, first, second) = loopRecording()
        let comp = LYTakeLaneEditor.promote(takeID: second.id, from: 2, to: 5, in: clip)
        let pieces = LYTakeLaneEditor.pieces(of: comp)

        XCTAssertEqual(pieces.map(\.startBeat), [8, 10, 13])
        XCTAssertEqual(pieces.map(\.lengthBeats), [2, 3, 3])
        XCTAssertEqual(pieces.map(\.sourceStartSeconds), [first.sourceStartSeconds, second.sourceStartSeconds, first.sourceStartSeconds])
        // Each piece enters its take where the section falls in the region.
        XCTAssertEqual(pieces.map(\.loopOffsetBeats), [0, 2, 5])
        XCTAssertEqual(pieces[0].fadeOutSeconds, LYTakeLaneEditor.compSeamSeconds)
        XCTAssertEqual(pieces[1].fadeInSeconds, LYTakeLaneEditor.compSeamSeconds)
        XCTAssertTrue(pieces.allSatisfy { $0.compSegments == nil && $0.takes == nil })
    }

    func testChoosingAWholeTakeChangesWhatPlays() {
        let (clip, _, second) = loopRecording()
        let chosen = LYTakeLaneEditor.chooseWholeTake(second.id, in: clip)
        XCTAssertEqual(LYTakeLaneEditor.pieces(of: chosen).map(\.sourceStartSeconds), [second.sourceStartSeconds])
    }

    func testPunchTrimCarriesToEveryTake() {
        var (clip, _, second) = loopRecording()
        clip.sourceStartSeconds = 1  // punched in one second into the pass
        let chosen = LYTakeLaneEditor.chooseWholeTake(second.id, in: clip)
        XCTAssertEqual(LYTakeLaneEditor.pieces(of: chosen).first?.sourceStartSeconds, 5)
    }

    func testPlainRegionsAreUntouched() {
        var session = LYLLTHSession.starter()
        let audio = session.tracks.firstIndex { $0.kind == .audio }!
        session.tracks[audio].clips = [LYClip(name: "A", kind: .audio, startBeat: 0, lengthBeats: 4, sourceRelativePath: "a.wav")]
        XCTAssertEqual(session.withCompsExpanded(), session)
    }
}

final class DeEsserAndGateRackTests: XCTestCase {
    func testDeEsserAndGateSurviveTheProjectFile() throws {
        var rack = LYFXRack()
        var deEsser = DeEsserState.factoryPresets[1].state
        deEsser.listen = true
        rack.deEsser = deEsser
        rack.noiseGate = NoiseGateState.factoryPresets[2].state
        rack.order = [.noiseGate, .eq, .deEsser]
        let back = try JSONDecoder().decode(LYFXRack.self, from: JSONEncoder().encode(rack))
        XCTAssertEqual(back.deEsser?.frequency, deEsser.frequency)
        XCTAssertEqual(back.deEsser?.listen, false, "LISTEN is never saved on")
        XCTAssertEqual(back.noiseGate, rack.noiseGate)
        XCTAssertTrue(back.isEngaged(.deEsser, isMain: false, reverb: .neutral))
        XCTAssertEqual(back.chain(isMain: false).prefix(3), [.noiseGate, .eq, .deEsser])
    }

    func testTheMenuFilesEveryEffectInAFolder() {
        let offered = FXKind.controlDeckCases.filter { $0.isAvailable(for: .track(UUID())) }
        XCTAssertTrue(offered.contains(.deEsser))
        XCTAssertTrue(offered.contains(.noiseGate))
        XCTAssertEqual(FXKind.deEsser.category, .dynamics)
        XCTAssertEqual(FXKind.noiseGate.title, "NOISE GATE")
    }

}

final class MediaReferenceTests: XCTestCase {
    func testDrumSampleAndFrozenOriginalsAreNotUnusedAudio() throws {
        var document = LYLLTHSessionDocument(session: .starter())
        try document.audioMediaStore.put(Data([1]), named: "fkit-kick.wav")
        try document.audioMediaStore.put(Data([2]), named: "vocal.wav")
        try document.audioMediaStore.put(Data([3]), named: "vocal-take-2.wav")
        try document.audioMediaStore.put(Data([4]), named: "old-sample.wav")
        try document.audioMediaStore.put(Data([5]), named: "freeze.wav")
        try document.audioMediaStore.put(Data([6]), named: "stray.wav")

        let drum = document.session.tracks.firstIndex { $0.kind == .drumkit }!
        document.session.tracks[drum].samplePath = "fkit-kick.wav"

        var original = LYClip(name: "VOCAL", kind: .audio, startBeat: 0, lengthBeats: 4, sourceRelativePath: "vocal.wav")
        original.takes = [LYAudioTake(name: "TAKE 2", sourceRelativePath: "vocal-take-2.wav", sourceStartSeconds: 0, durationSeconds: 1)]
        var frozen = LYTrack(name: "VOX", kind: .audio, accent: .purple)
        frozen.clips = [LYClip(name: "VOX · FREEZE", kind: .audio, startBeat: 0, lengthBeats: 4, sourceRelativePath: "freeze.wav")]
        frozen.frozenState = LYFrozenTrackState(kind: .drumkit, clips: [original], inserts: [], instrumentPlugin: nil, fx: nil,
                                                synth: nil, synthPresetID: nil, drumPresetID: nil, customDrumPreset: nil,
                                                samplePath: "old-sample.wav", automation: nil)
        document.session.tracks.append(frozen)

        XCTAssertEqual(document.orphanedAudioNames, ["stray.wav"])
        let discard = LYProjectMediaStore.discard
        LYProjectMediaStore.discard = { try FileManager.default.removeItem(at: $0) }
        defer { LYProjectMediaStore.discard = discard }
        try document.audioMediaStore.remove("fkit-kick.wav")
        XCTAssertEqual(document.missingAudioNames, ["fkit-kick.wav"])
    }
}

final class TubeAndExciterRackTests: XCTestCase {
    func testTubeAndExciterSurviveTheProjectFile() throws {
        var rack = LYFXRack()
        rack.tube = TubeSaturationState.factoryPresets[3].state
        var exciter = HarmonicExciterState.factoryPresets[1].state
        exciter.listen = true
        rack.exciter = exciter
        rack.order = [.eq, .tube, .exciter]
        let back = try JSONDecoder().decode(LYFXRack.self, from: JSONEncoder().encode(rack))
        XCTAssertEqual(back.tube, rack.tube)
        XCTAssertEqual(back.exciter?.highFrequency, exciter.highFrequency)
        XCTAssertEqual(back.exciter?.listen, false, "LISTEN is never saved on")
        XCTAssertTrue(back.isEngaged(.tube, isMain: false, reverb: .neutral))
        XCTAssertEqual(back.chain(isMain: false).prefix(3), [.eq, .tube, .exciter])
    }

    func testTheyAreFiledUnderTone() {
        let offered = FXKind.controlDeckCases.filter { $0.isAvailable(for: .main) }
        XCTAssertTrue(offered.contains(.tube))
        XCTAssertTrue(offered.contains(.exciter))
        XCTAssertEqual(FXKind.tube.category, .tone)
        XCTAssertEqual(FXKind.exciter.title, "HARMONIC EXCITER")
    }
}

final class PhaserRackTests: XCTestCase {
    func testPhaserSurvivesTheProjectFile() throws {
        var rack = LYFXRack()
        rack.phaser = PhaserState.factoryPresets[4].state
        rack.order = [.eq, .phaser]
        let back = try JSONDecoder().decode(LYFXRack.self, from: JSONEncoder().encode(rack))
        XCTAssertEqual(back.phaser, rack.phaser)
        XCTAssertEqual(back.phaser?.timingMode, .sync)
        XCTAssertTrue(back.isEngaged(.phaser, isMain: false, reverb: .neutral))
        XCTAssertEqual(back.chain(isMain: false).prefix(2), [.eq, .phaser])
    }

    func testAnOlderPhaserFileFillsInDefaults() throws {
        let state = try JSONDecoder().decode(PhaserState.self, from: Data(#"{"stages":12,"isBypassed":false}"#.utf8))
        XCTAssertEqual(state.stages, 12)
        XCTAssertEqual(state.centerHz, PhaserState().centerHz)
        XCTAssertFalse(state.isBypassed)
    }

    func testItIsFiledUnderMotion() {
        let offered = FXKind.controlDeckCases.filter { $0.isAvailable(for: .main) }
        XCTAssertTrue(offered.contains(.phaser))
        XCTAssertEqual(FXKind.phaser.category, .motion)
        XCTAssertEqual(FXKind.phaser.title, "PHASER")
    }
}

final class AddingAnEffectSwitchesItOnTests: XCTestCase {
    /// Logic inserts a plug-in running. Every effect that can be bypassed
    /// must be on once it is added.
    func testEveryInsertIsOnOnceAdded() {
        for kind in FXKind.controlDeckCases where kind != .eq && kind != .reverb {
            for isMain in [false, true] {
                let target: FXTarget = isMain ? .main : .track(UUID())
                guard kind.isAvailable(for: target) else { continue }
                var rack = LYFXRack()
                var chain = rack.chain(isMain: isMain)
                if !chain.contains(kind) { chain.append(kind) }
                rack.order = chain
                rack.engage(kind, isMain: isMain)
                XCTAssertTrue(rack.isEngaged(kind, isMain: isMain, reverb: .neutral), "\(kind.title) is on once added (MAIN: \(isMain))")
                rack.engage(kind, isMain: isMain)
                XCTAssertTrue(rack.isEngaged(kind, isMain: isMain, reverb: .neutral), "engaging twice leaves \(kind.title) on")
            }
        }
    }
}

final class DrumFolderTests: XCTestCase {
    func testANewSongHasItsDrumsInOneClosedFolder() {
        let session = LYLLTHSession.starter()
        let drums = session.tracks.filter { $0.kind == .drumkit }.map(\.id)
        let folder = session.drumFolderIndex.flatMap { session.trackFolders?[$0] }
        XCTAssertEqual(folder?.trackIDs, drums)
        XCTAssertEqual(folder?.isCollapsed, true)
        XCTAssertEqual(session.drumsNested, true)
    }

    func testAnOlderSongIsNestedOnceAndNeverRegrouped() {
        var older = LYLLTHSession.starter()
        older.trackFolders = nil
        older.drumsNested = nil
        let opened = older.migratedToCurrentSchema()
        XCTAssertNotNil(opened.drumFolderIndex)

        var unnested = opened
        unnested.trackFolders = nil
        XCTAssertNil(unnested.migratedToCurrentSchema().drumFolderIndex, "drums taken out of the folder stay out")
    }

    func testDrumsInAnotherFolderStayThere() {
        var older = LYLLTHSession.starter()
        older.trackFolders = nil
        older.drumsNested = nil
        let kick = older.tracks.first { $0.kind == .drumkit }!.id
        _ = older.createFolder(name: "MINE", trackIDs: [kick])
        let opened = older.migratedToCurrentSchema()
        XCTAssertEqual(opened.folder(containing: kick)?.name, "MINE")
        XCTAssertFalse(opened.drumFolderIndex.map { opened.trackFolders![$0].trackIDs.contains(kick) } ?? false)
    }
}
