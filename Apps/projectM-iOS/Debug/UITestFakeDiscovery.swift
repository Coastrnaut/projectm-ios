// UITestFakeDiscovery.swift — a stand-in local peer browser for UI tests (OSC-011-T13; DEBUG only).
//
// `-uitestFakeDiscovery` makes `OSCDiscoveryCoordinator.systemBrowser()` return this browser: on start it reports
// two fixed local devices (one resolved, one IPv6 link-local), so the Nearby Devices list can be tested without a
// network. Nothing here touches the Network framework.
#if DEBUG
import Foundation
import PerformanceControl
import Synchronization

enum UITestFakeDiscovery {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-uitestFakeDiscovery") }

    static let peers: [OSCDiscoveredPeer] = [
        OSCDiscoveredPeer(name: "Lighting Desk", address: .ipv4(192, 168, 1, 40), port: 9001),
        OSCDiscoveredPeer(name: "projectM 7C21", address: .ipv4(192, 168, 1, 23), port: 9000),
    ]

    /// Reports `.browsing` and the fixed peers on start; nothing after `cancel()`.
    final class Browser: OSCPeerBrowsing, Sendable {
        private let cancelled = Mutex(false)

        func start(events: @escaping @Sendable (OSCBrowserEvent) -> Void) {
            guard !cancelled.withLock({ $0 }) else { return }
            events(.browsing)
            events(.peers(UITestFakeDiscovery.peers))
        }

        func cancel() { cancelled.withLock { $0 = true } }
    }
}
#endif
