// MIDIEndpointDiff.swift — changes between two endpoint lists (MIDI-001-R5; data-model.md).
//
// Order: disappeared (old-list order), appeared, renamed, online changed (new-list order). An endpoint
// that appeared or disappeared has no other change; one that was renamed and changed online status in
// the same refresh reports both, renamed first. An unchanged list reports nothing.

public enum MIDIEndpointChange: Sendable, Hashable {
    case appeared(MIDIEndpoint)
    case disappeared(MIDIEndpoint)
    case renamed(MIDIEndpointID, from: String, to: String)
    case onlineChanged(MIDIEndpointID, isOnline: Bool)

    public var endpointID: MIDIEndpointID {
        switch self {
        case .appeared(let endpoint), .disappeared(let endpoint): endpoint.id
        case .renamed(let id, _, _), .onlineChanged(let id, _): id
        }
    }
}

public enum MIDIEndpointDiff {
    public static func changes(from old: MIDIEndpointList, to new: MIDIEndpointList) -> [MIDIEndpointChange] {
        var oldByID: [MIDIEndpointID: MIDIEndpoint] = [:]
        for endpoint in old.endpoints { oldByID[endpoint.id] = endpoint }
        var newIDs: Set<MIDIEndpointID> = []
        for endpoint in new.endpoints { newIDs.insert(endpoint.id) }

        var disappeared: [MIDIEndpointChange] = []
        for endpoint in old.endpoints where !newIDs.contains(endpoint.id) {
            disappeared.append(.disappeared(endpoint))
        }
        var appeared: [MIDIEndpointChange] = []
        var renamed: [MIDIEndpointChange] = []
        var online: [MIDIEndpointChange] = []
        for endpoint in new.endpoints {
            guard let previous = oldByID[endpoint.id] else {
                appeared.append(.appeared(endpoint))
                continue
            }
            if previous.name != endpoint.name {
                renamed.append(.renamed(endpoint.id, from: previous.name, to: endpoint.name))
            }
            if previous.isOnline != endpoint.isOnline {
                online.append(.onlineChanged(endpoint.id, isOnline: endpoint.isOnline))
            }
        }
        return disappeared + appeared + renamed + online
    }
}
