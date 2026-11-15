// NetworkOSCPeerBrowser.swift — the reviewed local peer browser (OSC-011-R1, R2, R8; contracts/osc-discovery.md D2;
// research OSC-011-D1, D3, D4; ADR-0100).
//
// FR-068 (amended 2026-11-12, owner ruling in ADR-0008): this folder, `OSCTransport/`, is the only place the Network
// framework may be used. ADR-0100 admits this browser; scripts/check_network_symbols.py accepts `NWBrowser` and the
// resolution APIs only in the image that defines it, and scripts/check_compliance.py keeps `NWBrowser` in this file.
//
// * Browses Bonjour (multicast DNS on the local link) for exactly one type, `OSCDiscovery.serviceType`, in
//   `OSCDiscovery.domain`: no server, no relay, no host name, no other endpoint. Peer-to-peer Wi-Fi and cellular off.
// * Each found service is resolved to an address by a UDP flow to the service itself, IPv4 only, that is started,
//   read once for its remote address when ready, and cancelled: it sends nothing. A service whose address is not
//   local (`OSCPeerAddress.isLocal`) is dropped; one not resolved within 5 s stays unresolved (no retry).
// * At most `OSCDiscovery.maximumPeers` services are tracked.
// * All state lives on one private serial queue. `cancel()` sets a flag synchronously, so no event is reported
//   after it returns, then cancels the browser and every resolution on the queue.
#if canImport(Network)
import Dispatch
import Foundation
import Network
import Synchronization

public final class NetworkOSCPeerBrowser: OSCPeerBrowsing, @unchecked Sendable {
    /// How long one resolution may take before it is given up.
    public static let resolveTimeoutSeconds = 5

    private struct Entry {
        let endpoint: NWEndpoint
        var connection: NWConnection?
        var address: OSCPeerAddress?
        var port: UInt16?
        /// Resolved to an address that is not local: never shown.
        var dropped = false
    }

    // `cancelled` is read on any thread; everything else is touched only on `queue` (hence @unchecked Sendable).
    private let cancelled = Mutex<Bool>(false)
    private let queue = DispatchQueue(label: "org.projectmios.osc.discovery")
    private var browser: NWBrowser?
    private var events: (@Sendable (OSCBrowserEvent) -> Void)?
    private var entries: [String: Entry] = [:]

    public init() {}

    public func start(events: @escaping @Sendable (OSCBrowserEvent) -> Void) {
        queue.async { self.open(events) }
    }

    public func cancel() {
        cancelled.withLock { $0 = true }
        queue.async { self.close() }
    }

    private var isCancelled: Bool { cancelled.withLock { $0 } }

    private func emit(_ event: OSCBrowserEvent) {
        guard !isCancelled else { return }
        events?(event)
    }

    // MARK: Browser

    private func open(_ events: @escaping @Sendable (OSCBrowserEvent) -> Void) {
        guard !isCancelled, browser == nil else { return }
        self.events = events
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        parameters.prohibitedInterfaceTypes = [.cellular]
        let descriptor: NWBrowser.Descriptor = .bonjour(type: OSCDiscovery.serviceType, domain: OSCDiscovery.domain)
        let browser = NWBrowser(for: descriptor, using: parameters)
        self.browser = browser
        browser.stateUpdateHandler = { (state: NWBrowser.State) -> Void in self.browserChanged(state) }
        browser.browseResultsChangedHandler = { (results: Set<NWBrowser.Result>, _: Set<NWBrowser.Result.Change>) -> Void in
            self.update(results)
        }
        browser.start(queue: queue)
    }

    private func browserChanged(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            emit(.browsing)
        case .waiting(let error), .failed(let error):
            // No automatic retry (as OSC-001-R3): report once and stop.
            emit(.failed(NetworkDatagramTransport.failure(error)))
            events = nil
            stopAll()
        default:
            break
        }
    }

    private func close() {
        events = nil
        stopAll()
    }

    private func stopAll() {
        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
        for entry in entries.values { Self.end(entry.connection) }
        entries.removeAll()
    }

    /// Cancels a resolution flow and drops its handler (the handler holds the flow).
    private static func end(_ connection: NWConnection?) {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
    }

    // MARK: Results

    private func update(_ results: Set<NWBrowser.Result>) {
        guard !isCancelled else { return }
        var current: [String: NWEndpoint] = [:]
        for result in results {
            if case let .service(name, type, _, _) = result.endpoint, type == OSCDiscovery.serviceType {
                current[name] = result.endpoint
            }
        }
        for (name, entry) in entries where current[name] == nil {   // gone
            Self.end(entry.connection)
            entries[name] = nil
        }
        for name in current.keys.sorted() where entries[name] == nil {
            guard entries.count < OSCDiscovery.maximumPeers, let endpoint = current[name] else { break }
            entries[name] = Entry(endpoint: endpoint)
            resolve(name, endpoint)
        }
        report()
    }

    private func report() {
        let peers: [OSCDiscoveredPeer] = entries.compactMap { (name: String, entry: Entry) -> OSCDiscoveredPeer? in
            entry.dropped ? nil : OSCDiscoveredPeer(name: name, address: entry.address, port: entry.port)
        }
        emit(.peers(peers))
    }

    // MARK: Resolution (research OSC-011-D3)

    private func resolve(_ name: String, _ endpoint: NWEndpoint) {
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = false
        parameters.prohibitedInterfaceTypes = [.cellular]
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4   // an address OSC-005 can send to
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        entries[name]?.connection = connection
        let id = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { (state: NWConnection.State) -> Void in
            switch state {
            case .ready: self.resolved(name, connection)
            case .failed: self.giveUp(name, id)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + .seconds(Self.resolveTimeoutSeconds)) { self.giveUp(name, id) }
    }

    private func resolved(_ name: String, _ connection: NWConnection) {
        guard var entry = entries[name], entry.connection === connection else { return }
        let remote: NWEndpoint? = connection.currentPath?.remoteEndpoint
        connection.stateUpdateHandler = nil
        connection.cancel()
        entry.connection = nil
        if let remote, case let .hostPort(_, port) = remote, let address = NetworkDatagramTransport.peerAddress(remote) {
            if address.isLocal {
                entry.address = address
                entry.port = port.rawValue
            } else {
                entry.dropped = true   // R8: never shown, never offered
            }
        }
        entries[name] = entry
        report()
    }

    /// Ends an unfinished resolution (failure or timeout); the service stays listed without an address.
    private func giveUp(_ name: String, _ id: ObjectIdentifier) {
        guard var entry = entries[name], let connection = entry.connection, ObjectIdentifier(connection) == id else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        entry.connection = nil
        entries[name] = entry
    }
}
#endif
