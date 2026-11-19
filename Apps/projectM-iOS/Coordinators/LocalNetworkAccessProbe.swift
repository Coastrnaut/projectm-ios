// LocalNetworkAccessProbe.swift — how the OSC receiver learns the Local Network permission (ADR-0125; QA-011 device
// run 2026-11-19; OSC-001-T26, UIX-015, FILE-013).
//
// iOS has no Local Network query, and a plain UDP listener neither makes iOS ask nor fails when access is off: on D2
// (iPadOS 27.2) and D3 (iPadOS 26.5) the receiver reported "Listening" with the permission never asked, so the
// app treated "listening" as granted and could never show the denied notice. Instead, when the receiver starts and
// the answer is unknown this launch, the probe runs one short Bonjour browse for the app's own declared type
// (`NetworkOSCPeerBrowser(resolves: false)`: `_projectm-osc._udp` in `local.`, no resolution, no connection).
// A browse makes iOS ask; its result decides:
// * policy denied (`.failed(.localNetworkDenied)`) → denied;
// * any service found → granted;
// * browsing for `settleSeconds` with the app still active → granted (while iOS's prompt shows, the app is inactive,
//   the receiver stops and the probe is cancelled; it runs again when the app is active, after the answer);
// * any other failure, or `maximumSeconds` without an answer → still unknown.
// The browse is cancelled as soon as it decides, and after `maximumSeconds` at the latest. The answer is kept in
// memory for this launch only (iOS ends the app when the permission is revoked in Settings).
import Foundation
import PerformanceControl

/// What the app knows about the Local Network permission this launch.
enum LocalNetworkAccess: Equatable, Sendable {
    case unknown, granted, denied
}

@MainActor
final class LocalNetworkAccessProbe {
    static let defaultSettleSeconds: Double = 2
    static let defaultMaximumSeconds: Double = 5

    private(set) var access: LocalNetworkAccess = .unknown
    /// True while a browse runs.
    var isRunning: Bool { browser != nil }
    /// Browses started this launch (tests).
    private(set) var runs = 0
    /// Called on the main actor when `access` changes.
    var onChange: (@MainActor (LocalNetworkAccess) -> Void)?

    private let makeBrowser: @MainActor () -> (any OSCPeerBrowsing)?
    private let settleSeconds: Double
    private let maximumSeconds: Double
    private var browser: (any OSCPeerBrowsing)?
    private var generation = 0

    init(settleSeconds: Double = LocalNetworkAccessProbe.defaultSettleSeconds,
         maximumSeconds: Double = LocalNetworkAccessProbe.defaultMaximumSeconds,
         makeBrowser: @escaping @MainActor () -> (any OSCPeerBrowsing)?) {
        self.settleSeconds = settleSeconds
        self.maximumSeconds = maximumSeconds
        self.makeBrowser = makeBrowser
    }

    /// The app's probe: the real browser without resolution, or none for the DEBUG fake receivers (no real network).
    static func system() -> LocalNetworkAccessProbe {
        LocalNetworkAccessProbe {
            #if DEBUG
            if UITestFakeOSC.isRequested || UITestOSCFailure.receiverIfRequested() != nil || UITestFakeDiscovery.isRequested { return nil }
            #endif
            return NetworkOSCPeerBrowser(resolves: false)
        }
    }

    /// The answer a browse event gives: nil while it says nothing yet (`.browsing` waits for the settle time).
    static func decision(for event: OSCBrowserEvent) -> LocalNetworkAccess? {
        switch event {
        case .failed(.localNetworkDenied): .denied
        case .failed: .unknown
        case .peers(let peers): peers.isEmpty ? nil : .granted
        case .browsing: nil
        }
    }

    /// One bounded browse, unless the answer is known or a browse already runs.
    func start() {
        guard access == .unknown, browser == nil, let made = makeBrowser() else { return }
        generation += 1
        runs += 1
        let run = generation
        browser = made
        made.start { [weak self] (event: OSCBrowserEvent) -> Void in
            Task { @MainActor [weak self] in self?.handle(event, run: run) }
        }
        after(maximumSeconds, run: run) { $0.finish(run: run, with: nil) }
    }

    /// Cancels a running browse (the receiver stopped, for example while iOS's prompt shows).
    func stop() {
        generation += 1
        browser?.cancel()
        browser = nil
    }

    private func handle(_ event: OSCBrowserEvent, run: Int) {
        guard run == generation, browser != nil else { return }
        if case .browsing = event {
            after(settleSeconds, run: run) { $0.finish(run: run, with: .granted) }
            return
        }
        guard let decision = Self.decision(for: event) else { return }
        finish(run: run, with: decision == .unknown ? nil : decision)
    }

    private func finish(run: Int, with decision: LocalNetworkAccess?) {
        guard run == generation, browser != nil else { return }
        stop()
        guard let decision, decision != access else { return }
        access = decision
        onChange?(decision)
    }

    private func after(_ seconds: Double, run: Int, _ body: @escaping @MainActor (LocalNetworkAccessProbe) -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            guard let self, run == self.generation else { return }
            body(self)
        }
    }
}
