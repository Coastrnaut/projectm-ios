// MemoryPressureCoordinator.swift — the one place that receives memory warnings (PERF-006-R1, R5,
// R14; research PERF-006-D1, D4, D8; specs/054-perf-006-memory-warning-recovery).
//
// `shared` observes `UIApplication.didReceiveMemoryWarningNotification` (nothing else in the app does)
// and runs `MemoryPressureRecovery`: cache steps on every warning, optional background work shed on a
// repeat within 30 s (or a critical signal from tests and the DEBUG probe) and restored 60 s after
// the last escalating signal by one main-actor task. No dispatch memory-pressure source: on iOS it
// fires for the same kernel event, so every warning would look like a repeat (D1).
//
// Owners register their steps: the shared texture pool (SharedTexturePool), the renderer's preset
// warm-up (AppCoordinator.prepareRenderer), the preset archive cache and the idle native spectrum
// (AppCoordinator). The shown visual, the audio source and stored settings are never touched.
import AudioCore
import Diagnostics
import Foundation
import PresentationLifecycle
import UIKit

@MainActor
final class MemoryPressureCoordinator {
    /// The app's coordinator; created on first use and observing the system warning from then on.
    static let shared = MemoryPressureCoordinator(observeSystemWarnings: true)

    let recovery: MemoryPressureRecovery
    private let clock: () -> Double
    private var observer: NSObjectProtocol?
    private var restoreTask: Task<Void, Never>?
    /// When the pending restore is due (monotonic seconds); nil when none is scheduled.
    private(set) var scheduledRestoreAt: Double?

    /// `clock`: monotonic seconds (tests pass a fake). `observeSystemWarnings` false: only `handle`.
    init(recovery: MemoryPressureRecovery = MemoryPressureRecovery(), observeSystemWarnings: Bool,
         clock: @escaping () -> Double = { Double(MonotonicClock.nowNanoseconds()) / 1_000_000_000 }) {
        self.recovery = recovery
        self.clock = clock
        recovery.onReport = { (report: MemoryPressureReport) in DiagnosticsLog.memoryRecovery(report.summary) }
        guard observeSystemWarnings else { return }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                          object: nil, queue: .main) { (_: Notification) in
            MainActor.assumeIsolated { _ = MemoryPressureCoordinator.shared.handle(.warning) }
        }
    }

    isolated deinit {
        restoreTask?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func register(_ responder: any MemoryPressureResponder) {
        recovery.register(responder)
    }

    var lastReport: MemoryPressureReport? { recovery.lastReport }

    /// Runs a recovery now and schedules the restore after an escalation.
    @discardableResult
    func handle(_ level: MemoryPressureLevel) -> MemoryPressureReport? {
        let report = recovery.handle(level, at: clock())
        scheduleRestoreIfNeeded()
        return report
    }

    /// Restores when the cool-down has ended (the restore task calls it; tests call it directly).
    @discardableResult
    func restoreIfDue() -> [String] {
        let restored = recovery.restoreIfDue(at: clock())
        scheduleRestoreIfNeeded()
        return restored
    }

    private func scheduleRestoreIfNeeded() {
        guard let until = recovery.shedUntil else {
            restoreTask?.cancel()
            restoreTask = nil
            scheduledRestoreAt = nil
            return
        }
        guard scheduledRestoreAt != until else { return }
        restoreTask?.cancel()
        scheduledRestoreAt = until
        let wait = max(0, until - clock())
        restoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.scheduledRestoreAt = nil
            self.restoreTask = nil
            self.restoreIfDue()   // reschedules itself if the cool-down was extended meanwhile
        }
    }
}
