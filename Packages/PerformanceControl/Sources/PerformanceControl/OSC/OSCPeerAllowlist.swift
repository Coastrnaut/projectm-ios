// OSCPeerAllowlist.swift — the optional allowlist of approved local hosts (OSC-008; specs/200-osc-008-peer-allowlist,
// contracts/osc-peer-allowlist.md A3; ADR-0058).
//
// * Off by default: `admits` is then always true and records nothing, so OSC behaves as before (OSC-008-R1).
// * A peer is its host address only: the port is never seen here, and an IPv4-mapped IPv6 address is the same
//   peer as its IPv4 form (OSC-008-R2).
// * Only local hosts (OSC-001's `isLocal` rule) may be approved; at most 16, and approving refuses a full list
//   rather than evicting a host the user chose (OSC-008-R3, R5).
// * While on, a datagram from a host not on the list, or from an unknown host (fail closed), is refused; a known
//   host moves to the front of the in-memory "recently blocked" list (at most 4, distinct) (OSC-008-R4, R6).
// * Checked per datagram on the transport's queue under one small lock: O(1) work (OSC-008-S4).
// Pure Swift (no Foundation), so it is tested on every host.
import Synchronization

extension OSCPeerAddress {
    /// The same host in one canonical form: an IPv4-mapped IPv6 address becomes IPv4 (OSC-008-R2).
    public var normalized: OSCPeerAddress {
        if case let .ipv6(b) = self, b.count == 16, b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xFF, b[11] == 0xFF {
            return .ipv4(b[12], b[13], b[14], b[15])
        }
        return self
    }

    /// The form shown in Settings: dotted IPv4, or IPv6 with the longest run of zero groups compressed (RFC 5952).
    public var text: String {
        switch self {
        case let .ipv4(a, b, c, d):
            return "\(a).\(b).\(c).\(d)"
        case let .ipv6(bytes):
            guard bytes.count == 16 else { return "invalid" }
            let groups: [Int] = Self.groups(bytes)
            var bestStart = -1, bestLength = 0, runStart = -1
            for i in 0...8 {
                if i < 8 && groups[i] == 0 {
                    if runStart < 0 { runStart = i }
                } else if runStart >= 0 {
                    let length: Int = i - runStart
                    if length > bestLength && length > 1 { bestStart = runStart; bestLength = length }
                    runStart = -1
                }
            }
            let hex: [String] = groups.map { (g: Int) -> String in String(g, radix: 16) }
            guard bestStart >= 0 else { return hex.joined(separator: ":") }
            let head: String = hex[0..<bestStart].joined(separator: ":")
            let tail: String = hex[(bestStart + bestLength)...].joined(separator: ":")
            return head + "::" + tail
        }
    }

    /// The stored form: dotted IPv4, or IPv6 as 8 lowercase hex groups without compression.
    public var storageText: String {
        switch self {
        case .ipv4: return text
        case let .ipv6(bytes):
            guard bytes.count == 16 else { return "invalid" }
            return Self.groups(bytes).map { (g: Int) -> String in String(g, radix: 16) }.joined(separator: ":")
        }
    }

    /// Reads dotted IPv4 or IPv6 hex groups (`::` allowed once, no embedded IPv4, no zone); nil otherwise.
    public init?(text: String) {
        if text.contains(".") {
            let parts: [Substring] = text.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            var bytes: [UInt8] = []
            for part in parts {
                guard (1...3).contains(part.count), part.allSatisfy({ (c: Character) -> Bool in c.isASCII && c.isNumber }),
                      let value = UInt8(part) else { return nil }
                bytes.append(value)
            }
            self = .ipv4(bytes[0], bytes[1], bytes[2], bytes[3])
            return
        }
        guard text.count <= 39, text.contains(":") else { return nil }
        let halves: [String] = text.components(separatedByDoubleColon: ())
        guard halves.count <= 2 else { return nil }
        func parse(_ part: String) -> [Int]? {
            if part.isEmpty { return [] }
            var groups: [Int] = []
            for field in part.split(separator: ":", omittingEmptySubsequences: false) {
                guard (1...4).contains(field.count), let value = Int(field, radix: 16) else { return nil }
                groups.append(value)
            }
            return groups
        }
        var groups: [Int]
        if halves.count == 2 {
            guard let head = parse(halves[0]), let tail = parse(halves[1]), head.count + tail.count <= 7 else { return nil }
            groups = head + Array(repeating: 0, count: 8 - head.count - tail.count) + tail
        } else {
            guard let all = parse(halves[0]), all.count == 8 else { return nil }
            groups = all
        }
        var bytes: [UInt8] = []
        for group in groups {
            bytes.append(UInt8(group >> 8))
            bytes.append(UInt8(group & 0xFF))
        }
        self = .ipv6(bytes)
    }

    private static func groups(_ bytes: [UInt8]) -> [Int] {
        (0..<8).map { (i: Int) -> Int in Int(bytes[2 * i]) << 8 | Int(bytes[2 * i + 1]) }
    }
}

private extension String {
    /// Splits at "::" (pure Swift; Foundation is not imported here).
    func components(separatedByDoubleColon: Void) -> [String] {
        var parts: [String] = []
        var current: String = ""
        var index: String.Index = startIndex
        while index < endIndex {
            let next: String.Index = self.index(after: index)
            if self[index] == ":" && next < endIndex && self[next] == ":" {
                parts.append(current)
                current = ""
                index = self.index(after: next)
            } else {
                current.append(self[index])
                index = next
            }
        }
        parts.append(current)
        return parts
    }
}

public final class OSCPeerAllowlist: Sendable {
    /// OSC-008-R5.
    public static let maximumApproved = 16
    /// OSC-008-R4.
    public static let maximumRecentlyBlocked = 4

    public enum ApproveResult: Sendable, Equatable {
        case approved, alreadyApproved, full, notLocal
    }

    private struct State {
        var isEnabled = false
        var approved: [OSCPeerAddress] = []
        var approvedSet: Set<OSCPeerAddress> = []
        var recentlyBlocked: [OSCPeerAddress] = []
    }

    private let state = Mutex(State())

    public init() {}

    public var isEnabled: Bool { state.withLock { $0.isEnabled } }
    /// In approval order.
    public var approved: [OSCPeerAddress] { state.withLock { $0.approved } }
    /// Most recent first; memory only.
    public var recentlyBlocked: [OSCPeerAddress] { state.withLock { $0.recentlyBlocked } }

    public func setEnabled(_ enabled: Bool) {
        state.withLock { s in
            s.isEnabled = enabled
            if !enabled { s.recentlyBlocked.removeAll() }
        }
    }

    /// Replaces the list (loading stored settings): non-local hosts and duplicates are dropped, then the first 16 kept.
    public func setApproved(_ peers: [OSCPeerAddress]) {
        var list: [OSCPeerAddress] = []
        var seen: Set<OSCPeerAddress> = []
        for peer in peers {
            let host: OSCPeerAddress = peer.normalized
            guard host.isLocal, !seen.contains(host), list.count < Self.maximumApproved else { continue }
            seen.insert(host)
            list.append(host)
        }
        state.withLock { s in
            s.approved = list
            s.approvedSet = seen
            s.recentlyBlocked.removeAll { (p: OSCPeerAddress) -> Bool in seen.contains(p) }
        }
    }

    @discardableResult
    public func approve(_ peer: OSCPeerAddress) -> ApproveResult {
        let host: OSCPeerAddress = peer.normalized
        guard host.isLocal else { return .notLocal }
        return state.withLock { s -> ApproveResult in
            if s.approvedSet.contains(host) { return .alreadyApproved }
            guard s.approved.count < Self.maximumApproved else { return .full }
            s.approved.append(host)
            s.approvedSet.insert(host)
            s.recentlyBlocked.removeAll { (p: OSCPeerAddress) -> Bool in p == host }
            return .approved
        }
    }

    public func remove(_ peer: OSCPeerAddress) {
        let host: OSCPeerAddress = peer.normalized
        state.withLock { s in
            s.approved.removeAll { (p: OSCPeerAddress) -> Bool in p == host }
            s.approvedSet.remove(host)
        }
    }

    public func clearRecentlyBlocked() {
        state.withLock { $0.recentlyBlocked.removeAll() }
    }

    /// Whether a datagram from `peer` may be dispatched (OSC-008-R6). Records a refused known host as recently blocked.
    public func admits(_ peer: OSCPeerAddress?) -> Bool {
        state.withLock { s -> Bool in
            guard s.isEnabled else { return true }
            guard let peer else { return false }        // unknown host: fail closed (research OSC-008-D3)
            let host: OSCPeerAddress = peer.normalized
            if s.approvedSet.contains(host) { return true }
            if s.recentlyBlocked.first != host {
                s.recentlyBlocked.removeAll { (p: OSCPeerAddress) -> Bool in p == host }
                s.recentlyBlocked.insert(host, at: 0)
                if s.recentlyBlocked.count > Self.maximumRecentlyBlocked { s.recentlyBlocked.removeLast() }
            }
            return false
        }
    }
}
