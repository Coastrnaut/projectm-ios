// SessionRecoveryCoordinator.swift — crash-safe session recovery in the app (PERF-010-R1 to R12;
// specs/070-perf-010-crash-safe-session-recovery, contracts/session-recovery.md C1-C4).
//
// * Launch (AppCoordinator.init, before the OSC receiver exists): `SessionRecoveryPolicy.launch`
//   decides from the stored record and marks the session open. `prepare(settings:)` then applies the
//   consent rules: after an abnormal exit the stored OSC toggle is turned off (ADR-0032: never reopened
//   without the user), and while an offer is pending the scene settings are put at their defaults
//   with the stored visual held for Reopen. Camera is never held (it is never stored, CAM-001-R11).
// * Lifecycle: the background transition and terminate end the session; a return to the foreground
//   opens it again.
// * The offer (`offer == .pending`) is answered by `markReopened()` / `markStartedFresh()`; the
//   AppCoordinator applies the scene. One diagnostics event per abnormal launch, flags only.
import Diagnostics
import Foundation
import Observation
import UIKit
import VisualEffects

@MainActor
@Observable
final class SessionRecoveryCoordinator {
    enum Offer: String, Sendable { case none, pending, reopened, fresh }

    static let openKey = "session.recovery.open"
    static let sessionsSinceReopenKey = "session.recovery.sessionsSinceReopen"
    static let heldVisualKey = "session.recovery.heldVisual"
    static let allKeys = [openKey, sessionsSinceReopenKey, heldVisualKey]

    let decision: LaunchDecision
    private(set) var offer: Offer
    /// A committed scene can be reopened (set when the app holds one; never in a crash loop).
    private(set) var canReopen = false
    /// OSC had been on and was turned off by this launch (the card says so).
    private(set) var oscTurnedOff = false
    /// The visual Reopen restores (never Camera).
    @ObservationIgnored private(set) var heldVisual: VisualChoice?
    @ObservationIgnored private(set) var heldScene: SceneAutosaveHeldScene?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var record: SessionRecord
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(defaults: UserDefaults, suppressed: Bool) {
        self.defaults = defaults
        let stored = Self.read(defaults)
        let launch = SessionRecoveryPolicy.launch(stored, suppressed: suppressed)
        decision = launch.decision
        offer = launch.offersRecovery ? .pending : .none
        record = launch.record
        heldVisual = launch.record.heldVisual.flatMap(VisualChoice.init(rawValue:)).flatMap(Self.reopenable)
        Self.write(record, to: defaults)
    }

    /// The app's harness rule (research PERF-010-D5): DEBUG and automation builds only.
    static func harnessSuppresses(processInfo: ProcessInfo = .processInfo) -> Bool {
        #if DEBUG || PROJECTM_AUTOMATION
        let harness = true
        #else
        let harness = false
        #endif
        return SessionRecoveryPolicy.isSuppressed(arguments: processInfo.arguments, environment: processInfo.environment,
                                                  harness: harness)
    }

    /// `-uitestResetNotice`: forget every session (the next launch is clean).
    static func reset(_ defaults: UserDefaults) {
        allKeys.forEach(defaults.removeObject(forKey:))
    }

    var offersReopen: Bool { offer == .pending && canReopen }

    // MARK: - Launch (contract C1)

    /// Applies the consent rules before the OSC receiver is created; true when an offer is pending, so
    /// the app must not restore the committed scene silently (it holds it, or in a crash loop drops it).
    @discardableResult
    func prepare(settings: AppSettings) -> Bool {
        if decision.isAbnormal, settings.oscEnabled {
            settings.oscEnabled = false   // PERF-010-R2: the stored toggle; only the user turns it on again
            oscTurnedOff = true
        }
        guard offer == .pending else { return false }
        if decision.isCrashLoop {
            heldVisual = nil
        } else if heldVisual == nil {
            heldVisual = Self.reopenable(settings.visual) ?? Self.reopenable(settings.visualBeforeCamera)
        }
        record.heldVisual = heldVisual?.rawValue
        Self.write(record, to: defaults)
        Self.applyFreshScene(to: settings)
        return true
    }

    /// The committed scene read without applying it (nil: nothing to reopen; always nil in a crash
    /// loop). Logs the abnormal exit once (PERF-010-R11: flags only, no user data).
    func hold(_ scene: SceneAutosaveHeldScene?) {
        heldScene = decision.isCrashLoop ? nil : scene
        canReopen = heldScene != nil && heldVisual != nil
        guard decision.isAbnormal else { return }
        DiagnosticsLog.app.notice("""
            session recovery: abnormal exit; crash loop \(self.decision.isCrashLoop, privacy: .public), \
            scene available \(self.canReopen, privacy: .public), OSC turned off \(self.oscTurnedOff, privacy: .public)
            """)
    }

    /// PERF-010-R5: the scene settings at their defaults (nothing else is touched).
    static func applyFreshScene(to settings: AppSettings) {
        settings.visual = .projectM
        settings.circularSpectrumBars = AppSettings.defaultCircularSpectrumBars
        settings.linearSpectrumOrientation = .vertical
        settings.linearSpectrumSpacing = AppSettings.defaultLinearSpectrumSpacing
        settings.glowEnabled = false
        settings.glowIntensity = Double(BloomParameters.defaultIntensity)
        settings.glowRadius = Double(BloomParameters.defaultRadius)
        settings.glowThreshold = Double(BloomParameters.defaultThreshold)
    }

    private static func reopenable(_ visual: VisualChoice) -> VisualChoice? {
        visual.usesCamera ? nil : visual   // PERF-010-R3: never Camera
    }

    // MARK: - Answers (contract C3)

    /// Reopen: returns the held scene for the app to apply, and records the reopen (crash-loop count).
    func markReopened() -> SceneAutosaveHeldScene? {
        guard offersReopen else { return nil }
        let scene = heldScene
        heldScene = nil
        offer = .reopened
        record = SessionRecoveryPolicy.reopened(record)
        Self.write(record, to: defaults)
        return scene
    }

    func markStartedFresh() {
        guard offer == .pending else { return }
        heldScene = nil
        heldVisual = nil
        offer = .fresh
        record = SessionRecoveryPolicy.startedFresh(record)
        Self.write(record, to: defaults)
    }

    // MARK: - Lifecycle

    func startObservingLifecycle() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] (_: Notification) in
                MainActor.assumeIsolated { self?.sessionEnded() }
            })
        }
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil,
                                            queue: .main) { [weak self] (_: Notification) in
            MainActor.assumeIsolated { self?.sessionResumed() }
        })
    }

    func sessionEnded() {
        record = SessionRecoveryPolicy.ended(record)
        Self.write(record, to: defaults)
    }

    func sessionResumed() {
        record = SessionRecoveryPolicy.resumed(record)
        Self.write(record, to: defaults)
    }

    // MARK: - Probe and texts (contracts C2, C4)

    func probe(oscListening: Bool) -> String {
        "decision=\(decision.probeName) offer=\(offer.rawValue) reopen=\(offersReopen ? 1 : 0) osc=\(oscListening ? "listening" : "off")"
    }

    var title: String {
        decision.isCrashLoop ? "projectM closed unexpectedly again." : "projectM closed unexpectedly."
    }

    var message: String {
        offersReopen ? "Reopen your last scene or start fresh." : "Starting with a fresh scene."
    }

    static let oscMessage = "OSC was turned off. Turn it on in Settings when you need it."

    // MARK: - Storage

    static func read(_ defaults: UserDefaults) -> SessionRecord {
        SessionRecord(open: defaults.bool(forKey: openKey),
                      sessionsSinceReopen: defaults.object(forKey: sessionsSinceReopenKey) as? Int,
                      heldVisual: defaults.string(forKey: heldVisualKey))
    }

    static func write(_ record: SessionRecord, to defaults: UserDefaults) {
        defaults.set(record.open, forKey: openKey)
        if let count = record.sessionsSinceReopen {
            defaults.set(count, forKey: sessionsSinceReopenKey)
        } else {
            defaults.removeObject(forKey: sessionsSinceReopenKey)
        }
        if let visual = record.heldVisual {
            defaults.set(visual, forKey: heldVisualKey)
        } else {
            defaults.removeObject(forKey: heldVisualKey)
        }
    }
}
