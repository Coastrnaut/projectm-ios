// OSCDiscovery.swift — local peer discovery rules (OSC-011-R1, R4 to R9; specs/289-osc-011-local-peer-discovery,
// contracts/osc-discovery.md D1; ADR-0100).
//
// Pure, so every rule is tested on every host (Linux too). The one real browser (`NetworkOSCPeerBrowser`) and the
// announcing listener live in `OSCTransport/`, the only folder FR-068 (amended, ADR-0008) allows the Network
// framework.
//
// * One Bonjour service type on the local link, `_projectm-osc._udp` in `local.`; no other mechanism, no relay.
// * Browsing and announcing exist only while their own switch, the OSC receiver switch (OSC-007) and the foreground
//   all hold (`activity`); both switches are off by default.
// * The announced name is "projectM " plus 4 random hexadecimal digits per launch: never the device name.
// * Found devices: names cleaned, non-local addresses dropped, own announcement left out, at most 16, by name.

/// Constants and pure rules of OSC-011 discovery.
public enum OSCDiscovery {
    /// The one service type the app browses for and announces (also the only `NSBonjourServices` entry).
    public static let serviceType = "_projectm-osc._udp"
    /// Multicast DNS on the local link only.
    public static let domain = "local."
    /// Found devices kept at once (R8).
    public static let maximumPeers = 16
    /// Longest name shown (a DNS-SD instance label is at most 63 bytes).
    public static let maximumNameLength = 63
    /// The prefix of every name this app announces.
    public static let namePrefix = "projectM"
    /// Shown for a name that is empty after cleaning.
    public static let unnamed = "Unnamed device"

    /// "projectM 0A1F": the prefix and `suffix` as 4 uppercase hexadecimal digits (R7).
    public static func announcedName(suffix: UInt16) -> String {
        let hex: String = String(suffix, radix: 16, uppercase: true)
        let padded: String = String(repeating: "0", count: max(0, 4 - hex.count)) + hex
        return namePrefix + " " + padded
    }

    /// A fresh announced name from the system random generator (one per launch, memory only).
    public static func randomAnnouncedName() -> String {
        var generator = SystemRandomNumberGenerator()
        return announcedName(suffix: UInt16.random(in: UInt16.min...UInt16.max, using: &generator))
    }

    /// Removes control characters, trims spaces and cuts to `maximumNameLength` characters (R8).
    public static func cleanName(_ raw: String) -> String {
        let kept: String.UnicodeScalarView = String.UnicodeScalarView(raw.unicodeScalars.filter { (scalar: Unicode.Scalar) -> Bool in
            !(scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format
              || scalar.properties.generalCategory == .lineSeparator || scalar.properties.generalCategory == .paragraphSeparator)
        })
        let trimmed: Substring = Substring(String(kept)).drop(while: { $0 == " " })
        var text: String = String(trimmed)
        while text.last == " " { text.removeLast() }
        if text.count > maximumNameLength { text = String(text.prefix(maximumNameLength)) }
        return text.isEmpty ? unnamed : text
    }

    /// What may run now (R5): each activity needs its switch, the OSC receiver switch and the foreground.
    public struct Activity: Sendable, Hashable {
        public let browse: Bool
        public let advertise: Bool
        public static let none = Activity(browse: false, advertise: false)
        public init(browse: Bool, advertise: Bool) {
            self.browse = browse
            self.advertise = advertise
        }
    }

    public static func activity(browse: Bool, advertise: Bool, oscEnabled: Bool, appActive: Bool) -> Activity {
        let allowed: Bool = oscEnabled && appActive
        return Activity(browse: browse && allowed, advertise: advertise && allowed)
    }

    /// The list to show (R8): cleaned names, non-local addresses dropped, `ownName` left out, sorted, at most 16.
    public static func peers(_ raw: [OSCDiscoveredPeer], excluding ownName: String?) -> [OSCDiscoveredPeer] {
        var seen: Set<String> = []
        var result: [OSCDiscoveredPeer] = []
        for peer in raw {
            if let address = peer.address, !address.isLocal { continue }
            let name: String = cleanName(peer.name)
            if let ownName, name == ownName { continue }
            if seen.contains(name) { continue }
            seen.insert(name)
            result.append(OSCDiscoveredPeer(name: name, address: peer.address, port: peer.port))
        }
        result.sort { (a: OSCDiscoveredPeer, b: OSCDiscoveredPeer) -> Bool in
            (a.name.lowercased(), a.name) < (b.name.lowercased(), b.name)
        }
        return Array(result.prefix(maximumPeers))
    }
}

/// One device found on the local network (memory only). `address` and `port` are nil until resolved.
public struct OSCDiscoveredPeer: Sendable, Hashable, Identifiable {
    public let name: String
    public let address: OSCPeerAddress?
    public let port: UInt16?

    public init(name: String, address: OSCPeerAddress? = nil, port: UInt16? = nil) {
        self.name = name
        self.address = address
        self.port = port
    }

    public var id: String { name }

    public var isResolved: Bool { address != nil && port != nil }

    /// The OSC-005 destination this device offers, when OSC-005 accepts its address and port (R9).
    public var destination: OSCSendDestination? {
        guard let address, let port else { return nil }
        return OSCSendDestination(host: address, port: port)
    }

    /// "192.168.1.23:9000", or nil while unresolved.
    public var addressText: String? {
        guard let address, let port else { return nil }
        let host: OSCPeerAddress = address.normalized
        switch host {
        case .ipv4: return host.text + ":" + String(port)
        case .ipv6: return "[" + host.text + "]:" + String(port)
        }
    }
}

/// What a browser reports, on its own queue.
public enum OSCBrowserEvent: Sendable, Hashable {
    /// The browser is running (possibly with nothing found yet).
    case browsing
    /// The full current list (raw: the coordinator filters it with `OSCDiscovery.peers`).
    case peers([OSCDiscoveredPeer])
    /// The browser stopped; no automatic retry (as OSC-001-R3).
    case failed(OSCListenerFailure)
}

/// A local-network browser for `OSCDiscovery.serviceType` (fakes in tests, `NetworkOSCPeerBrowser` in the app).
public protocol OSCPeerBrowsing: AnyObject, Sendable {
    /// Starts browsing and reports events on the browser's own queue.
    func start(events: @escaping @Sendable (OSCBrowserEvent) -> Void)
    /// Stops browsing and every resolution; no event is reported afterwards.
    func cancel()
}
