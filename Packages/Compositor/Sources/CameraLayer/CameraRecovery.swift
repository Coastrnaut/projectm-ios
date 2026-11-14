// CameraRecovery.swift — the camera's retry rules on the caller's clock (CAM-013-R6, R7, R10, R14;
// research CAM-013-D3; data-model.md "CameraRecovery"). Plain Swift: builds on every platform,
// Linux included.
//
// A pure value: the host feeds it the feed's changes and its retries with a monotonic time in
// seconds (`ProcessInfo.systemUptime` in the app, a fake clock in tests) and asks how long the
// next retry must wait. Attempts in a row back off 0, 2, 4, 8, 16, then 30 s (cap) after the
// previous attempt; 10 s of running, or `reset()`, starts a new run. Counts are numbers only.

public struct CameraRecovery: Sendable, Equatable {
    /// Seconds to wait after the previous attempt, indexed by the attempts already made (capped).
    public static let backoff: [Double] = [0, 2, 4, 8, 16, 30]
    /// Running this long ends a run of failures.
    public static let stableInterval: Double = 10
    /// The Retry button's titles and VoiceOver labels (CAM-013-R3, R6).
    public static let retryTitle = "Retry"
    public static let retryingTitle = "Retrying…"
    public static let retryLabel = "Retry camera"
    public static let retryingLabel = "Retrying camera"

    /// Retries in a row since the last reset.
    public private(set) var attempts = 0
    /// When the last retry ran (caller's clock).
    public private(set) var lastAttemptAt: Double?
    /// When the feed last became running; nil while it is not running.
    public private(set) var runningSince: Double?
    /// The one automatic retry of this run of failures was used.
    public private(set) var automaticRetryUsed = false
    /// How many times each reason happened (the session; numbers only).
    public private(set) var counts: [CameraStopReason: Int] = [:]
    /// Retries performed (the session).
    public private(set) var retries = 0

    public init() {}

    /// The feed became running at `now`.
    public mutating func noteRunning(now: Double) {
        if runningSince == nil { runningSince = now }
    }

    /// The feed stopped for `reason` at `now`: counted; after a stable run the run of failures restarts.
    public mutating func noteStop(_ reason: CameraStopReason, now: Double) {
        counts[reason, default: 0] += 1
        if let since = runningSince {
            let ran: Double = now - since
            if ran >= Self.stableInterval { startNewRun() }
        }
        runningSince = nil
    }

    /// Seconds until the next retry may run (0: now).
    public func delayBeforeNextAttempt(now: Double) -> Double {
        guard attempts > 0, let last = lastAttemptAt else { return 0 }
        let index: Int = min(attempts, Self.backoff.count - 1)
        let due: Double = last + Self.backoff[index]
        return max(0, due - now)
    }

    /// A retry runs at `now`.
    public mutating func recordAttempt(now: Double) {
        attempts += 1
        retries += 1
        lastAttemptAt = now
        runningSince = nil
    }

    /// True (once per run of failures) when `reason` is retried without the user; marks it used.
    public mutating func claimAutomaticRetry(for reason: CameraStopReason) -> Bool {
        guard reason.retriesAutomatically, !automaticRetryUsed else { return false }
        automaticRetryUsed = true
        return true
    }

    /// The camera was stopped by the user or the app: a new run, counts kept.
    public mutating func reset() {
        startNewRun()
        runningSince = nil
    }

    private mutating func startNewRun() {
        attempts = 0
        lastAttemptAt = nil
        automaticRetryUsed = false
    }

    /// "reason:count" pairs in declaration order, then "retries:n" (diagnostics; numbers only).
    public var countsSummary: String {
        var parts: [String] = []
        for reason in CameraStopReason.allCases {
            if let count = counts[reason] { parts.append("\(reason.rawValue):\(count)") }
        }
        parts.append("retries:\(retries)")
        return parts.joined(separator: ",")
    }
}
