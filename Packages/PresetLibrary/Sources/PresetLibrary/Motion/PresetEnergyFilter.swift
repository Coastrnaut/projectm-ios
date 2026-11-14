// PresetEnergyFilter.swift — roadmap PRE-005: matching and counting presets by motion class (spec
// PRE-005-R8, R9; research PRE-005-D6). Classes exclude each other, so a selection matches presets in
// ANY selected class; the browser then ANDs that with tags, colours, Favorites and search.
import Foundation

public struct PresetEnergyFilter: Sendable, Equatable {
    public static let empty = PresetEnergyFilter(scores: [:])

    /// Preset ID → current motion score.
    public let scores: [String: Int]
    private let members: [PresetEnergy: Set<String>]

    public init(scores: [String: Int]) {
        self.scores = scores
        var members: [PresetEnergy: Set<String>] = [:]
        for (id, score) in scores { members[PresetEnergy.of(score: score), default: []].insert(id) }
        self.members = members
    }

    public func energy(of presetID: String) -> PresetEnergy? { scores[presetID].map { PresetEnergy.of(score: $0) } }

    /// Presets in any of `energies` (OR); every scored preset for an empty selection.
    public func matching(any energies: [PresetEnergy]) -> Set<String> {
        guard !energies.isEmpty else { return Set(scores.keys) }
        var result: Set<String> = []
        for energy in energies { result.formUnion(members[energy] ?? []) }
        return result
    }

    public func count(of energy: PresetEnergy) -> Int { members[energy]?.count ?? 0 }

    /// Classes with at least one preset, in the fixed order, with their counts.
    public var chips: [(energy: PresetEnergy, count: Int)] {
        PresetEnergy.allCases.compactMap { (energy: PresetEnergy) -> (energy: PresetEnergy, count: Int)? in
            let n: Int = count(of: energy)
            return n > 0 ? (energy, n) : nil
        }
    }

    /// How many presets have a class.
    public var presetCount: Int { scores.count }
}
