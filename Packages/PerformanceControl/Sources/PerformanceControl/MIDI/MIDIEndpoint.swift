// MIDIEndpoint.swift — the MIDI endpoint model (MIDI-001-R1, R3, R9; specs/107-midi-001-midi-endpoint-discovery,
// data-model.md).
//
// Pure Swift, Linux-testable. A provider reads `MIDIEndpointRecord`s; `MIDIEndpointList.make(from:)` drops
// network-attributed endpoints (MIDI-001-R2, ADR-0038), assigns stable IDs (`MIDIEndpointIdentity`) and
// orders the list. Nothing here is stored or logged (MIDI-001-R10).

/// Which way MIDI flows. A source sends to projectM (shown "Input"); a destination receives (shown "Output").
public enum MIDIEndpointDirection: String, Sendable, Hashable, CaseIterable {
    case source
    case destination
}

/// How the system attributes the endpoint's device (research MIDI-001-D5).
public enum MIDIEndpointTransport: String, Sendable, Hashable {
    /// USB, virtual, or anything not attributed to another transport.
    case local
    /// A Bluetooth MIDI device the system has already connected (listed; no pairing in MIDI-001).
    case bluetooth
    /// The system's network MIDI session: never listed (MIDI-001-R2).
    case network
}

/// One endpoint as a provider reads it from the system (or a script).
public struct MIDIEndpointRecord: Sendable, Hashable {
    /// The system's unique number; 0 when missing.
    public var uniqueID: Int32
    public var direction: MIDIEndpointDirection
    public var displayName: String
    /// Names used only for the fallback ID; empty when absent.
    public var endpointName: String
    public var entityName: String
    public var deviceName: String
    public var isOffline: Bool
    /// No entity (device) behind the endpoint: published by an app.
    public var isVirtual: Bool
    public var transport: MIDIEndpointTransport

    public init(uniqueID: Int32, direction: MIDIEndpointDirection, displayName: String,
                endpointName: String = "", entityName: String = "", deviceName: String = "",
                isOffline: Bool = false, isVirtual: Bool = false, transport: MIDIEndpointTransport = .local) {
        self.uniqueID = uniqueID
        self.direction = direction
        self.displayName = displayName
        self.endpointName = endpointName
        self.entityName = entityName
        self.deviceName = deviceName
        self.isOffline = isOffline
        self.isVirtual = isVirtual
        self.transport = transport
    }
}

/// A stable endpoint ID (MIDI-001-R3, R4; research MIDI-001-D2).
public enum MIDIEndpointID: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The system's unique number (non-zero and not shared in the snapshot).
    case system(Int32)
    /// Name-based fallback: FNV-1a 64 of direction and names, plus an ordinal for identical hashes.
    case fallback(hash: UInt64, ordinal: Int)

    /// Fallback IDs are name-based; later rows must not persist them as device identities.
    public var isFallback: Bool {
        if case .fallback = self { true } else { false }
    }

    public var description: String {
        switch self {
        case .system(let number):
            return "midi:" + String(number)
        case let .fallback(hash, ordinal):
            let hex: String = String(hash, radix: 16)
            let padded: String = String(repeating: "0", count: max(0, 16 - hex.count)) + hex
            return "midi-fb:" + padded + "-" + String(ordinal)
        }
    }

    public static func < (lhs: MIDIEndpointID, rhs: MIDIEndpointID) -> Bool {
        lhs.description < rhs.description
    }
}

/// One listed endpoint.
public struct MIDIEndpoint: Sendable, Hashable, Identifiable {
    public let id: MIDIEndpointID
    public let direction: MIDIEndpointDirection
    /// The display name, or "MIDI input"/"MIDI output" when the system gives none.
    public let name: String
    public let isOnline: Bool
    public let isVirtual: Bool
    public let transport: MIDIEndpointTransport
    /// The device's name (grouping announcements); empty for a virtual endpoint. Never stored.
    public let deviceName: String

    public init(id: MIDIEndpointID, direction: MIDIEndpointDirection, name: String, isOnline: Bool,
                isVirtual: Bool, transport: MIDIEndpointTransport, deviceName: String) {
        self.id = id
        self.direction = direction
        self.name = name
        self.isOnline = isOnline
        self.isVirtual = isVirtual
        self.transport = transport
        self.deviceName = deviceName
    }

    /// The name used when the system gives none.
    public static func placeholderName(for direction: MIDIEndpointDirection) -> String {
        switch direction {
        case .source: "MIDI input"
        case .destination: "MIDI output"
        }
    }
}

/// The ordered endpoint list (MIDI-001-R9; spec Clarifications 2026-11-14).
public struct MIDIEndpointList: Sendable, Hashable {
    public let endpoints: [MIDIEndpoint]

    public static let empty = MIDIEndpointList(sorted: [])

    private init(sorted: [MIDIEndpoint]) { endpoints = sorted }

    public var isEmpty: Bool { endpoints.isEmpty }
    public var count: Int { endpoints.count }

    public func endpoint(_ id: MIDIEndpointID) -> MIDIEndpoint? {
        endpoints.first { (endpoint: MIDIEndpoint) -> Bool in endpoint.id == id }
    }

    /// Drops network endpoints, assigns stable IDs and orders: inputs, then outputs; within each, by
    /// case-insensitive name, then ID.
    public static func make(from records: [MIDIEndpointRecord]) -> MIDIEndpointList {
        let listed: [MIDIEndpointRecord] = records.filter { (record: MIDIEndpointRecord) -> Bool in record.transport != .network }
        let ids: [MIDIEndpointID] = MIDIEndpointIdentity.assign(listed)
        var endpoints: [MIDIEndpoint] = []
        endpoints.reserveCapacity(listed.count)
        for (index, record) in listed.enumerated() {
            let trimmed: String = record.displayName.trimmingSpaces()
            let name: String = trimmed.isEmpty ? MIDIEndpoint.placeholderName(for: record.direction) : trimmed
            endpoints.append(MIDIEndpoint(id: ids[index], direction: record.direction, name: name,
                                          isOnline: !record.isOffline, isVirtual: record.isVirtual,
                                          transport: record.transport, deviceName: record.deviceName))
        }
        endpoints.sort(by: Self.precedes)
        return MIDIEndpointList(sorted: endpoints)
    }

    static func precedes(_ a: MIDIEndpoint, _ b: MIDIEndpoint) -> Bool {
        if a.direction != b.direction { return a.direction == .source }
        let nameA: String = a.name.lowercased()
        let nameB: String = b.name.lowercased()
        if nameA != nameB { return nameA < nameB }
        return a.id < b.id
    }

    /// On-screen names: the 2nd, 3rd… endpoint with the same direction and (case-insensitive) name gets
    /// " (2)", " (3)"… in list order; the first keeps its name.
    public var displayNames: [MIDIEndpointID: String] {
        var seen: [String: Int] = [:]
        var names: [MIDIEndpointID: String] = [:]
        for endpoint in endpoints {
            let key: String = endpoint.direction.rawValue + "|" + endpoint.name.lowercased()
            let count: Int = (seen[key] ?? 0) + 1
            seen[key] = count
            names[endpoint.id] = count == 1 ? endpoint.name : endpoint.name + " (" + String(count) + ")"
        }
        return names
    }
}

extension String {
    /// Leading and trailing spaces and newlines removed (no Foundation, so it builds everywhere).
    func trimmingSpaces() -> String {
        let isSpace: (Character) -> Bool = { (c: Character) -> Bool in c.isWhitespace }
        guard let first = firstIndex(where: { (c: Character) -> Bool in !isSpace(c) }),
              let last = lastIndex(where: { (c: Character) -> Bool in !isSpace(c) }) else { return "" }
        return String(self[first...last])
    }
}
