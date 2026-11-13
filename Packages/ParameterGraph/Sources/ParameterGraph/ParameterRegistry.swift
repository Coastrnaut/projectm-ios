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
    private let indexByID: [ParameterID: Int]

    /// Validates `descriptors` and throws every issue found (MOD-001-R5).
    public init(descriptors: [ParameterDescriptor], retiredIDs: Set<ParameterID> = []) throws(ParameterRegistryError) {
        let issues = ParameterValidator.validate(descriptors, retiredIDs: retiredIDs)
        guard issues.isEmpty else { throw ParameterRegistryError(issues: issues) }
        self.descriptors = descriptors
        self.retiredIDs = retiredIDs
        var index: [ParameterID: Int] = [:]
        for (i, d) in descriptors.enumerated() { index[d.id] = i }
        indexByID = index
    }

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
