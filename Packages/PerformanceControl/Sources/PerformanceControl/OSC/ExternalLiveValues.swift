// ExternalLiveValues.swift — one live-value map from MIDI and OSC (OSC-003-R5; specs/191-osc-003-parameter-routes,
// research OSC-003-D3).
//
// MIDI-003's live values and OSC-003's live values feed the same per-frame path (the native host's external
// values, then MOD-002 and the ACC-012 clamp). When both drive one parameter, the source whose value changed most
// recently wins; when that source stops driving it, the other source's value is used. Memory only. Pure Swift.
import ParameterGraph

public struct ExternalLiveValues: Sendable, Equatable {
    public enum Source: Sendable, Hashable, CaseIterable {
        case midi
        case osc
    }

    private var bySource: [Source: [ParameterID: Double]] = [:]
    private var owner: [ParameterID: Source] = [:]

    public init() {}

    /// Replaces `source`'s values; every parameter whose value changed (or appeared) is now owned by `source`.
    public mutating func update(_ source: Source, _ values: [ParameterID: Double]) {
        let old: [ParameterID: Double] = bySource[source] ?? [:]
        for (id, value) in values where old[id]?.bitPattern != value.bitPattern { owner[id] = source }
        bySource[source] = values.isEmpty ? nil : values
        for (id, holder) in owner where bySource[holder]?[id] == nil { owner[id] = nil }
    }

    public func values(of source: Source) -> [ParameterID: Double] { bySource[source] ?? [:] }

    /// One value per parameter: the owner's, else the first source (in `Source` order) that has one.
    public var merged: [ParameterID: Double] {
        var result: [ParameterID: Double] = [:]
        for source in Source.allCases {
            for (id, value) in bySource[source] ?? [:] where result[id] == nil { result[id] = value }
        }
        for (id, holder) in owner { if let value = bySource[holder]?[id] { result[id] = value } }
        return result
    }
}
