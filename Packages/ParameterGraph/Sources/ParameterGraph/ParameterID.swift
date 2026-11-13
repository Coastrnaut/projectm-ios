// ParameterID.swift — stable parameter identity (MOD-001-R1; research MOD-001-D2; ADR-0012).
//
// An ID is `domain.subject.name`: two or more segments separated by ".", each a lowercase ASCII
// letter followed by ASCII letters and digits, at most 128 characters in all. Construction never
// fails; `syntaxProblem` says what is wrong so catalog validation (not a crash) rejects it.
// Once shipped an ID is never renamed, reused or given another kind; retired IDs are listed in the
// catalog's retired set and can never be registered again.

/// The stable, dotted name of one parameter, for example `visual.circularSpectrum.gap`.
public struct ParameterID: Sendable, Hashable, Comparable, CustomStringConvertible,
    ExpressibleByStringLiteral, Codable, CodingKeyRepresentable {
    public static let maximumLength = 128

    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }
    public var segments: [Substring] { rawValue.split(separator: ".", omittingEmptySubsequences: false) }
    /// The first segment (`visual`, `effect`, …).
    public var domain: Substring { segments.first ?? "" }

    public var isWellFormed: Bool { syntaxProblem == nil }

    /// Why this ID is ill-formed, or nil.
    public var syntaxProblem: String? {
        if rawValue.isEmpty { return "the ID is empty" }
        if rawValue.utf8.count > Self.maximumLength {
            return "the ID is longer than \(Self.maximumLength) characters"
        }
        let parts = segments
        if parts.count < 2 { return "the ID needs at least two dot-separated segments (domain.name)" }
        for part in parts {
            if let problem = ParameterSyntax.segmentProblem(part) { return problem }
        }
        return nil
    }

    public static func < (lhs: ParameterID, rhs: ParameterID) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init?<T: CodingKey>(codingKey: T) { rawValue = codingKey.stringValue }
    public var codingKey: any CodingKey { ParameterCodingKey(stringValue: rawValue) }
}

private struct ParameterCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// A group of related parameters (for example the glow), used to enumerate and present them.
/// The ID has one or more segments with the parameter ID's segment syntax.
public struct ParameterGroup: Sendable, Hashable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    /// Why the group ID is ill-formed, or nil.
    public var syntaxProblem: String? {
        if id.isEmpty { return "the group ID is empty" }
        if id.utf8.count > ParameterID.maximumLength { return "the group ID is too long" }
        for part in id.split(separator: ".", omittingEmptySubsequences: false) {
            if let problem = ParameterSyntax.segmentProblem(part) { return "group ID: " + problem }
        }
        return nil
    }
}

enum ParameterSyntax {
    static func isLower(_ b: UInt8) -> Bool { b >= 0x61 && b <= 0x7A }
    static func isUpper(_ b: UInt8) -> Bool { b >= 0x41 && b <= 0x5A }
    static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

    static func segmentProblem(_ segment: Substring) -> String? {
        guard let first = segment.utf8.first else { return "a segment is empty" }
        guard isLower(first) else { return "segment \"\(segment)\" must start with a lowercase ASCII letter" }
        for b in segment.utf8 where !(isLower(b) || isUpper(b) || isDigit(b)) {
            return "segment \"\(segment)\" may contain only ASCII letters and digits"
        }
        return nil
    }
}
