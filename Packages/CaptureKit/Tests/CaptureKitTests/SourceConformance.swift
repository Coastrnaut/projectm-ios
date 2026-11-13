// SourceConformance.swift — source configurations, per-source parameters and the contract rig
// (QA-007-T03; specs/013-qa-007-audio-source-contract-suite/contracts/source-contract.md).
//
// Determinism (research D3): everything runs on the main actor; the classifier is driven by a
// `ManualClock` and `stepAnalysisForTesting()`; waits poll a condition and give up after 5 s; a
// "nothing changed" result is proven with a marker event (`formatChanged`), because the manager
// handles one source's events strictly in order.
import AudioCore
import Foundation
import XCTest
@testable import CaptureKit

/// The five source configurations every invariant runs against (spec Clarifications).
enum SourceConfiguration: String, CaseIterable, Sendable {
    case systemAppCapture
    case microphone
    case inAppReference
    case inAppFile
    case inAppTestSignal

    var mode: AudioSourceMode {
        switch self {
        case .systemAppCapture: return .systemAppCapture
        case .microphone: return .microphone
        case .inAppReference, .inAppFile, .inAppTestSignal: return .inAppPlayback
        }
    }

    /// In-App Playback's track: the bundled reference (FR-006), an imported file (AUD-001) or a
    /// generated test signal (AUD-016).
    var track: InAppPlaybackTrack {
        switch self {
        case .inAppFile: return .file(URL(fileURLWithPath: "/library/assets/contract.wav"))
        case .inAppTestSignal: return .tone(ReferenceToneCatalog.fixture(id: "sine-1k")!)
        default: return .reference
        }
    }

    var parameters: SourceParameters { SourceParameters(mode) }

    /// Prefix for failure messages.
    func tag(_ invariant: String) -> String { "[\(rawValue)] \(invariant)" }
}

/// The documented per-source differences (contract P1 to P7). Never a skip: each test asserts the
/// outcome its parameter documents.
struct SourceParameters {
    /// P1: the reason a denied or blocked start ends with. System/App Capture: the user declined
    /// screen recording (owner ruling 2026-11-08, -3801). Microphone: permission denied (FR-005,
    /// FR-015). In-App Playback asks for no permission (FR-069); its blocked start is a track that
    /// cannot be played (FR-006, AUD-001-R19).
    let denialReason: StopReason
    /// P2: which row set of `InterruptionPolicy` governs it (System/App Capture: rule 1, FR-051).
    let policySource: InterruptionPolicy.Source
    /// P3: paused by background and lock (FR-050, FR-054). System/App Capture continues (data-model
    /// lifecycle matrix; ADR-0001 ruling 17, RI-003).
    let suspendsForLifecycle: Bool
    /// P4: the source's terminal OS event and where it ends (US6-AS3, data-model lifecycle matrix).
    let terminalEvent: SourceEvent
    let terminalState: AudioState
    let terminalReason: StopReason
    /// P5: resumes on a return to the foreground while an interruption is still open. Microphone
    /// keeps feature 001's FR-050 behavior (AUD-014-R9); In-App Playback waits for iOS (AUD-014-R5,
    /// R6); System/App Capture is not interrupted (P2).
    let resumesOnReturnDuringOpenInterruption: Bool
    /// P6: a resume re-checks permission (FR-053). Only Microphone has a revocable permission.
    let resumeRechecksPermission: Bool
    /// P7: every `stop()` is forwarded to the backend, also with no session, because a stop must
    /// reach a start still waiting on the system picker (`StreamDriver.stop` is idempotent; ADR-0001
    /// ruling 7; `ScreenCaptureSourceTests.testStopIsIdempotent`). The other adapters stop their
    /// backend only while started.
    let forwardsIdleStop: Bool

    init(_ mode: AudioSourceMode) {
        policySource = InterruptionPolicy.Source(mode)
        switch mode {
        case .systemAppCapture:
            denialReason = .screenRecordingNotAllowed
            suspendsForLifecycle = false
            terminalEvent = .endedBySystem("The stream was stopped (SCStreamError -3817)")
            terminalState = .endedBySystem
            terminalReason = .endedBySystem
            resumesOnReturnDuringOpenInterruption = false
            resumeRechecksPermission = false
            forwardsIdleStop = true
        case .microphone:
            denialReason = .permissionDenied
            suspendsForLifecycle = true
            terminalEvent = .failed(.microphoneUnavailable)
            terminalState = .stopped
            terminalReason = .microphoneUnavailable
            resumesOnReturnDuringOpenInterruption = true
            resumeRechecksPermission = true
            forwardsIdleStop = false
        case .inAppPlayback:
            denialReason = .inAppPlaybackFailed
            suspendsForLifecycle = true
            terminalEvent = .failed(.inAppPlaybackFailed)
            terminalState = .stopped
            terminalReason = .inAppPlaybackFailed
            resumesOnReturnDuringOpenInterruption = false
            resumeRechecksPermission = false
            forwardsIdleStop = false
        }
    }

    /// What the AUD-014 policy decides for a session that was playing, nobody holds paused, the
    /// user did not touch, the app is in the foreground and the source is usable (P2).
    func policyDecision(_ signal: InterruptionPolicy.SystemSignal) -> InterruptionPolicy.Decision {
        InterruptionPolicy.decide(InterruptionPolicy.Input(
            source: policySource, before: .playing, pausedBy: .nobody, signal: signal,
            isPresentable: true, userChangedTransport: false, sourceIsUsable: true))
    }

    var isInterruptionGoverned: Bool { policyDecision(.pending) != .notApplicable }
}

/// The allowed transitions of spec 001's data model (contract table; QA-007-R8).
enum ContractGraph {
    static let allowed: [AudioState: Set<AudioState>] = [
        .notStarted: [.waiting, .notStarted],
        .waiting: [.noAudioReceived, .silent, .active, .paused, .interrupted, .stopped, .endedBySystem],
        .noAudioReceived: [.silent, .active, .paused, .interrupted, .stopped, .endedBySystem],
        .silent: [.active, .noAudioReceived, .paused, .interrupted, .stopped, .endedBySystem],
        .active: [.silent, .noAudioReceived, .paused, .interrupted, .stopped, .endedBySystem],
        .paused: [.waiting, .stopped, .endedBySystem],
        .interrupted: [.waiting, .paused, .stopped, .endedBySystem],
        .stopped: [],
        .endedBySystem: [],
    ]

    static func isAllowed(_ from: AudioState, _ to: AudioState) -> Bool {
        allowed[from]?.contains(to) ?? false
    }
}

/// The real CaptureManager over the three real adapters, each on its conformance fake.
@MainActor
final class ContractRig {
    let clock = ManualClock()
    let log = OrderLog()
    let driver: ConformanceStreamDriver
    let micBackend: ConformanceMicrophoneBackend
    let playbackBackend: ConformancePlaybackBackend
    let capture: ScreenCaptureSource
    let mic: MicrophoneSource
    let inApp: InAppPlaybackSource
    let manager: CaptureManager
    /// Transitions checked so far in the current attempt.
    private var checkedTransitions = 0

    init(track: InAppPlaybackTrack = .reference) {
        driver = ConformanceStreamDriver(log: log)
        micBackend = ConformanceMicrophoneBackend(log: log)
        playbackBackend = ConformancePlaybackBackend(log: log)
        capture = ScreenCaptureSource(driver: driver)
        mic = MicrophoneSource(backend: micBackend)
        inApp = InAppPlaybackSource(backend: playbackBackend)
        inApp.track = track
        let clock = self.clock
        manager = CaptureManager(sources: [capture, mic, inApp], runsAnalysisTimer: false, clock: { clock.now })
    }

    convenience init(_ configuration: SourceConfiguration) {
        self.init(track: configuration.track)
    }

    func backend(_ mode: AudioSourceMode) -> any ConformanceBackend {
        switch mode {
        case .systemAppCapture: return driver
        case .microphone: return micBackend
        case .inAppPlayback: return playbackBackend
        }
    }

    func adapter(_ mode: AudioSourceMode) -> any AudioSource {
        switch mode {
        case .systemAppCapture: return capture
        case .microphone: return mic
        case .inAppPlayback: return inApp
        }
    }

    var totalLiveSessions: Int {
        AudioSourceMode.allCases.map { backend($0).liveSessions }.reduce(0, +)
    }

    // MARK: Commands (R8 is checked before every new attempt)

    func select(_ mode: AudioSourceMode, file: StaticString = #filePath, line: UInt = #line) async {
        assertTransitionsAllowed("before select \(mode)", file: file, line: line)
        await manager.select(mode)
        checkedTransitions = 0
    }

    func restart(file: StaticString = #filePath, line: UInt = #line) async {
        assertTransitionsAllowed("before restart", file: file, line: line)
        await manager.restart()
        checkedTransitions = 0
    }

    /// Delivers audio through `mode`'s backend in 10 ms chunks, advancing the clock and stepping the
    /// analysis after each chunk. `whileRunning` is checked after every step.
    func play(_ mode: AudioSourceMode, amplitude: Float, seconds: Double,
              whileRunning: ((AudioState) -> Void)? = nil) {
        let chunks = Int((seconds / 0.01).rounded())
        for _ in 0..<chunks {
            backend(mode).deliver(amplitude: amplitude, seconds: 0.01)
            clock.advance(0.01)
            manager.stepAnalysisForTesting()
            whileRunning?(manager.state)
        }
    }

    /// Non-silent (−6 dBFS) audio long enough to verify Active audio (≥ 250 ms; FR-011).
    func playLoud(_ mode: AudioSourceMode, seconds: Double = 0.5) {
        play(mode, amplitude: 0.5, seconds: seconds)
    }

    /// Advances time with no audio, stepping the analysis every 100 ms.
    func idle(seconds: Double) {
        let steps = Int((seconds / 0.1).rounded())
        for _ in 0..<steps {
            clock.advance(0.1)
            manager.stepAnalysisForTesting()
        }
    }

    // MARK: Waiting

    /// Sends a marker event through `mode`'s live session and waits until the manager handled it.
    /// Events of one session are handled in order, so every earlier event is then fully handled.
    func settle(_ mode: AudioSourceMode, file: StaticString = #filePath, line: UInt = #line) async {
        let before = manager.lifecycleLog.filter { $0.event == "formatChange" }.count
        backend(mode).send(.formatChanged)
        await waitFor("marker of \(mode) handled", file: file, line: line) {
            self.manager.lifecycleLog.filter { $0.event == "formatChange" }.count > before
        }
    }

    // MARK: R8

    /// Every transition recorded in the current attempt is an edge of the contract graph.
    func assertTransitionsAllowed(_ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let transitions = manager.transitions
        var previous: AudioState = .notStarted
        for (index, transition) in transitions.enumerated() {
            if index >= checkedTransitions {
                XCTAssertTrue(ContractGraph.isAllowed(previous, transition.state),
                              "R8 \(context): transition \(previous) → \(transition.state) is not in spec 001's graph (all: \(transitions.map(\.state)))",
                              file: file, line: line)
            }
            previous = transition.state
        }
        checkedTransitions = transitions.count
    }
}

/// Waits on the main actor until `condition` holds, yielding to other main-actor work; fails after
/// 5 s. A condition, never a fixed delay, decides when the test continues.
@MainActor
@discardableResult
func waitFor(_ what: String, file: StaticString = #filePath, line: UInt = #line,
             _ condition: () -> Bool) async -> Bool {
    for _ in 0..<1_000 {
        if condition() { return true }
        await Task.yield()
    }
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    if condition() { return true }
    XCTFail("timed out waiting: \(what)", file: file, line: line)
    return false
}

/// Whether `stream` finishes (its iteration ends), waiting at most 5 s.
@MainActor
func streamFinishes(_ stream: AsyncStream<SourceEvent>, collecting events: EventBox? = nil) async -> Bool {
    let box = events ?? EventBox()
    let reader = Task { @MainActor in
        for await event in stream { box.events.append(event) }
        box.finished = true
    }
    var finished = false
    for _ in 0..<1_000 where !box.finished { await Task.yield() }
    if box.finished {
        finished = true
    } else {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !box.finished { try? await Task.sleep(nanoseconds: 1_000_000) }
        finished = box.finished
    }
    reader.cancel()
    return finished
}

@MainActor
final class EventBox {
    var events: [SourceEvent] = []
    var finished = false
}
