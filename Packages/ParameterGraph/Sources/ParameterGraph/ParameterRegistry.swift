// ParameterRegistry.swift — the validated, ordered catalog of parameters (MOD-001-R5, R6;
// contract C2).
//
// An immutable value: built once per build from an ordered descriptor list, validated as a whole,
// then shared freely (Sendable). Enumeration is in registration order; lookup is O(1).

public struct ParameterRegistry: Sendable {
    /// Every descriptor, in registration order.
    public let descriptors: [ParameterDescriptor]
    /// IDs that once shipped and may never be registered again.
    public let retiredIDs: Set<ParameterID>
    /// How retired parameter and audio feature IDs map to their replacements (MOD-013-R2, ADR-0012).
    public let migrations: ModulationIDMigrations
    private let indexByID: [ParameterID: Int]

    /// Validates `descriptors` and the migration table against them (MOD-001-R5, MOD-013-R4) and
    /// throws every issue found.
    public init(descriptors: [ParameterDescriptor], retiredIDs: Set<ParameterID> = [],
                migrations: ModulationIDMigrations = .none) throws(ParameterRegistryError) {
        var issues = ParameterValidator.validate(descriptors, retiredIDs: retiredIDs)
        var index: [ParameterID: Int] = [:]
        for (i, d) in descriptors.enumerated() where index[d.id] == nil { index[d.id] = i }
        issues += Self.migrationIssues(migrations, registered: Set(index.keys), retiredIDs: retiredIDs)
        guard issues.isEmpty else { throw ParameterRegistryError(issues: issues) }
        self.descriptors = descriptors
        self.retiredIDs = retiredIDs
        self.migrations = migrations
        indexByID = index
    }

    /// Contract M2: a migrated parameter ID is retired and unregistered; a rename chain ends at a
    /// registered or retired ID; an audio rule's old ID is no known feature and its chain ends at one.
    static func migrationIssues(_ migrations: ModulationIDMigrations, registered: Set<ParameterID>,
                                retiredIDs: Set<ParameterID>) -> [ParameterValidationIssue] {
        var issues: [ParameterValidationIssue] = []
        for (i, rule) in migrations.rules.enumerated() {
            let id = ParameterID(rule.from)
            func add(_ problem: ParameterValidationIssue.Problem, _ text: String) {
                issues.append(ParameterValidationIssue(parameter: id, problem: problem,
                                                       message: "Migration rule \(i) (\(rule)): \(text)"))
            }
            let isAudio = ModulationIDMigrations.isAudioFeatureID(rule.from)
            if isAudio {
                if AudioFeatureSource(id: rule.from) != nil {
                    add(.migrationFromRegistered, "\"\(rule.from)\" is an audio feature of this version")
                }
            } else {
                if registered.contains(id) {
                    add(.migrationFromRegistered, "\"\(rule.from)\" is still registered; a shipped ID is never reused")
                }
                if !retiredIDs.contains(id) {
                    add(.migrationFromNotRetired, "\"\(rule.from)\" must be in the catalog's retired set")
                }
            }
            guard case let .renamed(to: end, chain: _) = migrations.resolve(rule.from) else { continue }
            if isAudio {
                if AudioFeatureSource(id: end) == nil {
                    add(.migrationTargetUnknown, "the rename chain ends at \"\(end)\", which is not an audio feature of this version")
                }
            } else if !registered.contains(ParameterID(end)) && !retiredIDs.contains(ParameterID(end)) {
                add(.migrationTargetUnknown, "the rename chain ends at \"\(end)\", which is neither registered nor retired")
            }
        }
        return issues
    }

    /// The parameter `id` after the migration table and the retired set (MOD-013-R3): renames are
    /// followed to the end, and an ID (or chain end) in the retired set is retired.
    public func resolveParameter(_ id: ParameterID) -> ModulationIDResolution {
        let resolution = migrations.resolve(id.rawValue)
        switch resolution {
        case .unchanged:
            return retiredIDs.contains(id) ? .retired(chain: [id.rawValue]) : .unchanged
        case let .renamed(to, chain):
            return retiredIDs.contains(ParameterID(to)) ? .retired(chain: chain) : resolution
        case .retired:
            return resolution
        }
    }

    /// The audio feature `id` after the migration table.
    public func resolveAudioFeature(_ id: String) -> ModulationIDResolution { migrations.resolve(id) }

    /// Every issue in `descriptors`, in registration order, without throwing.
    public static func validate(_ descriptors: [ParameterDescriptor], retiredIDs: Set<ParameterID> = []) -> [ParameterValidationIssue] {
        ParameterValidator.validate(descriptors, retiredIDs: retiredIDs)
    }

    public var count: Int { descriptors.count }

    /// IDs in registration order.
    public var ids: [ParameterID] { descriptors.map(\.id) }

    /// Groups in order of first appearance.
    public var groups: [ParameterGroup] {
        var seen: Set<String> = []
        return descriptors.compactMap { seen.insert($0.group.id).inserted ? $0.group : nil }
    }

    public func descriptor(for id: ParameterID) -> ParameterDescriptor? {
        indexByID[id].map { descriptors[$0] }
    }

    public func contains(_ id: ParameterID) -> Bool { indexByID[id] != nil }

    /// The group's descriptors, in registration order.
    public func descriptors(inGroup groupID: String) -> [ParameterDescriptor] {
        descriptors.filter { $0.group.id == groupID }
    }
}
