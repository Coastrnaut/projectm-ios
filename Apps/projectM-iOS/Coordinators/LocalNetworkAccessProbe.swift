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
//
// ADR-0125 follow-up 2 (QA-011 pass 9, D2, 2026-11-19): after Don't Allow the denied notice still never showed, and
// the run kept no trace of what the browse had reported. Two changes:
// * A browse that saw the app inactive (iOS's prompt) is restarted when the app is active again, before anything
//   is decided: a browse that was already running when the person answered need not report the new policy, while a
//   fresh one reports the denial at once. (When the scene itself went inactive, the receiver already stopped the
//   probe and starts it again; this covers the case where only the application's state changed.)
// * DEBUG builds keep the last events (`diagnostic`, shown by the hidden `localNetworkProbe` text) so a device run
//   says which events came (browsing, a policy denial, another failure with its code) and what was decided.
//
// ADR-0125 follow-up 3 (QA-011 prompt-flow on D1, iPhone 15, iOS 27.0.1, 2026-11-23 and 2026-11-24, every run):
// iOS's Local Network prompt left the app active (the probe never saw "inactive"), so the first browse reported
// `browsing`, settled 2 s later with the prompt still on screen ("start 1, browsing, stop, settled → granted") and
// Don't Allow, tapped about 0.4 s after that, was never seen. Activity cannot tell that the prompt is up, so a grant
// that rests only on the settle is now *unconfirmed*: it is published (no notice, no explainer), but fresh browses
// follow every `recheckSeconds` until `confirmSeconds` have passed since the first browse this launch. A fresh browse
// reports a denial at once (D3, iPadOS 26.5, 2026-11-22: "start 2, browsing, failed policyDenied"), which turns the
// answer to denied. A policy denial or a found service is final at once; a settle after the window is final too.
// The rechecks stop with the receiver (OSC off or the app inactive) and resume with it while the answer is not final.
import Foundation
import Observation
import PerformanceControl
import UIKit

/// What the app knows about the Local Network permission this launch.
enum LocalNetworkAccess: Equatable, Sendable {
    case unknown, granted, denied
}

@MainActor
@Observable
final class LocalNetworkAccessProbe {
    static let defaultSettleSeconds: Double = 2
    static let defaultMaximumSeconds: Double = 5
    /// Follow-up 3: how long after the first browse a settle-only grant stays unconfirmed and is rechecked.
    static let defaultConfirmSeconds: Double = 30
    /// Follow-up 3: the pause (active time) between an unconfirmed grant and the next fresh browse.
    static let defaultRecheckSeconds: Double = 2
    /// How many events `diagnostic` keeps.
    static let historyLimit = 12

    private(set) var access: LocalNetworkAccess = .unknown
    /// True once the answer is settled for this launch (a denial, a found service, or a settle after
    /// `confirmSeconds`); until then a granted answer is unconfirmed and rechecked (follow-up 3).
    private(set) var isFinal = false
    /// True while a browse runs.
    var isRunning: Bool { browser != nil }
    /// Browses started this launch (tests).
    private(set) var runs = 0
    /// The last events, oldest first ("start 1", "browsing", "inactive", "restart", "failed dns -65570", "denied" …).
    private(set) var history: [String] = []
    /// Called on the main actor when `access` changes.
    @ObservationIgnored var onChange: (@MainActor (LocalNetworkAccess) -> Void)?

    @ObservationIgnored private let makeBrowser: @MainActor () -> (any OSCPeerBrowsing)?
    /// Whether the app is active. The settle and the time limit count only while it is: on D2 (iPadOS 27.2, QA-011
    /// 2026-11-19) the receiver kept browsing while iOS's prompt showed, the 2 s settle granted before the person
    /// answered, and Don't Allow then showed no notice.
    @ObservationIgnored private let isActive: @MainActor () -> Bool
    @ObservationIgnored private let settleSeconds: Double
    @ObservationIgnored private let maximumSeconds: Double
    @ObservationIgnored private let confirmSeconds: Double
    @ObservationIgnored private let recheckSeconds: Double
    /// Monotonic seconds (tests may pass their own clock).
    @ObservationIgnored private let now: @MainActor () -> Double
    /// When the first browse of this launch started (`now()`).
    @ObservationIgnored private var firstStart: Double?
    @ObservationIgnored private var browser: (any OSCPeerBrowsing)?
    @ObservationIgnored private var generation = 0

    init(settleSeconds: Double = LocalNetworkAccessProbe.defaultSettleSeconds,
         maximumSeconds: Double = LocalNetworkAccessProbe.defaultMaximumSeconds,
         confirmSeconds: Double = LocalNetworkAccessProbe.defaultConfirmSeconds,
         recheckSeconds: Double = LocalNetworkAccessProbe.defaultRecheckSeconds,
         now: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime },
         isActive: @escaping @MainActor () -> Bool = { true },
         makeBrowser: @escaping @MainActor () -> (any OSCPeerBrowsing)?) {
        self.isActive = isActive
        self.settleSeconds = settleSeconds
        self.maximumSeconds = maximumSeconds
        self.confirmSeconds = confirmSeconds
        self.recheckSeconds = recheckSeconds
        self.now = now
        self.makeBrowser = makeBrowser
    }

    /// The app's probe: the real browser without resolution, or none for the DEBUG fake receivers (no real network).
    static func system() -> LocalNetworkAccessProbe {
        LocalNetworkAccessProbe(isActive: { UIApplication.shared.applicationState == .active }) {
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

    /// A short name for an event in `history` (never a peer's name).
    static func describe(_ event: OSCBrowserEvent) -> String {
        switch event {
        case .browsing: "browsing"
        case .peers(let peers): "peers \(peers.count)"
        case .failed(.localNetworkDenied): "failed policyDenied"
        case .failed(.portInUse): "failed portInUse"
        case .failed(.unavailable): "failed unavailable"
        case .failed(.other(let code)): "failed \(code)"
        }
    }

    /// "access=<a> runs=<n> running=<yes|no> | <last events>" (the DEBUG `localNetworkProbe` text).
    var diagnostic: String {
        "access=\(access) runs=\(runs) running=\(isRunning ? "yes" : "no") | " + history.joined(separator: ", ")
    }

    /// One bounded browse, unless the answer is final or a browse already runs.
    func start() {
        guard !isFinal, browser == nil, let made = makeBrowser() else { return }
        if firstStart == nil { firstStart = now() }
        generation += 1
        runs += 1
        let run = generation
        browser = made
        note("start \(runs)")
        made.start { [weak self] (event: OSCBrowserEvent) -> Void in
            Task { @MainActor [weak self] in self?.handle(event, run: run) }
        }
        whileActive(maximumSeconds, run: run) { $0.finish(run: run, with: nil, final: false, reason: "limit") }
        watchActivity(run: run)
    }

    /// Cancels a running browse (the receiver stopped, for example while iOS's prompt shows) and any pending recheck.
    func stop() {
        generation += 1
        if browser != nil { note("stop") }
        browser?.cancel()
        browser = nil
    }

    private func note(_ entry: String) {
        history.append(entry)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }

    private func handle(_ event: OSCBrowserEvent, run: Int) {
        guard run == generation, browser != nil else { return }
        note(Self.describe(event))
        if case .browsing = event {
            whileActive(settleSeconds, run: run) { (probe: LocalNetworkAccessProbe) -> Void in
                // Follow-up 3: browsing proves nothing while iOS's prompt may still be up with the app active.
                let elapsed = probe.now() - (probe.firstStart ?? probe.now())
                probe.finish(run: run, with: .granted, final: elapsed >= probe.confirmSeconds, reason: "settled")
            }
            return
        }
        guard let decision = Self.decision(for: event) else { return }
        finish(run: run, with: decision == .unknown ? nil : decision, final: decision != .unknown, reason: "event")
    }

    private func finish(run: Int, with decision: LocalNetworkAccess?, final: Bool, reason: String) {
        guard run == generation, browser != nil else { return }
        stop()
        let unconfirmed = decision == .granted && !final
        note("\(reason) → \(decision.map { "\($0)" } ?? "unknown")\(unconfirmed ? " (unconfirmed)" : "")")
        if decision != nil, final { isFinal = true }
        if let decision, decision != access {
            access = decision
            onChange?(decision)
        }
        // Follow-up 3: an unconfirmed grant (or a run that ended without an answer after one) is rechecked.
        if !isFinal, access == .granted { scheduleRecheck() }
    }

    /// Follow-up 3: a fresh browse after `recheckSeconds` of active time, unless the probe was stopped or started
    /// meanwhile (either changes `generation`).
    private func scheduleRecheck() {
        let token = generation
        Task { @MainActor [weak self] in
            var activeFor = 0.0
            while activeFor < (self?.recheckSeconds ?? 0) {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, token == self.generation else { return }
                activeFor = self.isActive() ? activeFor + 0.05 : 0
            }
            guard let self, token == self.generation, self.browser == nil, !self.isFinal else { return }
            self.note("recheck")
            self.start()
        }
    }

    /// Runs `body` once the app has been active for `seconds` in a row (checked every 50 ms), unless the
    /// run ends first. Time spent inactive (iOS's prompt) restarts the count.
    private func whileActive(_ seconds: Double, run: Int, _ body: @escaping @MainActor (LocalNetworkAccessProbe) -> Void) {
        Task { @MainActor [weak self] in
            var activeFor = 0.0
            while activeFor < seconds {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, run == self.generation else { return }
                activeFor = self.isActive() ? activeFor + 0.05 : 0
            }
            guard let self, run == self.generation else { return }
            body(self)
        }
    }

    /// Follow-up 2: when the app turns active again while this run is undecided, the browse starts over (a new run;
    /// the old browser's later events are ignored).
    private func watchActivity(run: Int) {
        Task { @MainActor [weak self] in
            var wasInactive = false
            while true {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, run == self.generation, self.browser != nil else { return }
                let active = self.isActive()
                if !active, !wasInactive { self.note("inactive") }
                if active, wasInactive {
                    self.note("restart")
                    self.stop()
                    self.start()
                    return
                }
                wasInactive = !active
            }
        }
    }
}
