// RecordingCountdown.swift — REC-007 (specs/175-rec-007-countdown, contract contracts/countdown.md, research
// REC-007-D2): the countdown's lengths, why a countdown was cancelled, and the clock that drives it.
//
// The clock is injected so tests advance time by hand (no wall-clock waits). The system clock reads
// `ProcessInfo.systemUptime` and schedules with a main-actor `Task.sleep` to an absolute deadline, so a
// countdown's ticks never drift.
import Foundation

/// REC-007-R1: Off (default), 3, 5 or 10 seconds.
enum RecordingCountdownLength: String, CaseIterable, Sendable {
    case off = "off"
    case three = "3"
    case five = "5"
    case ten = "10"

    static let defaultLength: RecordingCountdownLength = .off

    var seconds: Int {
        switch self {
        case .off: 0
        case .three: 3
        case .five: 5
        case .ten: 10
        }
    }

    /// "Off", "3 seconds".
    var title: String { self == .off ? "Off" : "\(seconds) seconds" }
}

/// REC-007-R5, R6: what cancelled a countdown.
enum RecordingCountdownCancel: String, CaseIterable, Sendable {
    case user, background, leftVisualizer, visualLost, presentationLost, blackedOut, paused

    static let cancelledText = "Countdown cancelled"

    /// The caption and announcement (row X9e).
    var text: String {
        switch self {
        case .user: Self.cancelledText
        case .background: Self.cancelledText + ": the app went to the background."
        case .leftVisualizer: Self.cancelledText + ": the visualizer was closed."
        case .visualLost: Self.cancelledText + ": the visual changed."
        case .presentationLost: Self.cancelledText + ": the visual stopped drawing."
        case .blackedOut: Self.cancelledText + ": the output is blacked out."
        case .paused: Self.cancelledText + ": the visualizer is paused."
        }
    }

    var isUser: Bool { self == .user }
}

/// A scheduled countdown step that can be cancelled.
@MainActor
protocol RecordingCountdownTimer: AnyObject {
    func cancel()
}

/// The countdown's time source (seconds on a monotonic clock).
@MainActor
protocol RecordingCountdownClock: AnyObject {
    var now: Double { get }
    /// Runs `action` on the main actor at `deadline` (at once when it has passed) unless cancelled.
    func schedule(at deadline: Double, _ action: @escaping @MainActor () -> Void) -> any RecordingCountdownTimer
}

/// The app's clock: system uptime and a sleeping main-actor task per step.
@MainActor
final class SystemRecordingCountdownClock: RecordingCountdownClock {
    private final class SleepTimer: RecordingCountdownTimer {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
    }

    var now: Double { ProcessInfo.processInfo.systemUptime }

    func schedule(at deadline: Double, _ action: @escaping @MainActor () -> Void) -> any RecordingCountdownTimer {
        let timer = SleepTimer()
        let delay: Double = max(deadline - now, 0)
        timer.task = Task { @MainActor () -> Void in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            action()
        }
        return timer
    }
}
