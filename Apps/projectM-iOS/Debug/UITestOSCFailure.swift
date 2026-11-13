// UITestOSCFailure.swift — a stand-in OSC transport that fails on start (FILE-013-R8, plan D8).
// DEBUG builds only; Release builds contain none of this. No Network framework: Local Network
// permission cannot be scripted on the simulator, so `-uitestOSCFailure localNetworkDenied` makes
// every start report the policy denial the real listener reports.
#if DEBUG
import Foundation
import PerformanceControl
import Synchronization

enum UITestOSCFailure {
    /// A receiver whose transport fails with the requested failure, if the launch arguments ask.
    static func receiverIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> OSCReceiver? {
        guard let i = arguments.firstIndex(of: "-uitestOSCFailure"), i + 1 < arguments.count else { return nil }
        let failure: OSCListenerFailure
        switch arguments[i + 1] {
        case "localNetworkDenied": failure = .localNetworkDenied
        case "portInUse": failure = .portInUse
        default: return nil
        }
        return OSCReceiver(makeTransport: { () -> (any OSCDatagramTransport)? in FailingTransport(failure: failure) })
    }

    /// Reports `failure` on start and `.cancelled` once on stop.
    final class FailingTransport: OSCDatagramTransport, Sendable {
        private let failure: OSCListenerFailure
        private let events = Mutex<(@Sendable (OSCTransportEvent) -> Void)?>(nil)

        init(failure: OSCListenerFailure) { self.failure = failure }

        func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
            self.events.withLock { $0 = events }
            events(.failed(failure))
        }

        func stop() {
            let handler: (@Sendable (OSCTransportEvent) -> Void)? = events.withLock { (value: inout (@Sendable (OSCTransportEvent) -> Void)?) -> (@Sendable (OSCTransportEvent) -> Void)? in
                let current = value
                value = nil
                return current
            }
            handler?(.cancelled)
        }
    }
}
#endif
