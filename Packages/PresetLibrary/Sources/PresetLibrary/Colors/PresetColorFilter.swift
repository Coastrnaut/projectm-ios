// PresetColorFilter.swift — roadmap PRE-004: matching and counting presets by colour (spec
// PRE-004-R7, R8; contract C4). Built from the current colours of listed presets only.
import Foundation

public struct PresetColorFilter: Sendable, Equatable {
    public static let empty = PresetColorFilter(colors: [:])

    /// Preset ID → dominant families (current thumbnail only).
    public let colors: [String: [PresetColorFamily]]
    private let members: [PresetColorFamily: Set<String>]

    public init(colors: [String: [PresetColorFamily]]) {
        self.colors = colors
        var members: [PresetColorFamily: Set<String>] = [:]
        for (id, families) in colors {
            for family in families { members[family, default: []].insert(id) }
        }
        self.members = members
    }

    /// Presets whose colours include every family (AND); every indexed preset for an empty selection.
    public func matching(all families: [PresetColorFamily]) -> Set<String> {
        guard let first = families.first else { return Set(colors.keys) }
        var result: Set<String> = members[first] ?? []
        for family in families.dropFirst() { result.formIntersection(members[family] ?? []) }
        return result
    }

    public func count(of family: PresetColorFamily) -> Int { members[family]?.count ?? 0 }

    /// Families with at least one preset, in the fixed order, with their counts.
    public var chips: [(family: PresetColorFamily, count: Int)] {
        PresetColorFamily.allCases.compactMap { (family: PresetColorFamily) -> (family: PresetColorFamily, count: Int)? in
            let n: Int = count(of: family)
            return n > 0 ? (family, n) : nil
        }
    }

    /// How many presets have colours.
    public var presetCount: Int { colors.count }
}
