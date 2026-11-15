// UITestFakeOSC.swift — a stand-in OSC source for OSC learn (OSC-004-T07; research OSC-004-D7). DEBUG builds only,
// and only with `-uitestFakeOSC`; Release builds contain none of this. No Network framework: the transport reports
// ready on start and its `send` hands encoded datagrams from a fixed local peer (192.168.1.20) to the receiver,
// so the allow list, the rate limiter, the decoder, routes and learn are the app's real code.
#if DEBUG
import Foundation
import ParameterGraph
import PerformanceControl
import Synchronization
import SwiftUI

enum UITestFakeOSC {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-uitestFakeOSC") }

    static let peer = OSCPeerAddress.ipv4(192, 168, 1, 20)
    /// The address the panel's Send button uses.
    static let address = "/fader/7"

    /// The transport the fake receiver uses (the latest one started).
    static let current = Mutex<Transport?>(nil)

    /// A receiver over the stand-in transport when the launch arguments ask for it.
    @MainActor static func receiverIfRequested(store: ParameterStore, routable: [ParameterDescriptor], defaults: UserDefaults) -> OSCReceiver? {
        guard isRequested else { return nil }
        return makeReceiver(store: store, routes: OSCRoutesCoordinator.initialRoutes(routable: routable, defaults: defaults))
    }

    static func makeReceiver(store: ParameterStore, routes: [OSCRoute]) -> OSCReceiver {
        OSCReceiver(store: store, routes: routes, makeTransport: { () -> (any OSCDatagramTransport)? in
            let transport = Transport()
            current.withLock { $0 = transport }
            return transport
        })
    }

    /// Sends `/fader/7 <value>` (or `address`) from the fixed peer through the current transport.
    static func send(_ address: String = UITestFakeOSC.address, value: Float = 0.5) {
        let bytes: [UInt8] = OSCEncoder.encode(OSCMessage(address: address, arguments: [.float(value)]))
        current.withLock { $0 }?.deliver(.datagram(bytes, source: OSCSourceID(rawValue: 1), peer: peer))
    }

    /// Reports `.ready` on start and `.cancelled` once on stop; `deliver` injects events while started.
    final class Transport: OSCDatagramTransport, Sendable {
        private let events = Mutex<(@Sendable (OSCTransportEvent) -> Void)?>(nil)

        func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
            self.events.withLock { $0 = events }
            events(.ready(port: port))
        }

        func stop() {
            let handler: (@Sendable (OSCTransportEvent) -> Void)? = events.withLock { (value: inout (@Sendable (OSCTransportEvent) -> Void)?) -> (@Sendable (OSCTransportEvent) -> Void)? in
                let current = value
                value = nil
                return current
            }
            handler?(.cancelled)
        }

        func deliver(_ event: OSCTransportEvent) {
            events.withLock { $0 }?(event)
        }
    }
}

/// OSC-004: a button on OSC Routes that sends `/fader/7 0.5` from the stand-in controller.
struct UITestFakeOSCPanel: View {
    var body: some View {
        Button("Send " + UITestFakeOSC.address) { UITestFakeOSC.send() }
            .accessibilityIdentifier("oscFakeSend")
    }
}
#endif
