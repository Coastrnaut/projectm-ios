// ModulationIDMigrations.swift — the stable-ID migration table (MOD-013-R2, R3; research MOD-013-D1;
// specs/064-mod-013-modulation-serialization/contracts/modulation-serialization.md M1; ADR-0012).
//
// MOD-001 never renames or reuses a shipped ID. When a later version replaces a parameter (or an
// audio feature), it retires the old ID, registers a new one and appends a rule "old renamed to new";
// an ID dropped without replacement is retired (a parameter by the catalog's retired set alone, an
// audio feature by a "retired" rule). Saved connections (scenes, later MIDI/OSC maps) resolve their
// IDs through the table.
//
// Format version 1: an ordered, append-only rule list. Each rule records the table version that
// added it (`since`, ≥ 1, never decreasing down the list); rules are never edited or removed. Renames
// chain (A → B added in 2, B → C in 3: A resolves to C) and resolution is idempotent (a chain's end has
// no rule). IDs starting with `audio.` are audio feature IDs, all others parameter IDs.

/// What a stable ID resolves to.
public enum ModulationIDResolution: Sendable, Hashable {
    /// No rule applies: the ID stands as written.
    case unchanged
    /// The ID was renamed; `chain` lists every ID from the original to `to`.
    case renamed(to: String, chain: [String])
    /// The ID (or the end of its rename chain) was retired; `chain` lists every ID visited.
    case retired(chain: [String])
}

public struct ModulationIDMigrations: Sendable, Hashable {
    /// The table's format version.
    public static let formatVersion = 1
    /// The prefix that marks an audio feature ID (`AudioFeatureSource.id`).
    public static let audioFeaturePrefix = "audio."
    /// The empty table: every ID resolves to itself.
    public static let none = ModulationIDMigrations(validated: [])

    public enum Change: Sendable, Hashable {
        case renamed(to: String)
        case retired
    }

    public struct Rule: Sendable, Hashable, CustomStringConvertible {
        public let from: String
        public let change: Change
        /// The table version that added this rule (≥ 1).
        public let since: Int

        public init(from: String, change: Change, since: Int) {
            self.from = from
            self.change = change
            self.since = since
        }

        public static func renamed(_ from: String, to: String, since: Int) -> Rule {
            Rule(from: from, change: .renamed(to: to), since: since)
        }

        public static func retired(_ from: String, since: Int) -> Rule {
            Rule(from: from, change: .retired, since: since)
        }

        public var description: String {
            switch change {
            case let .renamed(to): "\(from) → \(to) (since \(since))"
            case .retired: "\(from) retired (since \(since))"
            }
        }
    }

    public let rules: [Rule]
    private let ruleByID: [String: Rule]

    /// Validates `rules` (contract M1.1) and throws every issue found.
    public init(_ rules: [Rule]) throws(ModulationIDMigrationError) {
        let issues = Self.issues(in: rules)
        guard issues.isEmpty else { throw ModulationIDMigrationError(issues: issues) }
        self.init(validated: rules)
    }

    private init(validated rules: [Rule]) {
        self.rules = rules
        var map: [String: Rule] = [:]
        for rule in rules { map[rule.from] = rule }
        ruleByID = map
    }

    /// The largest `since`; 0 for the empty table.
    public var version: Int { rules.last?.since ?? 0 }

    public var isEmpty: Bool { rules.isEmpty }

    public static func isAudioFeatureID(_ id: String) -> Bool { id.hasPrefix(audioFeaturePrefix) }

    /// Follows renames to the end of the chain (contract M1.2). Linear in the chain length; the
    /// chain is loop-free by construction.
    public func resolve(_ id: String) -> ModulationIDResolution {
        guard ruleByID[id] != nil else { return .unchanged }
        var chain = [id]
        var current = id
        while let rule = ruleByID[current] {
            switch rule.change {
            case .retired:
                return .retired(chain: chain)
            case let .renamed(to):
                chain.append(to)
                current = to
            }
        }
        return .renamed(to: current, chain: chain)
    }

    // MARK: Structural checks

    static func issues(in rules: [Rule]) -> [ModulationIDMigrationIssue] {
        var issues: [ModulationIDMigrationIssue] = []
        func add(_ problem: ModulationIDMigrationIssue.Problem, _ index: Int, _ text: String) {
            issues.append(ModulationIDMigrationIssue(problem: problem, ruleIndex: index,
                                                     message: "Migration rule \(index) (\(rules[index])): \(text)"))
        }
        var firstIndex: [String: Int] = [:]
        var previousSince = 1
        for (i, rule) in rules.enumerated() {
            if let problem = idProblem(rule.from) { add(.malformedID, i, "\"\(rule.from)\" is ill-formed: \(problem)") }
            if rule.since < 1 {
                add(.invalidVersion, i, "the table version must be at least 1")
            } else if rule.since < previousSince {
                add(.versionOrder, i, "rules are appended in version order; version \(rule.since) follows version \(previousSince)")
            } else {
                previousSince = rule.since
            }
            if let j = firstIndex[rule.from] {
                add(.duplicateRule, i, "\"\(rule.from)\" already has rule \(j)")
            } else {
                firstIndex[rule.from] = i
            }
            if case let .renamed(to) = rule.change {
                if let problem = idProblem(to) { add(.malformedID, i, "\"\(to)\" is ill-formed: \(problem)") }
                if to == rule.from {
                    add(.selfRename, i, "an ID cannot be renamed to itself")
                } else if isAudioFeatureID(to) != isAudioFeatureID(rule.from) {
                    add(.crossKind, i, "a parameter ID and an audio feature ID cannot be renamed into each other")
                }
            }
        }
        // Each ID has at most one rule (duplicates reported above; the first counts), so the renames
        // form a functional graph: walking from each rule finds every loop in linear time overall.
        var next: [String: String] = [:]
        for (i, rule) in rules.enumerated() where firstIndex[rule.from] == i {
            if case let .renamed(to) = rule.change, to != rule.from { next[rule.from] = to }
        }
        var state: [String: Int] = [:]   // 1 = on the current walk, 2 = done
        for (i, rule) in rules.enumerated() where firstIndex[rule.from] == i && state[rule.from] == nil {
            var walk: [String] = []
            var current = rule.from
            while state[current] == nil, next[current] != nil {
                state[current] = 1
                walk.append(current)
                current = next[current] ?? current
            }
            if state[current] == 1, let start = walk.firstIndex(of: current) {
                let loop = Array(walk[start...]) + [current]
                let first = firstIndex[loop[0]] ?? i
                add(.cycle, first, "the renames form the loop " + loop.joined(separator: " → "))
            }
            for id in walk { state[id] = 2 }
        }
        return issues
    }

    /// Parameter IDs: MOD-001 syntax. Audio feature IDs: `audio.` then dot-separated segments of
    /// ASCII letters and digits.
    public static func idProblem(_ id: String) -> String? {
        guard isAudioFeatureID(id) else { return ParameterID(id).syntaxProblem }
        let rest = id.dropFirst(audioFeaturePrefix.count)
        if rest.isEmpty { return "the audio feature ID has no name after \"audio.\"" }
        for segment in rest.split(separator: ".", omittingEmptySubsequences: false) {
            if segment.isEmpty { return "a segment is empty" }
            for b in segment.utf8 where !(ParameterSyntax.isLower(b) || ParameterSyntax.isUpper(b) || ParameterSyntax.isDigit(b)) {
                return "segment \"\(segment)\" may contain only ASCII letters and digits"
            }
        }
        return nil
    }
}

/// One problem in a migration table.
public struct ModulationIDMigrationIssue: Sendable, Hashable, CustomStringConvertible {
    public enum Problem: String, Sendable, Hashable, CaseIterable {
        case malformedID
        case invalidVersion
        case versionOrder
        case duplicateRule
        case selfRename
        case crossKind
        case cycle
    }

    public let problem: Problem
    public let ruleIndex: Int
    public let message: String

    public var description: String { message }
}

/// A refused migration table: every issue, one per line.
public struct ModulationIDMigrationError: Error, Sendable, Hashable, CustomStringConvertible {
    public let issues: [ModulationIDMigrationIssue]

    public var description: String {
        (["Migration table is invalid (\(issues.count) issue\(issues.count == 1 ? "" : "s")):"]
            + issues.map { (issue: ModulationIDMigrationIssue) -> String in "- " + issue.message }).joined(separator: "\n")
    }
}
