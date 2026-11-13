// OSCLoopbackSender.swift — DEBUG ONLY: sends one datagram to 127.0.0.1 for the loopback
// integration test (OSC-001-T14; research OSC-001-D6).
//
// Test targets may not use the Network framework (scripts/check_compliance.py scans them too), so
// the test's sender lives here, in the one folder FR-068 allows. It is compiled only in debug
// builds, so the shipping (Release) app contains no sending code (OSC-001-R19, S5); the host is
// fixed to loopback, so it cannot reach another device. OSC-005 (send) is a separate, reviewed
// feature.
#if DEBUG && canImport(Network)
import Dispatch
import Foundation
import Network
import Synchronization

enum OSCLoopbackSender {
    /// Sends `bytes` to 127.0.0.1:`port`; `completion(true)` once the system processed the datagram.
    static func send(_ bytes: [UInt8], toLoopbackPort port: UInt16, completion: @escaping @Sendable (Bool) -> Void) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port), port != 0 else {
            completion(false)
            return
        }
        let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .udp)
        let done = Mutex(false)
        let finish: @Sendable (Bool) -> Void = { ok in
            let first = done.withLock { d -> Bool in
                defer { d = true }
                return !d
            }
            guard first else { return }
            completion(ok)
            connection.cancel()
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: Data(bytes), completion: .contentProcessed { error in finish(error == nil) })
            case .failed, .waiting:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(label: "org.projectmios.osc.loopback-sender"))
    }
}
#endif
