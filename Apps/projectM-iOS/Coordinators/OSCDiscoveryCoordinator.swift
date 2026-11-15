// OSCDiscoveryCoordinator.swift — Nearby Devices in Settings › OSC (OSC-011-R3 to R10; specs/289-osc-011-local-peer-discovery,
// contracts/osc-discovery.md D3; ADR-0100).
//
// * Two keys, both this device's network setup (excluded from the FILE-005 backup, removed by the FILE-011 Settings
//   erase and by `-uitestResetNotice`): `settings.osc.discovery.browse` ("Find nearby devices") and
//   `settings.osc.discovery.advertise` ("Let nearby devices find this one"); absent → off.
// * Each activity runs only while its switch, the OSC receiver switch (OSC-007) and the foreground hold
//   (`OSCDiscovery.activity`). `OSCReceiverCoordinator.apply()` calls `conditionsChanged()` for the switch and the
//   foreground. With browsing off no browser exists; with announcing off the receiver announces nothing.
// * Announcing goes through the receiver's own listener (`OSCReceiver.setAdvertisement`) under a per-launch generic
//   name ("projectM XXXX", memory only), so it carries the real port and ends with the listener.
// * Found devices are memory only and never trusted by themselves: only the user's "Allow" (OSC-008) or
//   "Use as send destination" (OSC-005) tap changes anything, and neither turns another switch on.
// * Browser events arrive on the browser's queue and are copied onto the main actor; events of a cancelled browser
//   are ignored (generation). A failure is shown and never retried by itself (as OSC-001-R3).
import Foundation
import Observation
import PerformanceControl

@MainActor
@Observable
final class OSCDiscoveryCoordinator {
    static let browseKey = "settings.osc.discovery.browse"
    static let advertiseKey = "settings.osc.discovery.advertise"
    static let allKeys: [String] = [browseKey, advertiseKey]

    enum BrowserState: Equatable {
        case off, looking, failed(OSCListenerFailure)
    }

    private(set) var browseEnabled: Bool
    private(set) var advertiseEnabled: Bool
    private(set) var peers: [OSCDiscoveredPeer] = []
    private(set) var browserState: BrowserState = .off
    /// What the last Allow or Use as send destination did (cleared when the list empties).
    private(set) var actionNote: String?
    /// The name this device announces while announcing (per launch, memory only).
    let advertisedName: String

    @ObservationIgnored private weak var osc: OSCReceiverCoordinator?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeBrowser: @MainActor () -> any OSCPeerBrowsing
    @ObservationIgnored private var browser: (any OSCPeerBrowsing)?
    @ObservationIgnored private var generation: UInt64 = 0
    /// Browsers created since launch (tests: none while off).
    @ObservationIgnored private(set) var browsersCreated = 0

    init(osc: OSCReceiverCoordinator, defaults: UserDefaults,
         advertisedName: String = OSCDiscovery.randomAnnouncedName(),
         makeBrowser: @escaping @MainActor () -> any OSCPeerBrowsing = OSCDiscoveryCoordinator.systemBrowser) {
        self.osc = osc
        self.defaults = defaults
        self.advertisedName = advertisedName
        self.makeBrowser = makeBrowser
        browseEnabled = defaults.bool(forKey: Self.browseKey)
        advertiseEnabled = defaults.bool(forKey: Self.advertiseKey)
        conditionsChanged()
    }

    /// The real browser, or the UI tests' fake (DEBUG, `-uitestFakeDiscovery`).
    static func systemBrowser() -> any OSCPeerBrowsing {
        #if DEBUG
        if UITestFakeDiscovery.isRequested { return UITestFakeDiscovery.Browser() }
        #endif
        return NetworkOSCPeerBrowser()
    }

    // MARK: Settings

    func setBrowse(_ on: Bool) {
        browseEnabled = on
        defaults.set(on, forKey: Self.browseKey)
        conditionsChanged()
    }

    func setAdvertise(_ on: Bool) {
        advertiseEnabled = on
        defaults.set(on, forKey: Self.advertiseKey)
        conditionsChanged()
    }

    /// Both switches need the OSC receiver switch (R5).
    var isOSCEnabled: Bool { osc?.isEnabled ?? false }

    var activity: OSCDiscovery.Activity {
        OSCDiscovery.activity(browse: browseEnabled, advertise: advertiseEnabled,
                              oscEnabled: osc?.isEnabled ?? false, appActive: osc?.appIsActive ?? false)
    }

    // MARK: Conditions (R5, R6)

    func conditionsChanged() {
        let now: OSCDiscovery.Activity = activity
        osc?.setAdvertisement(now.advertise ? advertisedName : nil)
        if now.browse {
            if browser == nil { startBrowser() }
        } else if browser != nil || browserState != .off || !peers.isEmpty {
            stopBrowser()
        }
    }

    private func startBrowser() {
        generation &+= 1
        let current: UInt64 = generation
        let browser: any OSCPeerBrowsing = makeBrowser()
        browsersCreated += 1
        self.browser = browser
        browserState = .looking
        browser.start { [weak self] (event: OSCBrowserEvent) -> Void in
            Task { @MainActor [weak self] in self?.handle(event, generation: current) }
        }
    }

    private func stopBrowser() {
        generation &+= 1
        browser?.cancel()
        browser = nil
        browserState = .off
        peers = []
        actionNote = nil
    }

    private func handle(_ event: OSCBrowserEvent, generation expected: UInt64) {
        guard expected == generation, browser != nil else { return }
        switch event {
        case .browsing:
            browserState = .looking
        case .peers(let raw):
            let shown: [OSCDiscoveredPeer] = OSCDiscovery.peers(raw, excluding: advertisedName)
            if shown != peers { peers = shown }
        case .failed(let failure):
            browser?.cancel()   // kept (cancelled) so nothing restarts it until a condition changes (no retry)
            browserState = .failed(failure)
            peers = []
        }
    }

    // MARK: Actions (R9: only on the user's tap)

    /// Adds the device's address to Approved Devices (OSC-008); never turns "Only approved devices" on.
    func allow(_ peer: OSCDiscoveredPeer) {
        guard let address = peer.address, let peersList = osc?.peers else { return }
        switch peersList.allow(address) {
        case .approved: actionNote = peer.name + " is an approved device."
        case .alreadyApproved: actionNote = peer.name + " is already approved."
        default: actionNote = "Approved Devices is full. Remove one to allow another."
        }
    }

    func isApproved(_ peer: OSCDiscoveredPeer) -> Bool {
        guard let address = peer.address, let peersList = osc?.peers else { return false }
        return peersList.approved.contains(address.normalized)
    }

    var canAllow: Bool { !(osc?.peers?.isFull ?? true) }

    /// Sets Send OSC's destination (OSC-005) to the device's address and port; Send OSC's switch is unchanged.
    func useAsSendDestination(_ peer: OSCDiscoveredPeer) {
        guard let destination = peer.destination, let sender = osc?.sender else { return }
        if sender.submitDestination(host: destination.host.text, port: String(destination.port)) {
            actionNote = "Send OSC will send to " + destination.text + "."
        }
    }

    // MARK: Texts

    var browseSummaryText: String { browseEnabled ? "On" : "Off" }

    var statusText: String {
        guard browseEnabled else { return "Off" }
        guard let osc, osc.isEnabled else { return "Turn on the OSC receiver to find nearby devices." }
        guard osc.appIsActive else { return "Paused while projectM is in the background." }
        switch browserState {
        case .off: return "Off"
        case .failed(.localNetworkDenied): return PermissionCatalog.localNetworkDenied
        case .failed: return "Couldn't look for nearby devices. Turn Find nearby devices off and on to try again."
        case .looking:
            if peers.isEmpty { return "Looking for nearby devices…" }
            return peers.count == 1 ? "1 device found" : String(peers.count) + " devices found"
        }
    }

    var advertiseStatusText: String? {
        guard advertiseEnabled else { return nil }
        guard isOSCEnabled else { return "Turn on the OSC receiver to be found." }
        guard activity.advertise else { return "Paused while projectM is in the background." }
        return "Nearby devices can find this one as “" + advertisedName + "”."
    }
}
