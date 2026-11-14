// StatusEvents.swift — captioned status events (ACC-011; spec specs/100-acc-011-captioned-status-events,
// contract contracts/status-events.md C1, research ACC-011-D1 to D7).
//
// * `StatusEventCatalog` is the transition table: one row per capture and recording status, with the
//   text on screen after the change, the announcement, the announcer kind, the cause and whether the end
//   state needs a transient caption. Its switches have no `default:`, so a new case of a status enum does
//   not compile until it has a row (ACC-011-R1, R2; research D5). Texts come from their existing owners
//   (UIStrings through `SourceStatusIndicator`, the FrameRecording notices, `CameraFeedState`, the badges);
//   nothing contract-pinned changes (ACC-011-R8).
// * `StatusEventRouter` owns ACC-004's `AccessibilityAnnouncer`, so every status announcement passes the
//   same per-kind gate (ACC-011-R3). The announcement rule (ACC-011-R4) is encoded in the rows: user-caused
//   rows, safety-relevant system rows and rows an earlier requirement announces are all posted; system rows
//   are dropped while the app is not active (ACC-011-R10, research D6). `.caption` rows show their visible
//   text for 4 s in `caption` (ACC-011-R7), replaced by a newer caption; no animation.
import AudioCore
import CameraLayer
import CaptureUI
import Foundation
import FrameRecording
import Observation
import PresentationLifecycle

/// Who caused a status change (ACC-011-R4, R10).
enum StatusCause: String, Sendable, Equatable {
    case user, system
}

/// How the end state shows as text (contract C1 "Pres.").
enum StatusPresentation: String, Sendable, Equatable {
    /// Persistent text is already on screen (indicator, badge, notice, panel, card, sheet).
    case persistent
    /// No persistent text: a transient status caption shows the visible text (ACC-011-R7).
    case caption
    /// iOS presents its own UI and VoiceOver reads it; no app announcement (X15 only).
    case systemPresented
}

/// One row of the transition table (data-model "StatusEvent").
struct StatusEvent: Sendable, Equatable {
    /// The transition ID of contract C1, e.g. "X1".
    let id: String
    let kind: AnnouncementKind
    let visibleText: String
    /// Empty only for `.systemPresented` rows (ACC-011-R2).
    let announcement: String
    let cause: StatusCause
    var presentation: StatusPresentation = .persistent
}

/// The transition table (contract C1). Main actor: the texts' owners (indicator, badges) are main-actor views.
@MainActor
enum StatusEventCatalog {
    static let frameReady = "Frame ready"
    static let recordingReady = "Recording ready"
    static let recordingSaved = "Recording saved."
    static let oscOff = "OSC off"
    static let restoringOutput = "Restoring output"
    static let sceneReopened = "Last scene reopened."

    // MARK: Source (X1-X3)

    /// X1-X3: the source changed. One text per change (ACC-011-R5): the AUD-014 hold text when In-App
    /// Playback goes on hold, else the indicator text; "Switching source…" while a switch waits (AUD-012).
    static func source(mode: AudioSourceMode?, state: AudioState, signal: String? = nil, switching: Bool = false,
                       reason: StopReason? = nil) -> StatusEvent {
        let status: String = SourceStatusIndicator.text(mode: mode, state: state, signal: signal, switching: switching)
        if switching {
            return StatusEvent(id: "X2", kind: .source, visibleText: status, announcement: status, cause: .user)
        }
        if let hold = SourceStatusIndicator.holdAnnouncement(mode: mode, state: state, reason: reason, signal: signal) {
            return StatusEvent(id: "X3", kind: .source, visibleText: status, announcement: hold, cause: .system)
        }
        return StatusEvent(id: "X1", kind: .source, visibleText: status, announcement: status, cause: .system)
    }

    /// Whether a source state is safety-relevant (contract C1 X1 "Why announced"); every state is announced
    /// under FR-070, this only documents which ones would be announced without it.
    nonisolated static func isSafetyRelevant(_ state: AudioState) -> Bool {
        switch state {
        case .noAudioReceived, .interrupted, .stopped, .endedBySystem: true
        case .notStarted, .waiting, .silent, .active, .paused: false
        }
    }

    /// The FR-015 message the banner shows for a stop reason (the visible text under the indicator).
    static func stopMessage(_ reason: StopReason) -> String {
        switch reason {
        case .cancelled, .permissionDenied, .microphoneUnavailable, .inAppPlaybackFailed, .interrupted,
             .audioRouteChanged, .endedBySystem, .unsupportedOS, .screenRecordingNotAllowed, .error:
            UIStrings.message(reason)
        }
    }

    // MARK: Background, route (X4, X5)

    static func background(_ notice: String) -> StatusEvent {
        StatusEvent(id: "X4", kind: .background, visibleText: notice, announcement: notice, cause: .system)
    }

    /// X5: `explanation` is the route text shown; `spoken` is `UIStrings.routeAnnouncement`.
    static func route(explanation: String, spoken: String) -> StatusEvent {
        StatusEvent(id: "X5", kind: .route, visibleText: explanation, announcement: spoken, cause: .system)
    }

    // MARK: Frame capture and sharing (X6-X8)

    static func frameNotice(_ notice: String) -> StatusEvent {
        StatusEvent(id: "X6", kind: .capture, visibleText: notice, announcement: notice, cause: .user)
    }

    static func frameOffered() -> StatusEvent {
        StatusEvent(id: "X7", kind: .capture, visibleText: frameReady, announcement: frameReady, cause: .user)
    }

    static func shareNotice(_ notice: String) -> StatusEvent {
        StatusEvent(id: "X8", kind: .capture, visibleText: notice, announcement: notice, cause: .user)
    }

    // MARK: Recording (X9-X14a; X9c REC-005; X9d, X9e REC-007)

    /// X9-X11: the recording state. `idle` is reached through the offered panel (X11); a stop reason or a
    /// failure shows its notice instead (X13, X14).
    static func recording(_ state: VideoRecordingCoordinator.State, elapsed: String = "0:00") -> StatusEvent {
        switch state {
        case .recording:
            let visible: String = "REC \(elapsed)"
            return StatusEvent(id: "X9", kind: .recording, visibleText: visible,
                               announcement: AccessibilityAnnouncer.recordingText(true), cause: .user)
        case .finishing:
            return StatusEvent(id: "X10", kind: .recording, visibleText: "Finishing…",
                               announcement: AccessibilityAnnouncer.recordingText(false), cause: .user)
        case .idle:
            return StatusEvent(id: "X11", kind: .recording, visibleText: recordingReady, announcement: recordingReady,
                               cause: .user)
        case .countingDown(let remaining):
            return recordingCountdown(remaining: remaining, first: true)
        }
    }

    /// REC-007-R7: X9d, one second of a countdown: "Recording in 3" on screen; spoken in full for the first
    /// second, then the bare number ("2", "1") on the same lane.
    static func recordingCountdown(remaining: Int, first: Bool) -> StatusEvent {
        let visible: String = countdownText(remaining)
        let spoken: String = first ? visible : String(remaining)
        return StatusEvent(id: "X9d", kind: .recording, visibleText: visible, announcement: spoken, cause: .user)
    }

    /// The row a recording state change posts (X9, X9d, X9e, X10), nil when none: a direct recording → idle
    /// also says "Recording stopped"; a countdown says its first second in full, then the number (REC-007);
    /// a countdown ending in idle posts its cancellation, and nothing when a refusal at completion has its
    /// own notice.
    static func recordingTransition(from old: VideoRecordingCoordinator.State, to new: VideoRecordingCoordinator.State,
                                    elapsed: String, countdownCancel: RecordingCountdownCancel?) -> StatusEvent? {
        if let remaining = new.countdownRemaining {
            return recordingCountdown(remaining: remaining, first: !old.isCountingDown)
        }
        if old.isCountingDown, new == .idle {
            return countdownCancel.map(countdownCancelled)
        }
        let state: VideoRecordingCoordinator.State = new == .idle && old == .recording ? .finishing : new
        return state == .idle ? nil : recording(state, elapsed: elapsed)
    }

    /// "Recording in 3".
    static func countdownText(_ remaining: Int) -> String { "Recording in \(remaining)" }

    /// REC-007-R6: X9e, a countdown was cancelled (a transient caption; no file was made).
    static func countdownCancelled(_ reason: RecordingCountdownCancel) -> StatusEvent {
        let text: String = reason.text
        return StatusEvent(id: "X9e", kind: .recording, visibleText: text, announcement: text,
                           cause: reason.isUser ? .user : .system, presentation: .caption)
    }

    /// REC-004-R9: X9a, what audio the recording that just started contains (after X9, same lane);
    /// X9b, its audio ended early (a source switch, a new session, the microphone setting turned off).
    static func recordingAudio(_ decision: RecordingAudioDecision) -> StatusEvent {
        let text: String = decision.statusText
        return StatusEvent(id: "X9a", kind: .recording, visibleText: text, announcement: text, cause: .user)
    }

    static func recordingAudioEnded() -> StatusEvent {
        let text: String = RecordingAudioDecision.endedText
        return StatusEvent(id: "X9b", kind: .recording, visibleText: text, announcement: text, cause: .system)
    }

    /// REC-005-R6: X9c, the recording that just started uses a lower profile than the one selected
    /// ("Recording at Standard: Needs HEVC, which this device cannot encode.").
    static func recordingQualityFallback(_ notice: String) -> StatusEvent {
        StatusEvent(id: "X9c", kind: .recording, visibleText: notice, announcement: notice, cause: .user)
    }

    static func recordingRefusal(_ refusal: RecordingRefusal) -> StatusEvent {
        switch refusal {
        case .noVisual, .notRecordable, .outputBlackedOut, .paused, .busy, .lowStorage:
            StatusEvent(id: "X12", kind: .recording, visibleText: refusal.notice, announcement: refusal.notice, cause: .user)
        }
    }

    /// X13: an automatic stop; the user's own stop has no notice and is X10.
    static func recordingStop(_ reason: RecordingStopReason) -> StatusEvent {
        switch reason {
        case .user:
            return recording(.finishing)
        case .durationReached, .background, .paused, .blackedOut, .visualChanged, .sizeChanged, .presentationLost,
             .writerFailed, .lowStorage:
            let notice: String = reason.notice ?? ""
            return StatusEvent(id: "X13", kind: .recording, visibleText: notice, announcement: notice, cause: .system)
        }
    }

    static func recordingFailure(_ failure: RecordingFailure) -> StatusEvent {
        switch failure {
        case .encoderUnavailable, .pixelBufferUnavailable, .writerFailed, .tooFewFrames, .cancelled, .storageFull:
            StatusEvent(id: "X14", kind: .recording, visibleText: failure.notice, announcement: failure.notice,
                        cause: .system)
        }
    }

    /// The recording coordinator's `notice` text, classified back to its row (X12, X13, X14, X14a).
    static func recordingNotice(_ notice: String) -> StatusEvent {
        if notice == recordingSaved {
            return StatusEvent(id: "X14a", kind: .recording, visibleText: notice, announcement: notice, cause: .user)
        }
        if notice.hasPrefix(RecordingQualityCatalog.fallbackPrefix) { return recordingQualityFallback(notice) }   // X9c
        if let refusal = RecordingRefusal.allCases.first(where: { $0.notice == notice }) {
            return recordingRefusal(refusal)
        }
        if let reason = RecordingStopReason.allCases.first(where: { $0.notice == notice }), reason != .writerFailed {
            return recordingStop(reason)
        }
        return StatusEvent(id: "X14", kind: .recording, visibleText: notice, announcement: notice, cause: .system)
    }

    // MARK: Camera (X15-X18)

    static func camera(_ state: CameraFeedState, position: CameraPosition = .back,
                       reason: CameraStopReason? = nil) -> StatusEvent {   // CAM-013-R12: the reason's text
        switch state {
        case .idle:
            let off: String = CameraIndicator.stoppedAnnouncement
            return StatusEvent(id: "X18", kind: .camera, visibleText: off, announcement: off, cause: .user,
                               presentation: .caption)
        case .requestingAccess:
            return StatusEvent(id: "X15", kind: .camera, visibleText: "Camera access requested", announcement: "",
                               cause: .user, presentation: .systemPresented)
        case .starting, .running:
            let label: String = CameraIndicator(state: state, position: position).label
            return StatusEvent(id: "X16", kind: .camera, visibleText: label, announcement: label, cause: .user)
        case .denied, .restricted, .unavailable, .interrupted, .failed:
            let notice: String = state.notice(position: position, reason: reason) ?? ""
            return StatusEvent(id: "X17", kind: .camera, visibleText: notice, announcement: notice, cause: .system)
        }
    }

    // MARK: OSC (X19, X20)

    /// X19 for a port (the listener opened), X20 for nil (the user's Stop on the badge).
    static func osc(port: UInt16?) -> StatusEvent {
        guard let port else {
            return StatusEvent(id: "X20", kind: .osc, visibleText: oscOff, announcement: oscOff, cause: .user,
                               presentation: .caption)
        }
        let text: String = OSCReceiverCoordinator.badgeText(port: port)
        return StatusEvent(id: "X19", kind: .osc, visibleText: text, announcement: text, cause: .system)
    }

    // MARK: Blackout (X21-X23)

    static func blackout(_ phase: OutputBlackout.Phase) -> StatusEvent {
        switch phase {
        case .blackedOut:
            let text: String = AccessibilityAnnouncer.blackoutText(true)
            return StatusEvent(id: "X21", kind: .output, visibleText: text, announcement: text, cause: .user)
        case .restoreWaiting, .fadingIn:
            return StatusEvent(id: "X22", kind: .output, visibleText: restoringOutput, announcement: restoringOutput,
                               cause: .user)
        case .live:
            let text: String = AccessibilityAnnouncer.blackoutText(false)
            return StatusEvent(id: "X23", kind: .output, visibleText: text, announcement: text, cause: .user,
                               presentation: .caption)
        }
    }

    // MARK: External display (X27, X28; OUT-002-R6)

    static let externalDisplayConnected = "External display connected"
    static let externalDisplayHeld = "External display connected. It shows the visualization when the recording ends."
    static let externalDisplayDisconnected = "External display disconnected"

    /// X27 for a settled connection (`held`: a running recording keeps the visualization on the device for
    /// now), X28 for the disconnect of a settled display. System rows with a transient caption.
    static func externalDisplay(_ change: ExternalDisplayConnectionChange) -> StatusEvent {
        switch change {
        case let .connected(held):
            let text: String = held ? externalDisplayHeld : externalDisplayConnected
            return StatusEvent(id: "X27", kind: .display, visibleText: text, announcement: text, cause: .system,
                               presentation: .caption)
        case .disconnected:
            return StatusEvent(id: "X28", kind: .display, visibleText: externalDisplayDisconnected,
                               announcement: externalDisplayDisconnected, cause: .system, presentation: .caption)
        }
    }

    // MARK: Session (X24-X26)

    static func recoveryOffer(title: String, message: String) -> StatusEvent {
        let spoken: String = "\(title) \(message)"
        return StatusEvent(id: "X24", kind: .session, visibleText: title, announcement: spoken, cause: .system)
    }

    static func lastSceneReopened() -> StatusEvent {
        StatusEvent(id: "X25", kind: .session, visibleText: sceneReopened, announcement: sceneReopened, cause: .user,
                    presentation: .caption)
    }

    /// X26: `spoken` is SCN-012's "<title>: <status>." text; the sheet shows the report.
    static func repairReport(_ spoken: String) -> StatusEvent {
        StatusEvent(id: "X26", kind: .session, visibleText: spoken, announcement: spoken, cause: .user)
    }
}

extension CameraFeedState {
    /// Every case, built by an exhaustive switch so a new case does not compile without being listed
    /// (ACC-011 research D5; the package enum is not `CaseIterable`).
    static var allStatusCases: [CameraFeedState] {
        let all: [CameraFeedState] = [.idle, .requestingAccess, .starting, .running, .denied, .restricted, .unavailable,
                                      .interrupted, .failed]
        for state in all {
            switch state {
            case .idle, .requestingAccess, .starting, .running, .denied, .restricted, .unavailable, .interrupted, .failed:
                break
            }
        }
        return all
    }
}

extension OutputBlackout.Phase {
    /// Every phase (ACC-011 completeness test); exhaustive by construction like `CameraFeedState.allStatusCases`.
    static var allStatusCases: [OutputBlackout.Phase] {
        let all: [OutputBlackout.Phase] = [.live, .blackedOut, .restoreWaiting, .fadingIn]
        for phase in all {
            switch phase {
            case .live, .blackedOut, .restoreWaiting, .fadingIn: break
            }
        }
        return all
    }
}

/// Posts status events: announcements through ACC-004's gate, captions for end states without text.
@MainActor
@Observable
final class StatusEventRouter {
    static let captionDuration: Double = 4.0

    /// The transient status caption (ACC-011-R7), nil when none shows.
    private(set) var caption: String?
    /// Every posted row's ID in order, including dropped ones as "-<id>" (tests).
    @ObservationIgnored private(set) var log: [String] = []

    @ObservationIgnored let announcer: AccessibilityAnnouncer
    /// False while the app is in the background or locked (ACC-011-R10).
    @ObservationIgnored var isActive: @MainActor () -> Bool = { () -> Bool in true }
    @ObservationIgnored private let schedule: @MainActor (Double, @escaping @MainActor () -> Void) -> Void
    @ObservationIgnored private var captionSequence = 0

    init(announcer: AccessibilityAnnouncer = AccessibilityAnnouncer(),
         schedule: @escaping @MainActor (Double, @escaping @MainActor () -> Void) -> Void = AccessibilityAnnouncer.sleepThen) {
        self.announcer = announcer
        self.schedule = schedule
    }

    func post(_ event: StatusEvent) {
        if event.cause == .system && !isActive() {
            log.append("-\(event.id)")
            return
        }
        log.append(event.id)
        if event.presentation != .systemPresented {
            announcer.announce(event.announcement, kind: event.kind)
        }
        if event.presentation == .caption {
            show(caption: event.visibleText)
        }
    }

    private func show(caption text: String) {
        captionSequence += 1
        let sequence = captionSequence
        caption = text
        schedule(Self.captionDuration) { [weak self] () -> Void in
            guard let self, self.captionSequence == sequence else { return }
            self.caption = nil
        }
    }
}
