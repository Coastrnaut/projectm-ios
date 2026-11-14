// StereoPhaseWarning.swift — ANL-013's phase-inversion warning in the app (ANL-013-R7, R8; contract
// specs/196-anl-013-stereo-correlation/contracts/stereo-correlation.md C5; research ANL-013-D5).
//
// The native visual's analysis bus raises the warning after r < −0.5 for 1 s and clears it after
// r > −0.3 for 1 s (the hysteresis lives in AnalysisFeatures' `StereoCorrelationMeter`). The visual
// reports each change on the main actor; this presenter:
// * keeps `isRaised` (observed by FR-042's source indicator, which appends `indicatorSuffix`);
// * posts ACC-011 status events on the `source` lane through the router: X3a when raised, at most once
//   per 30 s (`PhaseWarningAnnouncementThrottle`, injected clock), and X3b when a raise that was
//   announced clears (a transient caption). Both are system rows: the router drops them while the
//   app is inactive;
// * formats FR-048's overlay line ("stereo: r -0.98 phase-inverted").
// With mono or an AUD-009 mode other than Mix the channels are identical, r is 1 and nothing is raised.
import Foundation
import Observation

/// At most one raise announcement per `interval` seconds; a clear is announced only after an announced raise.
struct PhaseWarningAnnouncementThrottle: Equatable, Sendable {
    static let interval: Double = 30

    private(set) var lastRaiseAnnouncedAt: Double = -.infinity
    private(set) var raiseAnnounced = false

    /// The warning was raised at `now`: whether to announce it.
    mutating func raised(now: Double) -> Bool {
        guard now - lastRaiseAnnouncedAt >= Self.interval else {
            raiseAnnounced = false
            return false
        }
        lastRaiseAnnouncedAt = now
        raiseAnnounced = true
        return true
    }

    /// The warning cleared: whether to announce it (only when its raise was announced).
    mutating func cleared() -> Bool {
        defer { raiseAnnounced = false }
        return raiseAnnounced
    }
}

@MainActor
@Observable
final class StereoPhaseWarningPresenter {
    static let warningText = "Stereo channels look phase-inverted"
    static let clearedText = "Stereo phase normal"
    /// FR-042: appended to the source indicator while raised.
    static let indicatorSuffix = " · " + warningText

    /// The warning is raised now.
    private(set) var isRaised = false

    @ObservationIgnored private(set) var throttle = PhaseWarningAnnouncementThrottle()
    @ObservationIgnored var post: @MainActor (StatusEvent) -> Void = { (_: StatusEvent) -> Void in }
    @ObservationIgnored private let now: @MainActor () -> Double

    init(now: @escaping @MainActor () -> Double = { () -> Double in ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    /// The native visual reported a change (or the visual stopped: false).
    func update(_ raised: Bool) {
        guard raised != isRaised else { return }
        isRaised = raised
        if raised {
            if throttle.raised(now: now()) { post(StatusEventCatalog.stereoPhase(raised: true)) }
        } else if throttle.cleared() {
            post(StatusEventCatalog.stereoPhase(raised: false))
        }
    }

    /// FR-048's overlay line for correlation `r`: "stereo: r 0.98", "stereo: r -0.97 phase-inverted".
    nonisolated static func overlayLine(correlation r: Float, raised: Bool) -> String {
        let value: Float = r.isFinite ? min(max(r, -1), 1) : 0
        let number: String = String(format: "%.2f", Double(value))
        return raised ? "stereo: r \(number) phase-inverted" : "stereo: r \(number)"
    }
}
