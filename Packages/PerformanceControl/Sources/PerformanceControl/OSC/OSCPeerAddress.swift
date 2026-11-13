// OSCPeerAddress.swift — which peers count as the local network (OSC-001-R4, R5; research
// OSC-001-D2) and the bounded peer table.
//
// Pure, so the rule is tested on every host. The transport builds an address from the peer's raw
// bytes and drops any peer that is not local before reading from it. Addresses are never stored,
// logged or shown.

public enum OSCPeerAddress: Sendable, Hashable, CustomStringConvertible {
    case ipv4(UInt8, UInt8, UInt8, UInt8)
    /// 16 bytes; any other length is malformed and never local.
    case ipv6([UInt8])

    /// Loopback, private IPv4 (10/8, 172.16/12, 192.168/16), IPv4 link-local (169.254/16), IPv6
    /// loopback (::1), link-local (fe80::/10) and unique-local (fc00::/7). IPv4-mapped IPv6
    /// (::ffff:a.b.c.d) is judged as IPv4. Carrier-grade NAT (100.64/10) is not local.
    public var isLocal: Bool {
        switch self {
        case let .ipv4(a, b, _, _):
            return a == 127 || a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168)
                || (a == 169 && b == 254)
        case let .ipv6(bytes):
            guard bytes.count == 16 else { return false }
            if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
                return OSCPeerAddress.ipv4(bytes[12], bytes[13], bytes[14], bytes[15]).isLocal
            }
            if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }   // ::1
            if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 { return true }              // fe80::/10
            if bytes[0] & 0xFE == 0xFC { return true }                                   // fc00::/7
            return false
        }
    }

    /// For test failure messages only.
    public var description: String {
        switch self {
        case let .ipv4(a, b, c, d): "\(a).\(b).\(c).\(d)"
        case let .ipv6(bytes): "ipv6(\(bytes.count) bytes)"
        }
    }
}

/// An insertion-ordered set of peers with a fixed capacity (OSC-001-R5): admitting a new peer when
/// full evicts the least recently admitted one, which the caller then cancels.
public struct OSCPeerTable<Key: Hashable> {
    public let capacity: Int
    private var order: [Key] = []

    public init(capacity: Int) { self.capacity = max(capacity, 1) }

    public var count: Int { order.count }
    public var keys: [Key] { order }

    /// Admits `key`; returns the evicted key, if any. A key already present evicts nothing.
    public mutating func admit(_ key: Key) -> Key? {
        if order.contains(key) { return nil }
        order.append(key)
        return order.count > capacity ? order.removeFirst() : nil
    }

    public mutating func remove(_ key: Key) { order.removeAll { $0 == key } }

    public mutating func removeAll() { order.removeAll() }
}
