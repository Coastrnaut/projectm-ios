// NetworkDatagramTransport.swift — the OSC receiver's UDP listener (OSC-001-R2 to R5, R14;
// contract C4; research OSC-001-D1, D2).
//
// FR-068 (amended 2026-11-12, owner ruling in ADR-0008): this folder, `OSCTransport/`, is the only
// place the Network framework may be used; scripts/check_compliance.py enforces it. No other
// networking API is used here or anywhere.
//
// * Listens only: never connects out, never resolves a host, no Bonjour (OSC-011 adds discovery).
// * Local network only: cellular prohibited, and each peer's address must pass
//   `OSCPeerAddress.isLocal` before anything is read from it. `NWParameters.acceptLocalOnly` is NOT
//   set: with it the iOS 27.2 simulator never delivered a loopback datagram (the macOS host did), and
//   its exact rule is not documented, so the app enforces its own tested rule instead (research
//   OSC-001-D2).
// * At most 8 peers (`OSCPeerTable`); the least recently admitted one is cancelled for a ninth.
// * All state is confined to one private serial queue; events are reported on it.
// * `stop()` cancels the listener and every peer, then reports `.cancelled` once the listener is
//   cancelled, so the port is free for the next listener.
#if canImport(Network)
import Dispatch
import Foundation
import Network

public final class NetworkDatagramTransport: OSCDatagramTransport, @unchecked Sendable {
    /// Peers kept at once (OSC-001-R5).
    public static let maximumPeers = 8

    // Everything below is touched only on `queue` (hence @unchecked Sendable).
    private let queue = DispatchQueue(label: "org.projectmios.osc.receiver")
    private var listener: NWListener?
    private var requestedPort: UInt16 = 0
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var peers = OSCPeerTable<ObjectIdentifier>(capacity: NetworkDatagramTransport.maximumPeers)
    private var events: (@Sendable (OSCTransportEvent) -> Void)?
    private var stopRequested = false
    private var cancelReported = false

    public init() {}

    public func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
        queue.async { self.open(port: port, events: events) }
    }

    public func stop() {
        queue.async { self.close() }
    }

    // MARK: Listener

    private func open(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
        self.events = events
        requestedPort = port
        guard !stopRequested, listener == nil else { return }
        let parameters = NWParameters.udp
        parameters.prohibitedInterfaceTypes = [.cellular]
        let endpointPort = NWEndpoint.Port(rawValue: port) ?? .any
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port == 0 ? .any : endpointPort)
        } catch {
            events(.failed(Self.failure(error)))
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { state in self.listenerChanged(state) }
        listener.newConnectionHandler = { connection in self.accept(connection) }
        listener.start(queue: queue)
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard !stopRequested else { return }
            events?(.ready(port: listener?.port?.rawValue ?? requestedPort))
        case .waiting(let error), .failed(let error):
            // Waiting means the system cannot open the port now (for example Local Network is off);
            // the receiver treats it as a failure and stops this transport (no automatic retry).
            guard !stopRequested else { return }
            events?(.failed(Self.failure(error)))
        case .cancelled:
            reportCancelled()
        case .setup:
            break
        @unknown default:
            break
        }
    }

    private func close() {
        guard !stopRequested else { return }
        stopRequested = true
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        peers.removeAll()
        guard let listener else {
            reportCancelled()           // never opened
            return
        }
        listener.newConnectionHandler = nil
        switch listener.state {
        case .cancelled:
            reportCancelled()
        default:
            listener.cancel()           // `.cancelled` arrives through the state handler
        }
    }

    private func reportCancelled() {
        guard stopRequested, !cancelReported else { return }
        cancelReported = true
        listener?.stateUpdateHandler = nil
        listener = nil
        let events = self.events
        self.events = nil
        events?(.cancelled)
    }

    // MARK: Peers

    private func accept(_ connection: NWConnection) {
        guard !stopRequested, let address = Self.peerAddress(connection.endpoint), address.isLocal else {
            connection.cancel()
            if !stopRequested { events?(.droppedNonLocal) }
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        if let evicted = peers.admit(id) {
            connections.removeValue(forKey: evicted)?.cancel()
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: self.forget(id)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, id: id)
    }

    private func forget(_ id: ObjectIdentifier) {
        connections.removeValue(forKey: id)?.cancel()
        peers.remove(id)
    }

    private func receive(on connection: NWConnection, id: ObjectIdentifier) {
        connection.receiveMessage { data, _, _, error in
            guard !self.stopRequested, self.connections[id] != nil else { return }
            if let data {
                if data.count > OSCLimits.maximumDatagramBytes {
                    self.events?(.oversized(data.count))
                } else {
                    self.events?(.datagram([UInt8](data)))
                }
            }
            if error == nil {
                self.receive(on: connection, id: id)
            } else {
                self.forget(id)
            }
        }
    }

    // MARK: Mapping

    static func peerAddress(_ endpoint: NWEndpoint) -> OSCPeerAddress? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        switch host {
        case .ipv4(let address):
            let b = [UInt8](address.rawValue)
            return b.count == 4 ? .ipv4(b[0], b[1], b[2], b[3]) : nil
        case .ipv6(let address):
            return .ipv6([UInt8](address.rawValue))
        case .name:
            return nil
        @unknown default:
            return nil
        }
    }

    /// DNS-SD's kDNSServiceErr_PolicyDenied: the user turned Local Network access off.
    static let policyDenied: Int32 = -65570

    static func failure(_ error: any Error) -> OSCListenerFailure {
        guard let error = error as? NWError else { return .other("error") }
        switch error {
        case .posix(let code):
            if code == .EADDRINUSE { return .portInUse }
            return .other("posix \(code.rawValue)")
        case .dns(let code):
            return Int32(code) == policyDenied ? .localNetworkDenied : .other("dns \(code)")
        default:
            return .other("network")
        }
    }
}

#endif
