// OSCSend.swift — what the optional OSC sender sends and where (OSC-005; specs/277-osc-005-osc-send,
// contracts/osc-send.md S1, S2; research OSC-005-D2, D3, D5, D6).
//
// * Destination (OSC-005-R3): a literal IPv4/IPv6 address on the local network only: OSC-001's `isLocal` rule minus
//   IPv6 link-local (the field takes no interface zone), unspecified, multicast and limited broadcast. Host names are
//   refused: resolving one is a DNS lookup, which FR-068 forbids. Port 1024-65535 (OSC-001's rule).
// * Messages (OSC-005-R6, R7): `/projectm/scene` (the scene name only when the user chose to include names, cut to
//   64 UTF-8 bytes), `/projectm/beat ,i n`, `/projectm/status ,s started|stopped`. Nothing else leaves the device.
// * `OSCSendRateCap` (OSC-005-R9): at most 60 messages in any 1 s window; excess is dropped, never queued.
// * `OSCBeatGate` (OSC-005-R8): at most one message per beat of the tempo grid and at least 250 ms apart.
// Pure Swift (no Foundation), every time an argument, so it is tested on every host.

/// Where the sender sends: a validated local address and port.
public struct OSCSendDestination: Sendable, Hashable {
    public let host: OSCPeerAddress
    public let port: UInt16

    /// Only values that passed `isSendable` and `OSCPort.isValid`; use `parse` for user text.
    public init?(host: OSCPeerAddress, port: UInt16) {
        guard Self.isSendable(host), OSCPort.isValid(Int(port)) else { return nil }
        self.host = host.normalized
        self.port = port
    }

    /// "192.168.1.40:9001" or "[fd00::1]:9001".
    public var text: String {
        if case .ipv6 = host { return "[\(host.text)]:\(port)" }
        return "\(host.text):\(port)"
    }

    /// OSC-005-R3: local (OSC-001-R4) and not IPv6 link-local, unspecified, multicast or limited broadcast.
    public static func isSendable(_ address: OSCPeerAddress) -> Bool {
        let host: OSCPeerAddress = address.normalized
        guard host.isLocal else { return false }
        switch host {
        case let .ipv4(a, b, c, d):
            if a == 0 || a >= 224 { return false }                       // 0/8, multicast, reserved
            return !(a == 255 && b == 255 && c == 255 && d == 255)
        case let .ipv6(bytes):
            if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 { return false }   // fe80::/10 needs a zone
            if bytes[0] == 0xFF { return false }                               // multicast
            return !bytes.allSatisfy { (b: UInt8) -> Bool in b == 0 }         // ::
        }
    }

    /// The user's typed address and port; whitespace around either is ignored.
    public static func parse(host: String, port: String) -> Result<OSCSendDestination, OSCSendDestinationError> {
        let trimmed: String = String(host.filter { (c: Character) -> Bool in c != " " && c != "\t" && c != "\n" })
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let address = OSCPeerAddress(text: trimmed) else { return .failure(.notAnAddress) }
        let local: OSCPeerAddress = address.normalized
        if case let .ipv6(bytes) = local, bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return .failure(.linkLocalIPv6) }
        guard isSendable(local) else { return .failure(.notLocal) }
        guard let number = OSCPort.parse(port) else { return .failure(.port) }
        guard let destination = OSCSendDestination(host: local, port: number) else { return .failure(.notLocal) }
        return .success(destination)
    }
}

/// Why a typed destination was refused (OSC-005-R3); `message` is shown under the field.
public enum OSCSendDestinationError: Error, Sendable, Hashable {
    case empty
    /// A host name or anything that is not a literal IPv4/IPv6 address.
    case notAnAddress
    /// Public, carrier-grade NAT, multicast, broadcast or unspecified.
    case notLocal
    case linkLocalIPv6
    case port

    public var message: String {
        switch self {
        case .empty: "Enter the receiver's address, for example 192.168.1.40."
        case .notAnAddress: "Enter a numeric address such as 192.168.1.40. Names are not looked up."
        case .notLocal: "Use an address on your local network, such as 192.168.x.x or 10.x.x.x."
        case .linkLocalIPv6: "IPv6 link-local addresses (fe80::) are not supported. Use the receiver's IPv4 address."
        case .port: "Use a port from 1024 to 65535."
        }
    }
}

/// The message kinds the user can choose (OSC-005-R6).
public enum OSCSendKind: String, Sendable, Hashable, CaseIterable {
    case scene, beat, status

    /// Scene changes and status on, beats off (beats are the busiest kind).
    public static let defaults: Set<OSCSendKind> = [.scene, .status]
}

public enum OSCSendStatus: String, Sendable, Hashable {
    case started, stopped
}

/// One outbound event (memory only).
public enum OSCSendEvent: Sendable, Hashable {
    case scene(name: String?)
    case beat(Int32)
    case status(OSCSendStatus)

    public var kind: OSCSendKind {
        switch self {
        case .scene: .scene
        case .beat: .beat
        case .status: .status
        }
    }
}

/// The documented outbound namespace (contract S1).
public enum OSCSendMessages {
    public static let sceneAddress = "/projectm/scene"
    public static let beatAddress = "/projectm/beat"
    public static let statusAddress = "/projectm/status"
    /// OSC-005-R7: a scene name is cut to this many UTF-8 bytes.
    public static let maximumNameBytes = 64

    public static func message(for event: OSCSendEvent, includeSceneNames: Bool) -> OSCMessage {
        switch event {
        case .scene(let name):
            guard includeSceneNames, let name, let cut = truncated(name), !cut.isEmpty else {
                return OSCMessage(address: sceneAddress, arguments: [])
            }
            return OSCMessage(address: sceneAddress, arguments: [.string(cut)])
        case .beat(let n):
            return OSCMessage(address: beatAddress, arguments: [.int(n)])
        case .status(let status):
            return OSCMessage(address: statusAddress, arguments: [.string(status.rawValue)])
        }
    }

    /// The name without NULs, cut to `maximumNameBytes` UTF-8 bytes at a character boundary.
    public static func truncated(_ name: String) -> String? {
        var out: String = ""
        var bytes: Int = 0
        for character in name where character != "\u{0}" {
            let size: Int = String(character).utf8.count
            if bytes + size > maximumNameBytes { break }
            out.append(character)
            bytes += size
        }
        return out
    }
}

/// OSC-005-R9: an exact sliding window: admit while fewer than `limit` sends happened in the last `window` ns.
public struct OSCSendRateCap: Sendable {
    public static let defaultLimit = 60
    public static let defaultWindow: UInt64 = 1_000_000_000

    public let limit: Int
    public let window: UInt64
    private var times: [UInt64] = []
    private var next = 0

    public init(limit: Int = OSCSendRateCap.defaultLimit, window: UInt64 = OSCSendRateCap.defaultWindow) {
        self.limit = max(limit, 1)
        self.window = window
    }

    public mutating func admit(now: UInt64) -> Bool {
        if times.count < limit {
            times.append(now)
            return true
        }
        let oldest: UInt64 = times[next]            // the ring's oldest send
        guard now >= oldest, now - oldest >= window else { return false }
        times[next] = now
        next = (next + 1) % limit
        return true
    }

    public mutating func reset() {
        times.removeAll()
        next = 0
    }
}

/// OSC-005-R8: turns the tempo grid into at most one beat message per beat, at least `minimumSpacing` apart.
public struct OSCBeatGate: Sendable {
    /// 4 beats a second at most.
    public static let minimumSpacing: UInt64 = 250_000_000

    private var lastIndex: Int64?
    private var lastSent: UInt64?
    /// The number of the last beat sent (the next is 1 after a reset).
    public private(set) var count: Int32 = 0

    public init() {}

    /// The beat number to send now, or nil. The first observation of a grid only records the current beat.
    public mutating func beat(anchor: UInt64?, period: UInt64?, now: UInt64) -> Int32? {
        guard let anchor, let period, period > 0 else {
            lastIndex = nil
            return nil
        }
        let index: Int64 = now >= anchor ? Int64((now - anchor) / period) : -Int64((anchor - now + period - 1) / period)
        guard let previous = lastIndex else {
            lastIndex = index
            return nil
        }
        guard index != previous else { return nil }
        lastIndex = index
        if let lastSent, now >= lastSent, now - lastSent < Self.minimumSpacing { return nil }
        lastSent = now
        count = count == Int32.max ? 1 : count + 1
        return count
    }

    public mutating func reset() {
        lastIndex = nil
        lastSent = nil
        count = 0
    }
}
