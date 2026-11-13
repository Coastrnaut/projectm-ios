// ContractFakes.swift — conformance fakes for the three platform seams (QA-007-T02;
// specs/013-qa-007-audio-source-contract-suite/data-model.md, "ConformanceBackend").
//
// One scripted fake per seam: `StreamDriver` (System/App Capture), `MicrophoneBackend` and
// `InAppPlaybackBackend`. They share `SeamSessions`, which counts sessions and keeps the sink only
// while a session is live, as the platform backends must (contracts/audio-source.md guarantee 4).
// A fake does not protect itself against a second `start` without `stop`: the seam protocols do not
// promise that, and `AVMicrophoneBackend` and `SCKStreamDriver` do not do it (research D4). Every
// call is recorded in a shared `OrderLog` so the suite can check the order across sources.
//
// Everything runs on the main actor and nothing here waits on another thread.
import AudioCore
import Foundation
@testable import CaptureKit

/// Calls of every backend of one rig, in order: "start microphone", "stop inAppPlayback", ...
@MainActor
final class OrderLog {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }

    /// Index of the first entry equal to `entry` at or after `from`.
    func index(of entry: String, from: Int = 0) -> Int? {
        guard from < entries.count else { return nil }
        return entries[from...].firstIndex(of: entry)
    }
}

/// What the contract suite needs from every seam fake (the conformance harness's backend side).
@MainActor
protocol ConformanceBackend: AnyObject {
    var sessions: SeamSessions { get }
    /// The next `start` is denied or blocked the way this source's start is (contract P1).
    var denyNextStart: Bool { get set }
    /// Restores what `denyNextStart` changed, so a later start is allowed.
    func allowStart()
}

extension ConformanceBackend {
    var startCalls: Int { sessions.startCalls }
    /// Stops that ended a live session.
    var liveStops: Int { sessions.liveStops }
    /// Stops that found no live session (allowed where the seam declares `stop` idempotent).
    var idleStops: Int { sessions.idleStops }
    var pauseCalls: Int { sessions.pauseCalls }
    var resumeCalls: Int { sessions.resumeCalls }
    var liveSessions: Int { sessions.live }
    var maxLiveSessions: Int { sessions.maxLive }
    var hasSink: Bool { sessions.sink != nil }

    /// An event from the OS through the live session's callback; nothing without one.
    func send(_ event: SourceEvent) { sessions.onEvent?(event) }
    /// An event through the callback of the most recent session even after it ended: a late OS
    /// callback (delegate or notification) that a real backend could still deliver.
    func sendLate(_ event: SourceEvent) { sessions.lastOnEvent?(event) }
    /// Writes `seconds` of constant-amplitude 48 kHz stereo Float32 into the live session's sink.
    func deliver(amplitude: Float, seconds: Double) { sessions.deliver(amplitude: amplitude, seconds: seconds) }
}

/// Session bookkeeping shared by the three fakes.
@MainActor
final class SeamSessions {
    let label: String
    let log: OrderLog
    private(set) var startCalls = 0
    private(set) var liveStops = 0
    private(set) var idleStops = 0
    private(set) var pauseCalls = 0
    private(set) var resumeCalls = 0
    private(set) var live = 0
    private(set) var maxLive = 0
    private(set) var sink: PCMSink?
    private(set) var onEvent: (@Sendable (SourceEvent) -> Void)?
    private(set) var lastOnEvent: (@Sendable (SourceEvent) -> Void)?

    init(label: String, log: OrderLog) {
        self.label = label
        self.log = log
    }

    func began(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) {
        startCalls += 1
        live += 1
        maxLive = max(maxLive, live)
        self.sink = sink
        self.onEvent = onEvent
        lastOnEvent = onEvent
        log.append("start \(label)")
    }

    /// A start that was refused before any session began.
    func refused() {
        startCalls += 1
        log.append("refused \(label)")
    }

    func ended() {
        if live > 0 {
            live -= 1
            liveStops += 1
            log.append("stop \(label)")
        } else {
            idleStops += 1
            log.append("idle stop \(label)")
        }
        if live == 0 {
            sink = nil
            onEvent = nil
        }
    }

    func paused() {
        pauseCalls += 1
        log.append("pause \(label)")
    }

    func resumed() {
        resumeCalls += 1
        log.append("resume \(label)")
    }

    func deliver(amplitude: Float, seconds: Double) {
        guard let sink else { return }
        let frames = Int((48_000 * seconds).rounded())
        let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)
        let samples = [Float](repeating: amplitude, count: frames * 2)
        samples.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: frames, format: format) }
    }
}

// MARK: - System/App Capture seam

@MainActor
final class ConformanceStreamDriver: StreamDriver, ConformanceBackend {
    let sessions: SeamSessions
    var isSupported = true
    var isAllowed = true
    var contentIdentity: String?
    /// P1: the user declines screen recording at the picker (-3801, owner ruling 2026-11-08).
    var denyNextStart = false
    /// P1: the user cancels the system picker.
    var cancelNextPicker = false

    init(log: OrderLog) { sessions = SeamSessions(label: "systemAppCapture", log: log) }

    func allowStart() {
        denyNextStart = false
        cancelNextPicker = false
    }

    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) async throws {
        if denyNextStart {
            sessions.refused()
            throw SourceError(.screenRecordingNotAllowed, detail: "The user declined (SCStreamError -3801) [startCapture]")
        }
        if cancelNextPicker {
            sessions.refused()
            throw SourceError(.cancelled)
        }
        sessions.began(sink: sink, onEvent: onEvent)
    }

    /// `StreamDriver.stop` is documented as idempotent and must reach a pending picker.
    func stop() async { sessions.ended() }
}

// MARK: - Microphone seam

@MainActor
final class ConformanceMicrophoneBackend: MicrophoneBackend, ConformanceBackend {
    let sessions: SeamSessions
    var permission: MicrophonePermission = .granted
    var isInputAvailable = true
    /// When set, `requestPermission` waits like the system prompt until `answerPrompt`.
    var holdsPrompt = false
    var resumeError: SourceError?
    private var prompt: CheckedContinuation<Bool, Never>?

    init(log: OrderLog) { sessions = SeamSessions(label: "microphone", log: log) }

    /// P1: microphone permission denied.
    var denyNextStart: Bool {
        get { permission == .denied }
        set { permission = newValue ? .denied : .granted }
    }

    func allowStart() { permission = .granted }

    var isPromptPending: Bool { prompt != nil }

    func answerPrompt(grant: Bool) {
        permission = grant ? .granted : .denied
        let pending = prompt
        prompt = nil
        pending?.resume(returning: grant)
    }

    func requestPermission() async -> Bool {
        if holdsPrompt {
            return await withCheckedContinuation { prompt = $0 }
        }
        permission = .granted
        return true
    }

    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {
        sessions.began(sink: sink, onEvent: onEvent)
    }

    func stop() { sessions.ended() }
    func pause() { sessions.paused() }

    func resume() throws {
        if let resumeError { throw resumeError }
        sessions.resumed()
    }
}

// MARK: - In-App Playback seam

@MainActor
final class ConformancePlaybackBackend: InAppPlaybackBackend, ConformanceBackend {
    let sessions: SeamSessions
    /// P1: the track cannot be played (FR-006, AUD-001-R19).
    var denyNextStart = false
    var resumeError: SourceError?
    private(set) var startedTracks: [InAppPlaybackTrack] = []

    var loopsCurrentTrack = true
    var onTrackEnded: (@MainActor () -> Void)?
    var position: PlaybackPosition { PlaybackPosition(seconds: 0, durationSeconds: 60) }

    init(log: OrderLog) { sessions = SeamSessions(label: "inAppPlayback", log: log) }

    func allowStart() { denyNextStart = false }

    func start(track: InAppPlaybackTrack, sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {
        if denyNextStart {
            sessions.refused()
            throw SourceError(.inAppPlaybackFailed)
        }
        startedTracks.append(track)
        sessions.began(sink: sink, onEvent: onEvent)
    }

    func stop() { sessions.ended() }
    func pause() { sessions.paused() }

    func resume() throws {
        if let resumeError { throw resumeError }
        sessions.resumed()
    }

    func seek(to seconds: Double) {}
    func replaceTrack(_ track: InAppPlaybackTrack) throws {}
}
