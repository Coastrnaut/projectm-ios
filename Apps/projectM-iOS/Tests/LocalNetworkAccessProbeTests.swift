// LocalNetworkAccessProbeTests.swift — ADR-0125 (QA-011 device run 2026-11-19): the short Bonjour browse that makes iOS
// ask for Local Network and reports its answer, with a fake browser (no networking), alone and through the OSC
// receiver coordinator (the denied notice, the explainer status, the browse following the listener).
import PerformanceControl
import Synchronization
import XCTest
@testable import projectM_iOS

@MainActor
final class LocalNetworkAccessProbeTests: XCTestCase {
    private final class FakeBrowser: OSCPeerBrowsing, Sendable {
        let starts = Mutex(0)
        let cancels = Mutex(0)
        private let events = Mutex<(@Sendable (OSCBrowserEvent) -> Void)?>(nil)
        func start(events: @escaping @Sendable (OSCBrowserEvent) -> Void) {
            starts.withLock { $0 += 1 }
            self.events.withLock { $0 = events }
        }
        func cancel() { cancels.withLock { $0 += 1 } }
        func deliver(_ event: OSCBrowserEvent) { events.withLock { $0 }?(event) }
    }

    /// Fast timings so no test waits long (owner rule 7). `confirm: 0` makes a settle final at once (the
    /// follow-up 3 rechecks have their own tests below).
    private func makeProbe(_ browser: FakeBrowser, settle: Double = 0.1, maximum: Double = 0.5,
                           confirm: Double = 0) -> LocalNetworkAccessProbe {
        LocalNetworkAccessProbe(settleSeconds: settle, maximumSeconds: maximum, confirmSeconds: confirm) { browser }
    }

    private func settle(_ seconds: Double = 0.05) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    func testDecisionPerEvent() {
        XCTAssertEqual(LocalNetworkAccessProbe.decision(for: .failed(.localNetworkDenied)), .denied)
        XCTAssertEqual(LocalNetworkAccessProbe.decision(for: .failed(.portInUse)), .unknown)
        XCTAssertEqual(LocalNetworkAccessProbe.decision(for: .peers([OSCDiscoveredPeer(name: "projectM 1A2B")])), .granted)
        XCTAssertNil(LocalNetworkAccessProbe.decision(for: .peers([])))
        XCTAssertNil(LocalNetworkAccessProbe.decision(for: .browsing), "browsing waits for the settle time")
    }

    func testPolicyDeniedDeniesAndStopsTheBrowse() async {
        let browser = FakeBrowser()
        let probe = makeProbe(browser)
        probe.start()
        XCTAssertTrue(probe.isRunning)
        browser.deliver(.failed(.localNetworkDenied))
        await settle()
        XCTAssertEqual(probe.access, .denied)
        XCTAssertFalse(probe.isRunning)
        XCTAssertEqual(browser.cancels.withLock { $0 }, 1, "stopped as soon as it decided")
        probe.start()
        XCTAssertEqual(probe.runs, 1, "no second browse once the answer is known")
    }

    func testBrowsingThroughTheSettleTimeGrants() async {
        let browser = FakeBrowser()
        let probe = makeProbe(browser)
        probe.start()
        browser.deliver(.browsing)
        await settle()
        XCTAssertEqual(probe.access, .unknown, "not before the settle time")
        await settle(0.2)
        XCTAssertEqual(probe.access, .granted)
        XCTAssertFalse(probe.isRunning)
    }

    func testAFoundServiceGrantsAtOnce() async {
        let browser = FakeBrowser()
        let probe = makeProbe(browser, settle: 5)
        probe.start()
        browser.deliver(.peers([OSCDiscoveredPeer(name: "projectM 9F00")]))
        await settle()
        XCTAssertEqual(probe.access, .granted)
    }

    /// iOS's prompt makes the app inactive: the receiver stops and the browse is cancelled; nothing is decided until
    /// the next start after the answer.
    func testStopBeforeTheSettleTimeDecidesNothingAndTheNextStartAsksAgain() async {
        let browser = FakeBrowser()
        let probe = makeProbe(browser)
        probe.start()
        browser.deliver(.browsing)
        probe.stop()
        await settle(0.3)
        XCTAssertEqual(probe.access, .unknown)
        probe.start()
        XCTAssertEqual(probe.runs, 2)
        browser.deliver(.failed(.localNetworkDenied))
        await settle()
        XCTAssertEqual(probe.access, .denied)
    }

    /// D2 (iPadOS 27.2, QA-011 2026-11-19): the browse kept running while iOS's prompt made the app inactive, the
    /// settle granted before the answer and Don't Allow showed no notice. Inactive time must not count.
    func testInactiveTimeDoesNotSettleAndTheDenialAfterThePromptDecides() async {
        let browser = FakeBrowser()
        let active = Mutex(true)
        let probe = LocalNetworkAccessProbe(settleSeconds: 0.1, maximumSeconds: 0.3,
                                            isActive: { active.withLock { $0 } }) { browser }
        probe.start()
        browser.deliver(.browsing)
        active.withLock { $0 = false }   // iOS's prompt shows
        await settle(0.5)
        XCTAssertEqual(probe.access, .unknown, "no grant while the prompt shows")
        XCTAssertTrue(probe.isRunning, "the time limit does not run out while inactive")
        browser.deliver(.failed(.localNetworkDenied))   // Don't Allow
        active.withLock { $0 = true }
        await settle()
        XCTAssertEqual(probe.access, .denied)
    }

    /// Follow-up 2 (D2 pass 9, 2026-11-19): Don't Allow still showed no notice. When only the application's state
    /// changed (the receiver kept running), the browse that ran through iOS's prompt starts over once the app is
    /// active again; the old browser's late events are ignored and the fresh browse's denial decides.
    func testABrowseThatSawTheAppInactiveStartsOverWhenActiveAgain() async {
        let first = FakeBrowser(), second = FakeBrowser()
        let made = Mutex(0)
        let active = Mutex(true)
        let probe = LocalNetworkAccessProbe(settleSeconds: 0.1, maximumSeconds: 1, isActive: { active.withLock { $0 } }) {
            let count: Int = made.withLock { $0 += 1; return $0 }
            return count == 1 ? first : second
        }
        probe.start()
        first.deliver(.browsing)
        active.withLock { $0 = false }   // iOS's prompt shows
        await settle(0.25)
        XCTAssertEqual(probe.access, .unknown, "no grant while the prompt shows")
        XCTAssertEqual(probe.runs, 1)
        active.withLock { $0 = true }   // answered
        await settle(0.15)
        XCTAssertEqual(probe.runs, 2, "a fresh browse after the prompt")
        XCTAssertEqual(first.cancels.withLock { $0 }, 1, "the browse that ran through the prompt is cancelled")
        XCTAssertEqual(second.starts.withLock { $0 }, 1)
        first.deliver(.browsing)   // late, from the cancelled browse: ignored
        second.deliver(.failed(.localNetworkDenied))
        await settle()
        XCTAssertEqual(probe.access, .denied)
        XCTAssertFalse(probe.isRunning)
        XCTAssertTrue(probe.diagnostic.hasPrefix("access=denied runs=2 running=no | "), probe.diagnostic)
        for entry in ["start 1", "browsing", "inactive", "restart", "start 2", "failed policyDenied", "event → denied"] {
            XCTAssertTrue(probe.history.contains(entry), "\(entry) in \(probe.history)")
        }
    }

    /// The diagnostic keeps a failure's code (never a peer's name) and at most `historyLimit` entries.
    func testTheDiagnosticNamesOtherFailuresAndStaysShort() async {
        let browser = FakeBrowser()
        let probe = makeProbe(browser)
        probe.start()
        browser.deliver(.failed(.other("dns -65563")))
        await settle()
        XCTAssertEqual(probe.access, .unknown)
        XCTAssertTrue(probe.history.contains("failed dns -65563"), "\(probe.history)")
        for _ in 0..<10 {
            probe.start()
            probe.stop()
        }
        XCTAssertLessThanOrEqual(probe.history.count, LocalNetworkAccessProbe.historyLimit)
        probe.start()
        browser.deliver(.peers([OSCDiscoveredPeer(name: "Someone's iPad")]))
        await settle()
        XCTAssertEqual(probe.access, .granted)
        XCTAssertTrue(probe.history.contains("peers 1"), "\(probe.history)")
        XCTAssertFalse(probe.diagnostic.contains("Someone"), "no peer names")
    }

    func testTheBrowseEndsAfterTheMaximumWithoutAnAnswer() async {
        let browser = FakeBrowser()
        let probe = makeProbe(browser, settle: 5, maximum: 0.1)
        probe.start()
        await settle(0.3)
        XCTAssertFalse(probe.isRunning, "a few seconds at most")
        XCTAssertEqual(probe.access, .unknown)
        XCTAssertEqual(browser.cancels.withLock { $0 }, 1)
    }

    // MARK: Follow-up 3: unconfirmed grants are rechecked (D1, iOS 27.0.1)

    /// A fresh fake browser per run.
    private final class BrowserFactory: Sendable {
        let made = Mutex<[FakeBrowser]>([])
        func make() -> FakeBrowser {
            let browser = FakeBrowser()
            made.withLock { $0.append(browser) }
            return browser
        }
        var count: Int { made.withLock { $0.count } }
        var last: FakeBrowser? { made.withLock { $0.last } }
    }

    private func makeRecheckingProbe(_ factory: BrowserFactory, confirm: Double, recheck: Double = 0.05) -> LocalNetworkAccessProbe {
        LocalNetworkAccessProbe(settleSeconds: 0.05, maximumSeconds: 0.5, confirmSeconds: confirm, recheckSeconds: recheck) {
            factory.make()
        }
    }

    /// D1 (iOS 27.0.1, QA-011 2026-11-24): iOS's prompt left the app active, the first browse settled with the prompt
    /// still up ("start 1, browsing, stop, settled → granted") and Don't Allow was never seen. The settle's grant is
    /// unconfirmed; the fresh browse that follows reports the denial, which is final.
    func testAnUnconfirmedGrantIsRecheckedAndADenialAfterThePromptDecides() async {
        let factory = BrowserFactory()
        let probe = makeRecheckingProbe(factory, confirm: 30)
        probe.start()
        factory.last?.deliver(.browsing)   // iOS's prompt is up; the app stays active
        await settle(0.15)
        XCTAssertEqual(probe.access, .granted, "published, so no notice while undecided")
        XCTAssertFalse(probe.isFinal, "a settle inside the window is unconfirmed")
        XCTAssertTrue(probe.history.contains("settled → granted (unconfirmed)"), "\(probe.history)")
        await settle(0.15)
        XCTAssertEqual(probe.runs, 2, "a fresh browse follows")
        XCTAssertTrue(probe.isRunning)
        factory.last?.deliver(.failed(.localNetworkDenied))   // Don't Allow was tapped meanwhile
        await settle()
        XCTAssertEqual(probe.access, .denied)
        XCTAssertTrue(probe.isFinal)
        await settle(0.2)
        XCTAssertEqual(probe.runs, 2, "no browse after a final answer")
        for entry in ["recheck", "start 2", "failed policyDenied", "event → denied"] {
            XCTAssertTrue(probe.history.contains(entry), "\(entry) in \(probe.history)")
        }
    }

    /// Allowed (or asked before): the rechecks keep settling and the grant becomes final once the window has
    /// passed; the browses then stop.
    func testRechecksEndWithAFinalGrantAfterTheWindow() async {
        let factory = BrowserFactory()
        let probe = makeRecheckingProbe(factory, confirm: 0.3)
        probe.start()
        for _ in 0..<40 where !probe.isFinal {
            if probe.isRunning { factory.last?.deliver(.browsing) }
            await settle(0.05)
        }
        XCTAssertTrue(probe.isFinal)
        XCTAssertEqual(probe.access, .granted)
        XCTAssertGreaterThanOrEqual(probe.runs, 2, "rechecked inside the window")
        let runs = probe.runs
        await settle(0.25)
        XCTAssertEqual(probe.runs, runs, "no browse after the final grant")
        XCTAssertFalse(probe.isRunning)
    }

    /// The rechecks follow the receiver: stopping cancels the pending one, the next start browses again while the
    /// answer is not final, and a found service is final at once.
    func testStoppingCancelsThePendingRecheckAndAFoundServiceIsFinal() async {
        let factory = BrowserFactory()
        let probe = makeRecheckingProbe(factory, confirm: 30, recheck: 0.5)
        probe.start()
        factory.last?.deliver(.browsing)
        await settle(0.12)
        XCTAssertEqual(probe.access, .granted)
        probe.stop()   // OSC off, or the app left the foreground
        await settle(0.6)
        XCTAssertEqual(probe.runs, 1, "no recheck while stopped")
        probe.start()
        XCTAssertEqual(probe.runs, 2, "not final: the next start browses again")
        factory.last?.deliver(.peers([OSCDiscoveredPeer(name: "projectM 1A2B")]))
        await settle()
        XCTAssertTrue(probe.isFinal)
        XCTAssertEqual(probe.access, .granted)
    }

    // MARK: Through the OSC receiver coordinator

    private final class ReadyTransport: OSCDatagramTransport, Sendable {
        private let events = Mutex<(@Sendable (OSCTransportEvent) -> Void)?>(nil)
        func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
            self.events.withLock { $0 = events }
            events(.ready(port: port))
        }
        func stop() { events.withLock { $0 }?(.cancelled) }
    }

    func testTheReceiverRunsTheBrowseOnEnableAndShowsTheDeniedNoticeOnlyWhileOn() async throws {
        let suite = "LocalNetworkAccessProbeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let browser = FakeBrowser()
        let osc = OSCReceiverCoordinator(settings: settings, receiver: OSCReceiver(makeTransport: { ReadyTransport() }),
                                         localNetworkProbe: makeProbe(browser))
        var decided = 0
        osc.onLocalNetworkDecided = { decided += 1 }
        XCTAssertEqual(browser.starts.withLock { $0 }, 0, "no browse while OSC is off")

        osc.setEnabled(true)
        XCTAssertEqual(browser.starts.withLock { $0 }, 1, "the first enable browses")
        await settle()
        XCTAssertNil(osc.permissionNotice, "listening alone shows no notice")
        XCTAssertEqual(PermissionStatusSource.localNetwork(state: osc.state, access: osc.localNetworkAccess), .notDetermined)
        XCTAssertEqual(decided, 0, "listening alone decides nothing")

        browser.deliver(.failed(.localNetworkDenied))
        await settle()
        XCTAssertEqual(osc.localNetworkAccess, .denied)
        XCTAssertEqual(osc.permissionNotice?.text, PermissionCatalog.localNetworkDenied)
        XCTAssertGreaterThan(decided, 0)

        osc.setEnabled(false)
        XCTAssertNil(osc.permissionNotice, "off clears the notice")
        osc.setEnabled(true)
        XCTAssertEqual(browser.starts.withLock { $0 }, 1, "no second browse this launch")
        XCTAssertEqual(PermissionStatusSource.localNetwork(state: osc.state, access: osc.localNetworkAccess), .denied,
                       "no explainer after a denial")
        XCTAssertNotNil(osc.permissionNotice)

        osc.sceneBecame(active: false)
        XCTAssertEqual(osc.localNetworkProbe?.isRunning, false, "no browse outside the foreground")
    }
}
