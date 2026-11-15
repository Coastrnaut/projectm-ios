// NetworkOSCSender.swift — the optional OSC sender's UDP flow (OSC-005-R3 to R5; contracts/osc-send.md S2;
// research OSC-005-D1, D3, D4; ADR-0088).
//
// FR-068 (amended 2026-11-12, owner ruling in ADR-0008): this folder, `OSCTransport/`, is the only place the
// Network framework may be used. ADR-0088 admits this reviewed sender, also in Release builds; the network symbol
// scan (scripts/check_network_symbols.py) accepts outbound `NWConnection` APIs only in the image that defines it.
//
// * One UDP flow to a literal local address (`NWEndpoint.Host.ipv4/.ipv6`): no host name, so never a DNS lookup;
//   the host must pass `OSCSendDestination.isSendable` again here (defence in depth); cellular is prohibited.
// * `close()` bumps a generation synchronously, so every send block queued before it is dropped unrun, then
//   cancels the connection on the queue: nothing is sent after `close()` returns (R5).
// * At most 16 datagrams in flight, so a flow stuck waiting (for example Local Network off) cannot grow memory.
// * No automatic retry: a failure is reported once (OSC-005 clarification, as OSC-001-R3).
#if canImport(Network)
import Dispatch
import Foundation
import Network
import Synchronization

public final class NetworkOSCSender: OSCSendTransport, @unchecked Sendable {
    /// Datagrams handed to the system and not yet processed.
    public static let maximumInFlight = 16

    // `generation` is read on any thread; everything else is touched only on `queue` (hence @unchecked Sendable).
    private let generation = Mutex<UInt64>(0)
    private let queue = DispatchQueue(label: "org.projectmios.osc.sender")
    private var connection: NWConnection?
    /// The generation `connection` was opened under; a send of any other generation is dropped.
    private var connectionGeneration: UInt64 = 0
    private var inFlight = 0
    private var reported = false

    public init() {}

    public func open(host: OSCPeerAddress, port: UInt16, events: @escaping @Sendable (OSCSendTransportEvent) -> Void) {
        let current: UInt64 = generation.withLock { g -> UInt64 in
            g &+= 1
            return g
        }
        queue.async { self.start(host: host, port: port, generation: current, events: events) }
    }

    public func send(_ bytes: [UInt8]) {
        let current: UInt64 = generation.withLock { $0 }
        queue.async {
            guard self.generation.withLock({ $0 }) == current, self.connectionGeneration == current, let connection = self.connection,
                  self.inFlight < Self.maximumInFlight else { return }
            self.inFlight += 1
            connection.send(content: Data(bytes), completion: .contentProcessed { _ in self.inFlight -= 1 })
        }
    }

    public func close() {
        let current: UInt64 = generation.withLock { g -> UInt64 in
            g &+= 1
            return g
        }
        queue.async { self.cancel(ifGeneration: current) }
    }

    private func start(host: OSCPeerAddress, port: UInt16, generation expected: UInt64,
                       events: @escaping @Sendable (OSCSendTransportEvent) -> Void) {
        guard generation.withLock({ $0 }) == expected else { return }
        connection?.cancel()
        connection = nil
        inFlight = 0
        reported = false
        guard OSCSendDestination.isSendable(host), let endpointHost = Self.endpointHost(host),
              let endpointPort = NWEndpoint.Port(rawValue: port), port != 0 else {
            events(.failed(.other("not local")))
            return
        }
        let parameters = NWParameters.udp
        parameters.prohibitedInterfaceTypes = [.cellular]
        let connection = NWConnection(host: endpointHost, port: endpointPort, using: parameters)
        self.connection = connection
        connectionGeneration = expected
        connection.stateUpdateHandler = { (state: NWConnection.State) -> Void in
            guard self.generation.withLock({ $0 }) == expected, !self.reported else { return }
            switch state {
            case .ready:
                events(.ready)
            case .waiting(let error), .failed(let error):
                self.reported = true
                events(.failed(NetworkDatagramTransport.failure(error)))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func cancel(ifGeneration expected: UInt64) {
        guard generation.withLock({ $0 }) == expected else { return }   // a newer open owns the flow
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        inFlight = 0
    }

    static func endpointHost(_ address: OSCPeerAddress) -> NWEndpoint.Host? {
        switch address.normalized {
        case let .ipv4(a, b, c, d):
            return IPv4Address(Data([a, b, c, d])).map { NWEndpoint.Host.ipv4($0) }
        case let .ipv6(bytes):
            guard bytes.count == 16 else { return nil }
            return IPv6Address(Data(bytes)).map { NWEndpoint.Host.ipv6($0) }
        }
    }
}
#endif
