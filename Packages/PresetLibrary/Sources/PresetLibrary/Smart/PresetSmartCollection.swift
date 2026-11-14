// PresetSmartCollection.swift — roadmap PRE-008 smart collections: the model, condition kinds, limits and
// errors (specs/228-pre-008-smart-collections, PRE-008-R1, R2, R4, R6; research PRE-008-D2).
//
// A smart collection is a named rule set: a match mode (All or Any) and conditions, each a kind and a list
// of values that are alternatives (a preset with any listed value matches the condition). Membership is never
// stored; `PresetSmartMatcher` computes it. Kinds this build does not know are kept unchanged and skipped.
// Foundation only, like the rest of the package.
import Foundation

public enum PresetSmartMatch: String, Codable, Sendable, Hashable, CaseIterable {
    case all, any

    /// R1: an unknown stored mode reads as `all`, the narrower one.
    public init(from decoder: any Decoder) throws {
        let raw: String = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = PresetSmartMatch(rawValue: raw) ?? .all
    }
}

public struct PresetSmartCondition: Codable, Sendable, Hashable {
    /// The kinds this build applies (R2).
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case tag, notTag, pack, motion, color, favorite
    }

    /// The stored kind; any string is kept, so a newer build's kinds survive (R4).
    public var kind: String
    public var values: [String]

    public init(kind: String, values: [String]) {
        self.kind = kind
        self.values = values
    }

    public init(_ kind: Kind, _ values: [String] = []) {
        self.init(kind: kind.rawValue, values: values)
    }

    /// Nil for a kind this build does not know.
    public var knownKind: Kind? { Kind(rawValue: kind) }

    private enum CodingKeys: String, CodingKey { case kind, values }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        values = try container.decodeIfPresent([String].self, forKey: .values) ?? []
    }

    /// Values de-duplicated in order (tags folded, the first spelling kept); `favorite` takes none.
    public var normalized: PresetSmartCondition {
        if knownKind == .favorite { return PresetSmartCondition(kind: kind, values: []) }
        let folds: Bool = knownKind == .tag || knownKind == .notTag
        var seen: Set<String> = []
        var kept: [String] = []
        for value in values {
            let key: String = folds ? PresetTagMap.fold(value) : value
            if seen.insert(key).inserted { kept.append(value) }
        }
        return PresetSmartCondition(kind: kind, values: kept)
    }
}

public struct PresetSmartCollection: Codable, Sendable, Hashable, Identifiable {
    /// R1, research D4: smart IDs start with this, so they never collide with manual collection IDs.
    public static let idPrefix = "smart-"

    public let id: String
    public var name: String
    public var match: PresetSmartMatch
    public var conditions: [PresetSmartCondition]

    public init(id: String, name: String, match: PresetSmartMatch, conditions: [PresetSmartCondition]) {
        self.id = id
        self.name = name
        self.match = match
        self.conditions = conditions
    }

    /// R4: how many stored conditions this build does not apply.
    public var unknownConditionCount: Int { conditions.filter { (c: PresetSmartCondition) -> Bool in c.knownKind == nil }.count }

    public static func isSmartID(_ id: String) -> Bool { id.hasPrefix(idPrefix) }
}

/// R6: bounds that keep the document small.
public enum PresetSmartLimits {
    public static let maxCollections = 100
    public static let maxConditions = 32
    public static let maxValues = 64
    public static let maxValueLength = 128
    public static let maxFileBytes = 1_024 * 1_024
}

public enum PresetSmartCollectionError: Error, Equatable, Sendable {
    case tooManyConditions(limit: Int)
    case tooManyValues(limit: Int)
    case invalidValue

    public var message: String {
        switch self {
        case .tooManyConditions(let limit): "A smart collection can have up to \(limit) rules."
        case .tooManyValues(let limit): "A rule can have up to \(limit) choices."
        case .invalidValue: "A rule choice is 1 to \(PresetSmartLimits.maxValueLength) characters."
        }
    }

    /// R6: the conditions a change may save, normalized; throws the first broken limit.
    public static func validated(_ conditions: [PresetSmartCondition]) throws -> [PresetSmartCondition] {
        guard conditions.count <= PresetSmartLimits.maxConditions else {
            throw PresetSmartCollectionError.tooManyConditions(limit: PresetSmartLimits.maxConditions)
        }
        return try conditions.map { (raw: PresetSmartCondition) -> PresetSmartCondition in
            guard raw.knownKind != nil else { return raw }   // R4: unknown kinds pass through unchanged
            let condition: PresetSmartCondition = raw.normalized
            guard condition.values.count <= PresetSmartLimits.maxValues else {
                throw PresetSmartCollectionError.tooManyValues(limit: PresetSmartLimits.maxValues)
            }
            for value in condition.values where value.isEmpty || value.count > PresetSmartLimits.maxValueLength {
                throw PresetSmartCollectionError.invalidValue
            }
            return condition
        }
    }
}
