// VideoRecordingCoordinator.swift — Record (REC-003; spec specs/058-rec-003-video-recording,
// contracts/video-recording.md, research REC-003-D6 to D9, ADR-0027).
//
// * Only the user's Record starts a recording (REC-003-R2). The refusal rules come first
//   (`RecordingGate`): busy, no visual, projectM (not recordable in this row), blacked out, paused.
// * The shown visual's host gets a `VideoRecordingTap`; after each frame it encodes the frame as shown
//   into the recorder's pixel buffer (compositor `encodeOutput`, or a drawable blit for the spectra).
//   The recorder never makes the frame loop wait (bounded queue, drops counted).
// * While recording, a 0.25 s check stops the recording when the user paused, the output was blacked
//   out, the visual changed or stopped drawing; the app going to the background stops it inside a
//   background-task grant; the tap reports size changes, the 10-minute limit and writer failures.
//   Every stop finishes the file off the main thread and keeps what was recorded (REC-003-R11).
// * The finished file is offered (REC-012-R1: "Recording ready" with Save…, Share… and Discard) until
//   Save… moves it or Discard deletes it; while it is offered, Record refuses (REC-012-R10). Save…
//   opens the system file mover (`fileMover`: the user picks the folder; the temporary file is moved,
//   never copied), never the photo library; a cancelled move keeps it offered (REC-012 supersedes
//   REC-003-R13's delete on cancel). Leftovers in `<tmp>/Recordings` are deleted at launch
//   (REC-003-R13), so nothing outlives the session. Nothing else is stored.
// * REC-015 (specs/063-rec-015-recording-disk-guard): Record reads the free storage once (after the
//   refusals above) and refuses below the reserve plus one minute; while recording, a 5 s loop reads
//   the free storage and the file's size off the main actor and stops with `.lowStorage` (the normal
//   finish: the file is finished and offered). An out-of-space writer failure ends as `storageFull`
//   (the package deletes the partial file). The value is used only for that, never stored or sent.
//   DEBUG `-uitestStorage low|dropAfter:<n>` fakes the readings (1 s interval) and an offered file is
//   read back into `probe`.
// * REC-004 (specs/134-rec-004-recording-audio, contract C4, ADR-0053): at Record the audio decision is
//   made from the source mode, the microphone permission and "Include microphone audio"
//   (`RecordingAudioPolicy`); only "include" gives the file an AAC track and arms the normalized ring's
//   recording tap. After each frame the tap is drained into the recorder (`RecordingAudioFeed`). The
//   0.25 s check ends the audio for good when the source mode changes, the tap was disarmed by a new
//   capture session, or the microphone setting is turned off; no silence is added. Other apps' audio
//   (System/App Capture) never reaches a file.
// * REC-007 (specs/175-rec-007-countdown, contract C1): with a countdown set (Off, 3, 5, 10 s), Record applies
//   the refusals and then counts down (`.countingDown(remaining)`) on an injected clock; no writer, file, audio
//   tap or storage reading exists until it completes, and the completion runs the start path exactly once
//   (generation token). Record, Cancel or Escape cancels; a Record tap in the last 0.25 s or the first 0.5 s
//   of the recording it started is ignored. The 0.25 s check, the background observer and leaving the
//   visualizer cancel it.
// * REC-008 (specs/180-rec-008-timed-stop, contract C2, C3): with a length set (Off, 10 s, 30 s, 1 min, 5 min) the
//   recording's `maxDurationSeconds` is that length, fixed at start; the recorder writes exactly the frames below
//   it, the tap calls `beginFinish()` on the frame that crossed it (never waits) and reports the stop, which is
//   `timedStop` with "Recording stopped after 10 seconds.". The indicator reads "0:07 / 0:10".
// * REC-009 (specs/190-rec-009-status-overlay, contract C1, C2): while recording, `statusSummary` (dropped slots from
//   the recorder's statistics, the free storage from the Record-time and 5 s REC-015 readings, the minutes until the
//   guard stops) is refreshed by the 0.25 s check and after each storage reading; `RecordingWarningThrottle` sets
//   `statusWarning` for rising warnings (at most once per kind per 30 s of recording), which the view posts as X9f
//   or X9g. The readings stay in memory (REC-009-R7). The overlay is app UI and never reaches a file (REC-009-R6,
//   research REC-009-D1): every source feeds the recorder from its own Metal output inside its frame's command
//   buffer — the compositor's `encodeOutput` (the shown composite after the FX-019 flash guard and FX-003 grade) or
//   the native spectra's drawable blit — which SwiftUI layers are never drawn into, also when the visual's view is
//   on an external display (the same host feeds the recording). There is no option to include the overlay.
// * DEBUG: `-uitestRecordingDirectory <name>` moves the file into `<tmp>/<name>/` instead of showing
//   the mover, and `probe` reports what AVFoundation reads back ("video hvc1 1178x2556 frames=58
//   duration=1.93 audio=0").
import AudioCore
import Compositor
import Foundation
import FrameRecording
import Metal
import Observation
import UIKit

/// A visual that can feed a video recording (REC-003-R1).
@MainActor
protocol VideoRecordingSource: AnyObject {
    var recordingDevice: MTLDevice { get }
    /// The drawable's size in pixels.
    var recordingDrawableSize: CGSize { get }
    /// False while the visual's frame loop is stopped (paused, background, presentation lost).
    var isPresentingFrames: Bool { get }
    var videoRecording: VideoRecordingTap? { get set }
}

/// What a host calls once per presented frame while a recording is attached.
@MainActor
final class VideoRecordingTap {
    let recorder: MetalFrameRecorder
    /// Called once, on the main actor, when the recording must stop (size, limit, failure).
    var onStop: ((RecordingStopReason) -> Void)?
    /// REC-004: drains the recording tap into the recorder after each frame (nil without permitted audio).
    var audioFeed: RecordingAudioFeed?
    private var stopReported = false

    init(recorder: MetalFrameRecorder) {
        self.recorder = recorder
    }

    /// Offers the frame `commandBuffer` presents (before it is committed). `encode` draws the shown
    /// frame into the recorder's texture. Never waits.
    func record(commandBuffer: MTLCommandBuffer, presentationNanoseconds: UInt64, drawable: MTLTexture,
                encode: (MTLTexture) -> Bool) {
        guard !stopReported else { return }
        let outcome = recorder.recordFrame(presentationNanoseconds: presentationNanoseconds, drawableWidth: drawable.width,
                                           drawableHeight: drawable.height, commandBuffer: commandBuffer, encode: encode)
        audioFeed?.pump()   // after the frame: the first frame sets the audio's origin
        if outcome == .durationReached { recorder.beginFinish() }   // REC-008-R3: after the last audio; never waits
        switch outcome {
        case .sizeChanged: report(.sizeChanged)
        case .durationReached: report(.durationReached)
        case .failed: report(.writerFailed)
        case .submitted, .skippedRate, .dropped, .finished: break
        }
    }

    private func report(_ reason: RecordingStopReason) {
        stopReported = true
        let onStop = onStop
        Task { @MainActor in onStop?(reason) }   // never inside the host's frame
    }
}

/// REC-004: moves the recording tap's audio into the recorder. Main actor (the frame loop's thread);
/// one preallocated buffer, never waits.
@MainActor
final class RecordingAudioFeed {
    static let maxFrames = 22_050
    private let reader: any RecordingTapReading
    private let recorder: MetalFrameRecorder
    private let buffer: UnsafeMutablePointer<Float>

    init(reader: any RecordingTapReading, recorder: MetalFrameRecorder) {
        self.reader = reader
        self.recorder = recorder
        buffer = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxFrames * 2)
        buffer.initialize(repeating: 0, count: Self.maxFrames * 2)
    }

    isolated deinit {
        buffer.deinitialize(count: Self.maxFrames * 2)
        buffer.deallocate()
    }

    /// Drains what the tap holds (at most 0.5 s) and hands it to the recorder with its host time.
    func pump() {
        let chunk: RecordingTapChunk = reader.read(into: buffer, maxFrames: Self.maxFrames)
        guard chunk.frames > 0 else { return }
        recorder.appendAudio(buffer, frames: chunk.frames, firstSampleNanoseconds: chunk.firstSampleNanoseconds)
    }
}

@MainActor
@Observable
final class VideoRecordingCoordinator {
    /// What the coordinator needs to know about the visualizer at a given moment.
    struct Context {
        /// The shown visual's recording source (nil for projectM and when no visual is shown).
        var source: (any VideoRecordingSource)?
        /// A visual is shown (projectM included).
        var visualShown: Bool
        var outputLive: Bool
        var paused: Bool
        /// REC-004: the running source's mode (nil when none), the microphone permission and the setting.
        var audioMode: AudioSourceMode? = nil
        var microphoneGranted = false
        var includeMicrophone = false
        /// REC-004: the normalized ring's recording tap and how to arm or disarm it (nil in tests without audio).
        var audioTap: (any RecordingTapReading)? = nil
        var setAudioTapArmed: ((Bool) -> Void)? = nil
        /// REC-005: the selected quality profile and what the device can encode (nil: VideoToolbox at 60 fps).
        var qualityProfile: RecordingQualityProfile = .defaultProfile
        var qualityCapabilities: (any RecordingEncoderCapabilities)? = nil
        /// REC-006: the frame-rate choice (Profile default keeps the profile's rate).
        var frameRateChoice: RecordingFrameRateChoice = .defaultChoice
        /// REC-007: the countdown before a recording starts (Off: at once).
        var countdown: RecordingCountdownLength = .defaultLength
        /// REC-008: the length after which the recording stops by itself (Off: the 10-minute limit only).
        var timedStop: RecordingTimedStopLength = .defaultLength
    }

    enum State: Equatable, CaseIterable {   // CaseIterable: ACC-011's completeness test
        case idle
        /// REC-007: the whole seconds left before the recording starts (nothing is written yet).
        case countingDown(Int)
        case recording
        case finishing

        /// `countingDown(1)` stands for every remaining count.
        static var allCases: [State] { [.idle, .countingDown(1), .recording, .finishing] }

        var isCountingDown: Bool {
            if case .countingDown = self { return true }
            return false
        }

        /// REC-007: the remaining seconds while counting down.
        var countdownRemaining: Int? {
            if case .countingDown(let remaining) = self { return remaining }
            return nil
        }

        /// The recording indicator shows (a file exists or is being finished).
        var hasRecording: Bool { self == .recording || self == .finishing }
    }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }   // OUT-002-R4: the external display's hold
    }
    /// OUT-002: told of every state change (AppCoordinator holds the visual's placement while recording).
    @ObservationIgnored var onStateChange: ((State) -> Void)?
    /// Seconds of video recorded so far (media time, shown by the indicator).
    private(set) var elapsedSeconds: Double = 0
    /// The latest user-visible notice, nil when none.
    private(set) var notice: String?
    /// The system file mover is shown with `fileToMove`.
    var showMover = false
    private(set) var fileToMove: URL?
    /// REC-012: the finished recording, offered with Save…, Share… and Discard (a temporary file).
    private(set) var offered: URL?
    /// The reason of the last stop (tests, diagnostics).
    private(set) var lastStopReason: RecordingStopReason?
    /// DEBUG probe: what the last recording reads back as, or the last refusal or failure.
    private(set) var probe = "none"
    /// REC-004: the audio decision of the current (or last) recording; nil before the first.
    private(set) var recordingAudio: RecordingAudioDecision?
    /// REC-004: the current recording's audio ended early (a switch, a new session, the setting off).
    private(set) var audioEnded = false
    /// REC-005: the profile the current (or last) recording uses (after a fallback, the one it fell back to).
    private(set) var recordingProfile: RecordingQualityProfile?
    /// REC-006-R4: the last finished recording's facts (frame rate, frames, dropped frames); nil before the first.
    private(set) var lastRecording: RecordedVideo?
    /// REC-007-R6: why the last countdown was cancelled (nil while counting and after a completion or a refusal).
    private(set) var lastCountdownCancel: RecordingCountdownCancel?
    /// REC-008-R10: the current (or last) recording's length, fixed at its start; nil with Off.
    private(set) var recordingLength: RecordingTimedStopLength?
    /// REC-009: what the status overlay shows (nil unless recording).
    private(set) var statusSummary: RecordingStatusSummary?
    /// REC-009-R4: the latest warning to announce; each new one has a new sequence number.
    private(set) var statusWarning: RecordingStatusWarning?
    @ObservationIgnored private var storageReading = StorageReading()
    @ObservationIgnored private var warningThrottle = RecordingWarningThrottle()
    @ObservationIgnored private var warningSequence = 0
    /// REC-007: writers this coordinator has created (tests: a cancelled countdown creates none).
    @ObservationIgnored private(set) var writerCreations = 0
    @ObservationIgnored private let countdownClock: any RecordingCountdownClock
    @ObservationIgnored private var countdownGeneration = 0
    @ObservationIgnored private var countdownDeadline: Double = 0
    @ObservationIgnored private var countdownTimer: (any RecordingCountdownTimer)?
    @ObservationIgnored private weak var countdownSource: (any VideoRecordingSource)?
    @ObservationIgnored private var countdownStartedRecordingAt: Double?
    @ObservationIgnored private var recordingAudioMode: AudioSourceMode?
    @ObservationIgnored private var disarmAudioTap: (() -> Void)?

    @ObservationIgnored private let context: @MainActor () -> Context
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let debugDirectory: URL?
    @ObservationIgnored private let checkInterval: Duration?
    @ObservationIgnored private var recorder: MetalFrameRecorder?
    @ObservationIgnored private weak var source: (any VideoRecordingSource)?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let storageProbe: any StorageProbe
    @ObservationIgnored private let storageCheckInterval: Duration?
    @ObservationIgnored private let writerFault: RecordingWriterFault?
    @ObservationIgnored private var storagePolicy: RecordingStoragePolicy?
    @ObservationIgnored private var storageTicker: Task<Void, Never>?

    /// `checkInterval` nil: no periodic check (tests call `checkContext()`).
    /// `storageCheckInterval` nil: no storage loop (tests call `checkStorage()`). `writerFault`: tests only.
    init(directory: URL = VideoRecordingCoordinator.defaultDirectory,
         debugDirectory: URL? = VideoRecordingCoordinator.debugDirectoryFromArguments(),
         checkInterval: Duration? = .milliseconds(250),
         storageProbe: (any StorageProbe)? = nil,
         storageCheckInterval: Duration? = .seconds(RecordingStoragePolicy.checkIntervalSeconds),
         writerFault: RecordingWriterFault? = nil,
         countdownClock: (any RecordingCountdownClock)? = nil,
         context: @escaping @MainActor () -> Context) {
        self.directory = directory
        self.debugDirectory = debugDirectory
        self.checkInterval = checkInterval
        let debugStorage = Self.debugStorageFromArguments()
        self.storageProbe = storageProbe ?? debugStorage?.probe ?? VolumeStorageProbe()
        self.storageCheckInterval = storageProbe == nil ? (debugStorage?.interval ?? storageCheckInterval) : storageCheckInterval
        self.writerFault = writerFault
        self.countdownClock = countdownClock ?? SystemRecordingCountdownClock()
        self.context = context
        Self.removeLeftovers(in: directory)   // REC-003-R13: a crash may have left a temporary file
        observeBackground()
    }

    isolated deinit {
        ticker?.cancel()
        storageTicker?.cancel()
        countdownTimer?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// FILE-010-R5: what cache cleanup must keep — the whole recording folders while a recording is made
    /// or finished, the offered recording and the one handed to the Save mover.
    var filesInUse: [URL] {
        var urls: [URL] = [offered, fileToMove].compactMap { (url: URL?) -> URL? in url }
        if state.hasRecording {   // REC-007: a countdown has no file yet
            urls.append(directory)
            if let debugDirectory { urls.append(debugDirectory) }
        }
        return urls
    }

    /// `<tmp>/Recordings`: the only place recordings exist before the mover takes them.
    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    /// DEBUG `-uitestRecordingDirectory <name>`: a folder in the app's temporary directory.
    static func debugDirectoryFromArguments() -> URL? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-uitestRecordingDirectory"), i + 1 < arguments.count {
            let name = arguments[i + 1].replacingOccurrences(of: "/", with: "_")
            return FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        }
        #endif
        return nil
    }

    /// Deletes every file in `directory` (a directory listing only: no file dates are read).
    static func removeLeftovers(in directory: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    }

    /// "Visualizer Recording 2026-11-13 at 14.05.32.mp4" (the user may rename it in Files).
    static func fileName(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Visualizer Recording \(formatter.string(from: date)).mp4"
    }

    /// The indicator's text: "0:05", "1:02:03" never (10-minute limit).
    nonisolated static func elapsedText(_ seconds: Double) -> String {
        let whole = max(Int(seconds), 0)
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    var elapsedText: String { Self.elapsedText(elapsedSeconds) }

    /// REC-008-R8: the indicator's text, "0:07 / 0:10" with a length, else "0:07".
    var indicatorText: String {
        guard let total = recordingLength?.indicatorText else { return elapsedText }
        return elapsedText + " / " + total
    }

    /// REC-008-R8: what VoiceOver reads for the indicator's time, "0:07 of 0:10" with a length.
    var indicatorAccessibilityText: String {
        guard let total = recordingLength?.indicatorText else { return elapsedText }
        return elapsedText + " of " + total
    }

    // MARK: - Audio (REC-004)

    /// The recording audio source of an app source mode.
    nonisolated static func audioKind(_ mode: AudioSourceMode?) -> RecordingAudioSourceKind? {
        switch mode {
        case .inAppPlayback: .inAppPlayback
        case .microphone: .microphone
        case .systemAppCapture: .systemCapture
        case nil: nil
        }
    }

    /// The decision a recording started now would get (REC-004-R4).
    static func audioDecision(for c: Context) -> RecordingAudioDecision {
        RecordingAudioPolicy.decide(source: audioKind(c.audioMode), includeMicrophone: c.includeMicrophone,
                                    microphoneGranted: c.microphoneGranted)
    }

    /// What the next (idle) or current (recording) recording's audio is (REC-004-R9).
    var audioStatusText: String {
        if state == .recording, let recordingAudio {
            return audioEnded ? RecordingAudioDecision.endedText : recordingAudio.statusText
        }
        return Self.audioDecision(for: context()).statusText
    }

    /// True when the shown visual can be recorded (the control's state).
    var isRecordable: Bool { context().source != nil }

    // MARK: - User actions

    /// Record / Stop recording.
    func toggle() {
        switch state {
        case .recording:
            if !countdownStartGuardActive { stop(.user) }   // REC-007-R4: a late tap never stops the new recording
        case .finishing: refuse(.busy)
        case .countingDown:
            if countdownDeadline - countdownClock.now > Self.countdownFinalGuard { cancelCountdown(.user) }   // REC-007-R4
        case .idle: requestStart()
        }
    }

    func clearNotice() { notice = nil }

    /// The notice while a recording is offered and the user taps Record (REC-012-R10).
    static let resultOfferedNotice = "Save, share or discard the last recording first."

    /// Save… on the offered recording: the file mover gets it (REC-012-R1).
    func requestSave() {
        guard let offered else { return }
        fileToMove = offered
        showMover = true
    }

    /// Discard: the offered recording's temporary file is deleted (REC-012-R9).
    func discardOffered() {
        if let offered { try? FileManager.default.removeItem(at: offered) }
        offered = nil
        fileToMove = nil
        showMover = false
    }

    /// The mover finished: the file was moved (success: nothing is offered any more); a cancel or a
    /// failure keeps the recording offered (REC-012-R8).
    func moverFinished(_ result: Result<URL, any Error>) {
        if case .success = result {
            notice = "Recording saved."
            offered = nil
        } else if let error = result.failureValue, (error as? CocoaError)?.code != .userCancelled {
            notice = RecordingFailure.writerFailed("").notice
        }
        fileToMove = nil
        showMover = false
    }

    /// The mover was cancelled or dismissed without a result: the recording stays offered.
    func moverCancelled() {
        fileToMove = nil
        showMover = false
    }

    // MARK: - Start and stop

    /// The start refusals (REC-003, REC-012-R10); true when Record was refused (the notice is set).
    private func refusedStart(_ c: Context, busy: Bool) -> Bool {
        if let refusal = RecordingGate.refusal(visualAvailable: c.visualShown, recordable: c.source != nil, outputLive: c.outputLive,
                                               paused: c.paused, busy: busy || fileToMove != nil) {
            refuse(refusal)
            return true
        }
        if offered != nil {   // REC-012-R10: never delete an offered recording without the user's choice
            notice = Self.resultOfferedNotice
            probe = "refused: resultOffered"
            return true
        }
        return false
    }

    /// `afterCountdown`: the completion of a countdown (its own state is not "busy", REC-007-R3).
    private func start(afterCountdown: Bool = false) {
        let c = context()
        if refusedStart(c, busy: afterCountdown ? false : state != .idle) { return }
        guard let source = c.source else { return }
        let size = source.recordingDrawableSize
        let audio = Self.audioDecision(for: c)   // REC-004-R4: fixed for this recording
        let tapArmer = c.setAudioTapArmed
        let url = directory.appendingPathComponent(Self.fileName(date: Date()))
        // REC-005-R6, REC-006-R7: the selected profile and rate, re-checked with this drawable; a fallback is announced (X9c).
        let capabilities: any RecordingEncoderCapabilities = c.qualityCapabilities ?? RecordingQualitySetting.encoder
        let resolution = RecordingFrameRateCatalog.resolve(profile: c.qualityProfile, choice: c.frameRateChoice,
                                                           drawableWidth: Int(size.width), drawableHeight: Int(size.height),
                                                           capabilities: capabilities)
        guard let plan = resolution.plan else {
            fail(.encoderUnavailable)
            return
        }
        var settings: RecordingSettings = plan.settings
        let length: RecordingTimedStopLength? = c.timedStop.seconds > 0 ? c.timedStop : nil   // REC-008-R10: fixed now
        if let length { settings.maxDurationSeconds = min(length.seconds, settings.maxDurationSeconds) }   // media time
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // REC-015-R1, R3: one free-storage reading before anything is written.
            var policy: RecordingStoragePolicy?
            var startAvailable: Int64?
            if let geometry = RecordingGeometry(drawableWidth: Int(size.width), drawableHeight: Int(size.height),
                                                maxLongSide: settings.maxLongSide) {
                let rules = RecordingStoragePolicy(estimate: RecordingStorageEstimate(geometry: geometry, settings: settings))
                startAvailable = storageProbe.availableBytes(at: directory)
                guard rules.allowsStart(availableBytes: startAvailable) else {
                    refuse(.lowStorage)
                    return
                }
                policy = rules
            }
            writerCreations += 1   // REC-007: counted before the writer exists
            let recorder = try MetalFrameRecorder(device: source.recordingDevice, url: url, drawableWidth: Int(size.width),
                                                  drawableHeight: Int(size.height), settings: settings, fault: writerFault,
                                                  audio: audio.includesAudio && c.audioTap != nil)
            storagePolicy = policy
            storageReading = StorageReading(availableBytes: startAvailable, fileBytes: nil)   // REC-009-R3
            let tap = VideoRecordingTap(recorder: recorder)
            if recorder.hasAudioTrack, let reader = c.audioTap {
                tapArmer?(true)   // empty, then only this recording's permitted source
                tap.audioFeed = RecordingAudioFeed(reader: reader, recorder: recorder)
                disarmAudioTap = { () -> Void in tapArmer?(false) }
            }
            tap.onStop = { [weak self] (reason: RecordingStopReason) in self?.stop(reason) }
            source.videoRecording = tap
            self.recorder = recorder
            self.source = source
        } catch let failure as RecordingFailure {
            fail(failure)
            return
        } catch {
            fail(.writerFailed(error.localizedDescription))
            return
        }
        let hasTrack: Bool = recorder?.hasAudioTrack ?? false
        // Without a tap to read (unit tests) an "include" decision still records no audio: say so.
        recordingAudio = hasTrack || !audio.includesAudio ? audio : RecordingAudioDecision.exclude(.noSource)
        recordingAudioMode = c.audioMode
        audioEnded = false
        state = .recording
        elapsedSeconds = 0
        notice = resolution.notice   // REC-005-R6, REC-006-R7: X9c, nil without a fallback
        recordingProfile = plan.profile
        recordingLength = length
        lastStopReason = nil
        probe = "recording"
        warningThrottle = RecordingWarningThrottle()   // REC-009-R4: per recording
        refreshStatus()
        startTicker()
        startStorageTicker()
    }

    // MARK: - Countdown (REC-007, contract C1, research REC-007-D3 to D6)

    /// A Record tap this close to the countdown's end is ignored (REC-007-R4).
    static let countdownFinalGuard: Double = 0.25
    /// A Record tap this soon after the countdown started the recording is ignored (REC-007-R4).
    static let countdownStartGuard: Double = 0.5

    private var countdownStartGuardActive: Bool {
        guard let startedAt = countdownStartedRecordingAt else { return false }
        return countdownClock.now - startedAt < Self.countdownStartGuard
    }

    /// Record from idle: at once (Off), or the refusals and then a countdown.
    private func requestStart() {
        countdownStartedRecordingAt = nil
        let c = context()
        let seconds: Int = c.countdown.seconds
        guard seconds > 0 else {
            start()
            return
        }
        if refusedStart(c, busy: false) { return }
        guard let source = c.source else { return }
        countdownGeneration += 1
        let generation: Int = countdownGeneration
        let begin: Double = countdownClock.now
        countdownDeadline = begin + Double(seconds)
        countdownSource = source
        lastCountdownCancel = nil
        state = .countingDown(seconds)
        scheduleCountdownTick(step: 1, begin: begin, seconds: seconds, generation: generation)
        startTicker()   // the 0.25 s check cancels on the same changes that stop a recording
    }

    /// Step k runs at `begin + k` (no drift); a stale generation does nothing.
    private func scheduleCountdownTick(step: Int, begin: Double, seconds: Int, generation: Int) {
        countdownTimer = countdownClock.schedule(at: begin + Double(step)) { [weak self] () -> Void in
            self?.countdownTick(step: step, begin: begin, seconds: seconds, generation: generation)
        }
    }

    private func countdownTick(step: Int, begin: Double, seconds: Int, generation: Int) {
        guard generation == countdownGeneration, state.isCountingDown else { return }
        if step >= seconds {
            completeCountdown()
            return
        }
        state = .countingDown(seconds - step)
        scheduleCountdownTick(step: step + 1, begin: begin, seconds: seconds, generation: generation)
    }

    /// The countdown reached zero: the start path runs exactly once (REC-007-R3).
    private func completeCountdown() {
        countdownGeneration += 1   // no later tick of this countdown can act
        endCountdownSchedule()
        start(afterCountdown: true)
        if state == .recording {
            countdownStartedRecordingAt = countdownClock.now
        } else if state.isCountingDown {
            state = .idle   // refused at completion: its notice says why
        }
    }

    /// Cancels a countdown (Record, Cancel, Escape, or an automatic reason); nothing was written (REC-007-R6).
    func cancelCountdown(_ reason: RecordingCountdownCancel = .user) {
        guard state.isCountingDown else { return }
        countdownGeneration += 1
        endCountdownSchedule()
        lastCountdownCancel = reason
        state = .idle
    }

    private func endCountdownSchedule() {
        countdownTimer?.cancel()
        countdownTimer = nil
        ticker?.cancel()
        ticker = nil
        countdownSource = nil
    }

    /// REC-007-R5: the countdown ends on the changes that would stop a recording.
    private func checkCountdownContext() {
        let c = context()
        if !c.visualShown {
            cancelCountdown(.leftVisualizer)
        } else if !c.outputLive {
            cancelCountdown(.blackedOut)
        } else if c.paused {
            cancelCountdown(.paused)
        } else if c.source == nil || c.source !== countdownSource {
            cancelCountdown(.visualLost)
        } else if c.source?.isPresentingFrames == false {
            cancelCountdown(.presentationLost)
        }
    }

    // MARK: - Storage (REC-015-R4, R5)

    private func startStorageTicker() {
        guard let storageCheckInterval else { return }
        storageTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: storageCheckInterval)
                guard !Task.isCancelled, let self else { return }
                await self.checkStorage()
            }
        }
    }

    /// One storage sample: the free storage and the file's size are read off the main actor, the
    /// decision is made here; stops with `.lowStorage` when the policy says so. Unknown values never stop.
    func checkStorage() async {
        guard state == .recording, let recorder, let policy = storagePolicy else { return }
        let probe = storageProbe, folder = directory, url = recorder.url
        let reading = await Task.detached(priority: .utility) { () -> (Int64?, Int64?) in
            (probe.availableBytes(at: folder), RecordingStorage.fileBytes(at: url))
        }.value
        guard state == .recording, self.recorder === recorder else { return }
        storageReading = StorageReading(availableBytes: reading.0, fileBytes: reading.1)   // REC-009-R3
        refreshStatus()
        if policy.shouldStop(availableBytes: reading.0, fileBytes: reading.1, recordedSeconds: recorder.recordedSeconds) {
            stop(.lowStorage)
        }
    }

    private func startTicker() {
        guard let checkInterval else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: checkInterval)
                guard !Task.isCancelled, let self else { return }
                self.checkContext()
            }
        }
    }

    /// Updates the elapsed time and stops when the context no longer allows recording (REC-003-R11).
    func checkContext() {
        if state.isCountingDown {
            checkCountdownContext()   // REC-007-R5
            return
        }
        guard state == .recording else { return }
        elapsedSeconds = recorder?.recordedSeconds ?? 0
        refreshStatus()   // REC-009-R2
        let c = context()
        if !c.outputLive {
            stop(.blackedOut)
        } else if c.paused {
            stop(.paused)
        } else if let source, c.source !== source {
            stop(.visualChanged)
        } else if source == nil {
            stop(.visualChanged)
        } else if source?.isPresentingFrames == false {
            stop(.presentationLost)
        } else if recorder?.hasFailed == true {
            stop(.writerFailed)
        } else if shouldEndAudio(c) {
            endAudio()
        }
    }

    /// REC-004-R5: the source changed, a new session disarmed the tap, or the microphone consent was withdrawn.
    private func shouldEndAudio(_ c: Context) -> Bool {
        guard recordingAudio?.includesAudio == true, !audioEnded else { return false }
        if c.audioMode != recordingAudioMode { return true }
        if c.audioTap?.isArmed == false { return true }
        return recordingAudioMode == .microphone && !(c.includeMicrophone && c.microphoneGranted)
    }

    /// Ends the recording's audio for good; the video goes on (no silence is added).
    func endAudio() {
        guard state == .recording, recordingAudio?.includesAudio == true, !audioEnded else { return }
        disarmAudioTap?()
        disarmAudioTap = nil
        source?.videoRecording?.audioFeed = nil
        recorder?.endAudio()
        audioEnded = true
    }

    /// Stops the recording and finishes the file off the main thread (idempotent).
    func stop(_ requested: RecordingStopReason) {
        guard state == .recording, let recorder else { return }
        // REC-008-R7: the recorder's duration limit is the user's length when one is set.
        let reason: RecordingStopReason = requested == .durationReached && recordingLength != nil ? .timedStop : requested
        state = .finishing
        statusSummary = nil   // REC-009: the overlay shows only while recording
        lastStopReason = reason
        ticker?.cancel()
        ticker = nil
        storageTicker?.cancel()
        storageTicker = nil
        storagePolicy = nil
        source?.videoRecording = nil   // no later frame is offered
        source = nil
        disarmAudioTap?()   // REC-004: the tap is written only while a recording takes audio
        disarmAudioTap = nil
        elapsedSeconds = recorder.recordedSeconds
        Task { [weak self] in
            let result = await recorder.finish()
            self?.finished(result, reason: reason)
        }
    }

    private func finished(_ result: Result<RecordedVideo, RecordingFailure>, reason: RecordingStopReason) {
        state = .idle
        recorder = nil
        switch result {
        case .failure(let failure):
            fail(failure)
        case .success(let video):
            lastRecording = video   // REC-006-R4
            notice = reason == .timedStop ? (recordingLength?.stoppedNotice ?? reason.notice) : reason.notice
            if let debugDirectory {
                moveForTests(video, into: debugDirectory)
            } else {
                offered = video.url   // REC-012-R1: offered, nothing opens by itself
                inspectOfferedForTests(video.url)
            }
        }
        endBackgroundTask()
    }

    private func refuse(_ refusal: RecordingRefusal) {
        notice = refusal.notice
        probe = "refused: \(refusal.rawValue)"
    }

    private func fail(_ failure: RecordingFailure) {
        notice = failure.notice
        probe = "failed: \(failure)"
    }

    // MARK: - Status overlay (REC-009, contract C1, C2)

    /// The latest REC-015 readings (in memory only, REC-009-R7).
    struct StorageReading {
        var availableBytes: Int64?
        var fileBytes: Int64?
    }

    /// Recomputes the overlay's summary and lets the throttle raise a warning (rising levels only).
    private func refreshStatus() {
        guard state == .recording, let recorder else {
            statusSummary = nil
            return
        }
        let seconds: Double = recorder.recordedSeconds
        let summary = RecordingStatusSummary(statistics: recorder.statistics, policy: storagePolicy,
                                             availableBytes: storageReading.availableBytes,
                                             fileBytes: storageReading.fileBytes, recordedSeconds: seconds)
        if summary != statusSummary { statusSummary = summary }
        let droppedLevel: Int = summary.droppedWarning ? 1 : 0
        if warningThrottle.submit(.droppedFrames, level: droppedLevel, at: seconds) {
            raiseWarning(.droppedFrames, summary)
            return   // one warning per refresh: the storage one follows 0.25 s later (each is posted)
        }
        let storageLevel: Int = summary.storageLevel?.rawValue ?? 0
        if warningThrottle.submit(.storage, level: storageLevel, at: seconds) {
            raiseWarning(.storage, summary)
        }
    }

    private func raiseWarning(_ kind: RecordingWarningKind, _ summary: RecordingStatusSummary) {
        warningSequence += 1
        statusWarning = RecordingStatusWarning(kind: kind, storageLevel: summary.storageLevel,
                                               secondsLeft: summary.secondsLeft, sequence: warningSequence)
    }

    // MARK: - Background (REC-003-R11, research REC-003-D8)

    private func observeBackground() {
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                                                queue: .main) { [weak self] (_: Notification) in
            MainActor.assumeIsolated { self?.appEnteredBackground() }
        })
    }

    /// The app left the screen: finish the file while the system still runs the app.
    func appEnteredBackground() {
        cancelCountdown(.background)   // REC-007-R5: nothing to finish, nothing written
        guard state == .recording else { return }
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "REC-003 finish recording") { [weak self] in
                MainActor.assumeIsolated { self?.endBackgroundTask() }
            }
        }
        stop(.background)
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - DEBUG

    /// DEBUG: true when `-uitestStorage` is given (the view then shows the probe). False in Release.
    static var debugStorageRequested: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uitestStorage")
        #else
        return false
        #endif
    }

    /// DEBUG `-uitestStorage low` (always 50 MB free) or `dropAfter:<n>` (the first n readings 64 GB,
    /// then 50 MB), with a 1 s storage interval. nil in Release and without the option.
    static func debugStorageFromArguments() -> (probe: any StorageProbe, interval: Duration)? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "-uitestStorage"), i + 1 < arguments.count else { return nil }
        let value = arguments[i + 1]
        let ample: Int64 = 64_000_000_000
        let low: Int64 = 50_000_000
        if value == "low" { return (ScriptedStorageProbe(ampleReadings: 0, ample: ample, low: low), .seconds(1)) }
        if value.hasPrefix("dropAfter:"), let n = Int(value.dropFirst("dropAfter:".count)) {
            return (ScriptedStorageProbe(ampleReadings: n, ample: ample, low: low), .seconds(1))
        }
        #endif
        return nil
    }

    /// DEBUG: an offered recording is read back into `probe` (UI tests check it plays); nothing in Release.
    private func inspectOfferedForTests(_ url: URL) {
        #if DEBUG
        probe = "inspecting"
        Task { [weak self] in
            let info = await RecordedVideoInspector.inspect(url)
            guard let self, self.probe == "inspecting" else { return }
            self.probe = info?.summary ?? "failed: unreadable"
        }
        #endif
    }

    /// UI tests: the mover cannot be automated, so the file goes to a temporary folder and is read back.
    private func moveForTests(_ video: RecordedVideo, into folder: URL) {
        let destination = folder.appendingPathComponent(video.url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: video.url, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: video.url)
            probe = "failed: move"
            return
        }
        probe = "inspecting"
        Task { [weak self] in
            let info = await RecordedVideoInspector.inspect(destination)
            self?.probe = info?.summary ?? "failed: unreadable"
            if self?.notice == nil { self?.notice = "Recording saved." }
        }
    }
}

/// REC-009-R4: a recording warning to announce (rows X9f, X9g); `sequence` makes each one a change.
struct RecordingStatusWarning: Equatable, Sendable {
    let kind: RecordingWarningKind
    let storageLevel: RecordingStorageLevel?
    let secondsLeft: Int64?
    let sequence: Int
}

#if DEBUG
/// DEBUG `-uitestStorage`: the first `ampleReadings` readings return `ample`, later ones `low`.
final class ScriptedStorageProbe: StorageProbe, @unchecked Sendable {
    private let lock = NSLock()
    private var readings = 0
    private let ampleReadings: Int
    private let ample: Int64
    private let low: Int64

    init(ampleReadings: Int, ample: Int64, low: Int64) {
        self.ampleReadings = ampleReadings
        self.ample = ample
        self.low = low
    }

    func availableBytes(at directory: URL) -> Int64? {
        lock.withLock { () -> Int64 in
            readings += 1
            return readings <= ampleReadings ? ample : low
        }
    }
}
#endif

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

// MARK: - Sources (REC-003-R1)

extension CameraVisualHost: VideoRecordingSource {
    var recordingDevice: MTLDevice { compositor.device }
    var recordingDrawableSize: CGSize { view.metalLayer.drawableSize }
    var isPresentingFrames: Bool { isRunning }
}

extension PhotoVisualHost: VideoRecordingSource {
    var recordingDevice: MTLDevice { compositor.device }
    var recordingDrawableSize: CGSize { view.metalLayer.drawableSize }
    var isPresentingFrames: Bool { isRunning }
}

extension VideoVisualHost: VideoRecordingSource {
    var recordingDevice: MTLDevice { compositor.device }
    var recordingDrawableSize: CGSize { view.metalLayer.drawableSize }
    var isPresentingFrames: Bool { isRunning }
}

extension TextVisualHost: VideoRecordingSource {
    var recordingDevice: MTLDevice { compositor.device }
    var recordingDrawableSize: CGSize { view.metalLayer.drawableSize }
    var isPresentingFrames: Bool { isRunning }
}

extension NativeSpectrumHost: VideoRecordingSource {   // `recordingDevice` is in the host (its device is private)
    var recordingDrawableSize: CGSize { view.metalLayer.drawableSize }
    var isPresentingFrames: Bool { isRunning }
}
