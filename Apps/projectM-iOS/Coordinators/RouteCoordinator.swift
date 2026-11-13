// RouteCoordinator.swift — the audio route indicator's state (AUD-007-T12; AUD-007-R3, R7, R10;
// specs/026-aud-007-audio-output-route-indicator).
//
// Owns the route monitor (CaptureKit) and, on iOS, the observer of the session's route-change
// notification. For each change it shows a short explanation (about 4 s; the newest replaces the
// previous) and announces it to VoiceOver, both worded by CaptureUI's UIStrings for the current
// context: In-App Playback (outputs), Microphone (inputs), or none (no indicator, nothing shown).
// The context and whether the app is active are read through closures set by AppCoordinator.
// Port names stay in memory: never logged, stored or exported (AUD-007-R14).
import CaptureKit
import CaptureUI
import Observation
import UIKit

@MainActor
@Observable
final class RouteCoordinator {
    /// How long an explanation stays (a presentation detail; never asserted by tests).
    static let explanationSeconds: Double = 4

    let monitor: AudioRouteMonitor
    /// The explanation on screen, if any (identifier `routeExplanation`).
    private(set) var explanation: String?
    /// The indicator's context; nil = no indicator (System/App Capture, no source, ended).
    @ObservationIgnored var context: () -> AudioRouteContext? = { nil }
    /// False while the app is in the background or locked: no explanation for changes then.
    @ObservationIgnored var isActive: () -> Bool = { true }
    @ObservationIgnored private let announce: (String) -> Void
    @ObservationIgnored private var observer: AudioRouteObserver?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var shownSequence = 0

    /// - Parameters:
    ///   - observesSession: true in the app (the session's notifications reach the monitor); false in tests.
    ///   - announce: posts a VoiceOver announcement (tests record it).
    init(provider: any AudioRouteProviding, observesSession: Bool,
         announce: @escaping (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }) {
        monitor = AudioRouteMonitor(provider: provider)
        self.announce = announce
        if observesSession { observer = AudioRouteObserver(monitor: monitor) }
        monitor.onChange = { [weak self] change in self?.handle(change) }
    }

    /// The app's coordinator: the real session, or the UI tests' fake route (`-uitestFakeRoutes`).
    static func makeDefault() -> RouteCoordinator {
        #if DEBUG
        if UITestRouteProvider.isRequested { return RouteCoordinator(provider: UITestRouteProvider.shared, observesSession: true) }
        #endif
        return RouteCoordinator(provider: SystemAudioRouteProvider(), observesSession: true)
    }

    /// The route the indicator shows.
    var route: AudioRoute { monitor.route }

    /// Reads the route again without an explanation (a source started or its state changed).
    func refresh() {
        monitor.refresh()
    }

    /// One change from the monitor: explain and announce it when the context words it.
    func handle(_ change: AudioRouteChange) {
        guard isActive(), let context = context(), let text = UIStrings.routeExplanation(change, context: context) else { return }
        explanation = text
        shownSequence = change.sequence
        if let spoken = UIStrings.routeAnnouncement(change, context: context) { announce(spoken) }
        expiry?.cancel()
        let sequence = change.sequence
        expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.explanationSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.shownSequence == sequence else { return }
            self.explanation = nil
        }
    }

    isolated deinit {
        expiry?.cancel()
        observer?.invalidate()
    }
}
