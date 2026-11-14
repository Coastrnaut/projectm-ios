// StatusEventsTests.swift — ACC-011-T09, T11, T12 (ACC-011-R1-R7, R10; S1, S3; contract C1).
// The router gets ACC-004's announcer with a fake clock, a recording sink and a manual scheduler, so no
// test waits or reads the wall clock. Owner rule 7: each test well under 1 s.
import AudioCore
import CameraLayer
import FrameRecording
import PresentationLifecycle
import XCTest
@testable import projectM_iOS

final class StatusEventsTests: XCTestCase {
    /// A clock, a sink and a scheduler the test drives by hand.
    @MainActor private final class Harness {
        var now: Double = 1_000
        var posted: [String] = []
        var scheduled: [(at: Double, action: @MainActor () -> Void)] = []
        var active = true
        lazy var router: StatusEventRouter = {
            let announcer = AccessibilityAnnouncer(post: { [unowned self] (text: String) in self.posted.append(text) },
                                                   now: { [unowned self] () -> Double in self.now },
                                                   schedule: { [unowned self] (delay: Double, action: @escaping @MainActor () -> Void) in
                                                       self.scheduled.append((self.now + delay, action))
                                                   })
            let router = StatusEventRouter(announcer: announcer,
                                           schedule: { [unowned self] (delay: Double, action: @escaping @MainActor () -> Void) in
                                               self.scheduled.append((self.now + delay, action))
                                           })
            router.isActive = { [unowned self] () -> Bool in self.active }
            return router
        }()

        /// Advances the clock, running every scheduled action that falls due, in time order.
        func advance(by seconds: Double) {
            let end = now + seconds
            while let next = scheduled.enumerated().filter({ $0.element.at <= end }).min(by: { $0.element.at < $1.element.at }) {
                scheduled.remove(at: next.offset)
                now = next.element.at
                next.element.action()
            }
            now = end
        }
    }

    // MARK: - Transition table walk (T09)

    /// One expected row: the event, then what is on screen and what VoiceOver hears.
    private struct Expected {
        let event: StatusEvent
        let id: String
        let visible: String
        let spoken: String?
    }

    @MainActor
    func testTheTransitionTableWalk() {
        let status = "In-App Playback · Active audio"
        let interrupted = "In-App Playback · Interrupted"
        let rows: [Expected] = [
            Expected(event: StatusEventCatalog.source(mode: .inAppPlayback, state: .waiting), id: "X1",
                     visible: "In-App Playback · Waiting", spoken: "In-App Playback · Waiting"),
            Expected(event: StatusEventCatalog.source(mode: .inAppPlayback, state: .active), id: "X1", visible: status, spoken: status),
            Expected(event: StatusEventCatalog.source(mode: .microphone, state: .active, switching: true), id: "X2",
                     visible: "Switching source…", spoken: "Switching source…"),
            Expected(event: StatusEventCatalog.source(mode: .inAppPlayback, state: .interrupted, reason: .interrupted), id: "X3",
                     visible: interrupted,
                     spoken: "\(interrupted). Playback is on hold at its position. It continues when iOS allows it, or press Play."),
            Expected(event: StatusEventCatalog.source(mode: .systemAppCapture, state: .endedBySystem, reason: .endedBySystem),
                     id: "X1", visible: "System/App Capture · Ended by system", spoken: "System/App Capture · Ended by system"),
            Expected(event: StatusEventCatalog.background("Microphone stopped while the app was in the background."), id: "X4",
                     visible: "Microphone stopped while the app was in the background.",
                     spoken: "Microphone stopped while the app was in the background."),
            Expected(event: StatusEventCatalog.route(explanation: "Now playing on Speaker", spoken: "Audio output: Speaker"),
                     id: "X5", visible: "Now playing on Speaker", spoken: "Audio output: Speaker"),
            Expected(event: StatusEventCatalog.frameNotice("Frame saved."), id: "X6", visible: "Frame saved.", spoken: "Frame saved."),
            Expected(event: StatusEventCatalog.frameOffered(), id: "X7", visible: "Frame ready", spoken: "Frame ready"),
            Expected(event: StatusEventCatalog.shareNotice("Shared."), id: "X8", visible: "Shared.", spoken: "Shared."),
            Expected(event: StatusEventCatalog.recording(.recording, elapsed: "0:03"), id: "X9", visible: "REC 0:03",
                     spoken: "Recording started"),
            Expected(event: StatusEventCatalog.recording(.finishing), id: "X10", visible: "Finishing…", spoken: "Recording stopped"),
            Expected(event: StatusEventCatalog.recording(.idle), id: "X11", visible: "Recording ready", spoken: "Recording ready"),
            Expected(event: StatusEventCatalog.recordingNotice(RecordingRefusal.paused.notice), id: "X12",
                     visible: "Resume to record.", spoken: "Resume to record."),
            Expected(event: StatusEventCatalog.recordingNotice("Recording stopped because storage is almost full."), id: "X13",
                     visible: "Recording stopped because storage is almost full.",
                     spoken: "Recording stopped because storage is almost full."),
            Expected(event: StatusEventCatalog.recordingNotice(RecordingFailure.storageFull.notice), id: "X14",
                     visible: "Storage is full; the recording couldn't be saved.",
                     spoken: "Storage is full; the recording couldn't be saved."),
            Expected(event: StatusEventCatalog.recordingNotice("Recording saved."), id: "X14a", visible: "Recording saved.",
                     spoken: "Recording saved."),
            Expected(event: StatusEventCatalog.camera(.requestingAccess), id: "X15", visible: "Camera access requested", spoken: nil),
            Expected(event: StatusEventCatalog.camera(.running, position: .front), id: "X16", visible: "Front camera on",
                     spoken: "Front camera on"),
            Expected(event: StatusEventCatalog.camera(.interrupted), id: "X17",
                     visible: "The camera is paused by the system. It comes back when the camera is free, or tap Retry.",
                     spoken: "The camera is paused by the system. It comes back when the camera is free, or tap Retry."),
            Expected(event: StatusEventCatalog.camera(.idle), id: "X18", visible: "Camera off", spoken: "Camera off"),
            Expected(event: StatusEventCatalog.osc(port: 9000), id: "X19", visible: "OSC listening on port 9000",
                     spoken: "OSC listening on port 9000"),
            Expected(event: StatusEventCatalog.osc(port: nil), id: "X20", visible: "OSC off", spoken: "OSC off"),
            Expected(event: StatusEventCatalog.blackout(.blackedOut), id: "X21", visible: "Output blacked out",
                     spoken: "Output blacked out"),
            Expected(event: StatusEventCatalog.blackout(.restoreWaiting), id: "X22", visible: "Restoring output",
                     spoken: "Restoring output"),
            Expected(event: StatusEventCatalog.blackout(.live), id: "X23", visible: "Output restored", spoken: "Output restored"),
            Expected(event: StatusEventCatalog.recoveryOffer(title: "Last session ended unexpectedly", message: "Reopen it?"),
                     id: "X24", visible: "Last session ended unexpectedly", spoken: "Last session ended unexpectedly Reopen it?"),
            Expected(event: StatusEventCatalog.lastSceneReopened(), id: "X25", visible: "Last scene reopened.",
                     spoken: "Last scene reopened."),
            Expected(event: StatusEventCatalog.repairReport("Intro: 1 repair."), id: "X26", visible: "Intro: 1 repair.",
                     spoken: "Intro: 1 repair."),
        ]
        let harness = Harness()
        for row in rows {
            harness.advance(by: 5)   // past the window, the repeat interval and a caption: each row stands alone
            let before = harness.posted.count
            harness.router.post(row.event)
            XCTAssertEqual(row.event.id, row.id, row.visible)
            XCTAssertEqual(row.event.visibleText, row.visible, row.id)
            if let spoken = row.spoken {
                XCTAssertEqual(harness.posted.last, spoken, row.id)
                XCTAssertEqual(harness.posted.count, before + 1, row.id)
            } else {
                XCTAssertEqual(harness.posted.count, before, "\(row.id): system-presented, no app announcement")
            }
            let captioned = row.event.presentation == .caption
            XCTAssertEqual(harness.router.caption, captioned ? row.visible : nil, row.id)
        }
        XCTAssertEqual(Set(rows.map(\.id)).count, 27, "every row of contract C1 is walked (X1-X26 and X14a)")
    }

    // MARK: - Rate rule and one text per change (S3, R5)

    @MainActor
    func testABurstSpeaksTheFirstAndTheLatestState() {
        let harness = Harness()
        for state in [AudioState.waiting, .active, .silent] {
            harness.router.post(StatusEventCatalog.source(mode: .inAppPlayback, state: state))
            harness.advance(by: 0.3)
        }
        XCTAssertEqual(harness.posted, ["In-App Playback · Waiting"])
        harness.advance(by: 1)
        XCTAssertEqual(harness.posted, ["In-App Playback · Waiting", "In-App Playback · Audio received — silent"],
                       "at most two announcements, ending on the latest state")
        XCTAssertEqual(harness.router.announcer.lastSpoken, "source|In-App Playback · Audio received — silent")
    }

    @MainActor
    func testOneInterruptionSpeaksOnce() {
        let harness = Harness()
        let event = StatusEventCatalog.source(mode: .inAppPlayback, state: .interrupted, reason: .interrupted)
        harness.router.post(event)   // the state's .onChange
        harness.router.post(event)   // the stop reason's .onChange, same change
        harness.advance(by: 3)
        XCTAssertEqual(harness.posted.count, 1, "the identical second text is dropped")
    }

    @MainActor
    func testKindsAreIndependent() {
        let harness = Harness()
        harness.router.post(StatusEventCatalog.source(mode: .inAppPlayback, state: .active))
        harness.router.post(StatusEventCatalog.recording(.recording))
        harness.router.post(StatusEventCatalog.blackout(.blackedOut))
        XCTAssertEqual(harness.posted.count, 3, "a source change never swallows a recording or blackout change")
    }

    // MARK: - Background suppression (R10)

    @MainActor
    func testSystemRowsAreDroppedWhileInactive() {
        let harness = Harness()
        harness.active = false
        harness.router.post(StatusEventCatalog.source(mode: .microphone, state: .interrupted))
        harness.router.post(StatusEventCatalog.camera(.interrupted))
        XCTAssertTrue(harness.posted.isEmpty)
        harness.router.post(StatusEventCatalog.camera(.idle))
        XCTAssertEqual(harness.posted, ["Camera off"], "user rows are never dropped")
        XCTAssertEqual(harness.router.log, ["-X1", "-X17", "X18"])
    }

    // MARK: - Captions (T11, R7)

    @MainActor
    func testCaptionsShowForFourSecondsAndANewerOneReplacesThem() {
        let harness = Harness()
        harness.router.post(StatusEventCatalog.blackout(.live))
        XCTAssertEqual(harness.router.caption, "Output restored")
        harness.advance(by: 2)
        harness.router.post(StatusEventCatalog.camera(.idle))
        XCTAssertEqual(harness.router.caption, "Camera off")
        harness.advance(by: 2.5)
        XCTAssertEqual(harness.router.caption, "Camera off", "the first caption's expiry does not clear the newer one")
        harness.advance(by: 1.6)
        XCTAssertNil(harness.router.caption, "cleared 4 s after it appeared")
        harness.router.post(StatusEventCatalog.source(mode: .inAppPlayback, state: .active))
        XCTAssertNil(harness.router.caption, "persistent rows never caption")
    }

    // MARK: - Completeness (T12, S1, research D5)

    /// Every row has visible text and an announcement; only system-presented rows announce nothing.
    private func assertComplete(_ event: StatusEvent, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(event.visibleText.isEmpty, "\(label): visible text", file: file, line: line)
        if event.presentation == .systemPresented {
            XCTAssertTrue(event.announcement.isEmpty, "\(label): system-presented", file: file, line: line)
        } else {
            XCTAssertFalse(event.announcement.isEmpty, "\(label): announcement", file: file, line: line)
        }
        XCTAssertTrue(event.id.hasPrefix("X"), label, file: file, line: line)
    }

    /// Every case of `StopReason`, exhaustive by construction (it carries a value, so it is not CaseIterable).
    private static let allStopReasons: [StopReason] = {
        let all: [StopReason] = [.cancelled, .permissionDenied, .microphoneUnavailable, .inAppPlaybackFailed, .interrupted,
                                 .audioRouteChanged, .endedBySystem, .unsupportedOS, .screenRecordingNotAllowed, .error("x")]
        for reason in all {
            switch reason {
            case .cancelled, .permissionDenied, .microphoneUnavailable, .inAppPlaybackFailed, .interrupted, .audioRouteChanged,
                 .endedBySystem, .unsupportedOS, .screenRecordingNotAllowed, .error: break
            }
        }
        return all
    }()

    private static let allRecordingFailures: [RecordingFailure] = {
        let all: [RecordingFailure] = [.encoderUnavailable, .pixelBufferUnavailable, .writerFailed("x"), .tooFewFrames,
                                       .cancelled, .storageFull]
        for failure in all {
            switch failure {
            case .encoderUnavailable, .pixelBufferUnavailable, .writerFailed, .tooFewFrames, .cancelled, .storageFull: break
            }
        }
        return all
    }()

    @MainActor
    func testEveryStateHasARow() {
        var rows = 0
        for mode in [AudioSourceMode?.none] + AudioSourceMode.allCases.map(Optional.some) {
            for state in AudioState.allCases {
                assertComplete(StatusEventCatalog.source(mode: mode, state: state), "source \(String(describing: mode)) \(state)")
                rows += 1
                for reason in Self.allStopReasons {
                    assertComplete(StatusEventCatalog.source(mode: mode, state: state, reason: reason), "source \(state) \(reason)")
                    XCTAssertFalse(StatusEventCatalog.stopMessage(reason).isEmpty, "FR-015 message for \(reason)")
                }
            }
        }
        assertComplete(StatusEventCatalog.source(mode: .microphone, state: .waiting, switching: true), "switching")
        for state in VideoRecordingCoordinator.State.allCases {
            assertComplete(StatusEventCatalog.recording(state), "recording \(state)")
            rows += 1
        }
        for reason in RecordingStopReason.allCases {
            let event = StatusEventCatalog.recordingStop(reason)
            assertComplete(event, "stop \(reason)")
            XCTAssertEqual(event.cause, reason == .user ? .user : .system, "automatic stops are system-caused: \(reason)")
            rows += 1
        }
        for refusal in RecordingRefusal.allCases {
            assertComplete(StatusEventCatalog.recordingRefusal(refusal), "refusal \(refusal)")
            XCTAssertEqual(StatusEventCatalog.recordingNotice(refusal.notice).id, "X12", "refusal notice classified: \(refusal)")
            rows += 1
        }
        for failure in Self.allRecordingFailures {
            assertComplete(StatusEventCatalog.recordingFailure(failure), "failure \(failure)")
            rows += 1
        }
        for position in CameraPosition.allCases {
            for state in CameraFeedState.allStatusCases {
                assertComplete(StatusEventCatalog.camera(state, position: position), "camera \(state) \(position)")
                rows += 1
            }
        }
        for phase in OutputBlackout.Phase.allStatusCases {
            assertComplete(StatusEventCatalog.blackout(phase), "blackout \(phase)")
            rows += 1
        }
        assertComplete(StatusEventCatalog.osc(port: 9000), "osc on")
        assertComplete(StatusEventCatalog.osc(port: nil), "osc off")
        XCTAssertEqual(CameraFeedState.allStatusCases.count, 9)
        XCTAssertGreaterThan(rows, 60)
    }

    /// The safety classification documents ACC-011-R4: the source states announced even without FR-070.
    func testSafetyRelevantSourceStates() {
        let safety = AudioState.allCases.filter(StatusEventCatalog.isSafetyRelevant)
        XCTAssertEqual(Set(safety), [.noAudioReceived, .interrupted, .stopped, .endedBySystem])
    }
}
