// ParameterValidation.swift — catalog validation (MOD-001-R5; research MOD-001-D4; contract C2).
//
// Every descriptor is checked, then the set (duplicate IDs, retired IDs, one display name per
// group). All issues are collected in registration order; a catalog with any issue is rejected.
import Foundation

public struct ParameterValidationIssue: Sendable, Hashable, CustomStringConvertible {
    public enum Problem: String, Sendable, Hashable, CaseIterable {
        case duplicateID
        case malformedID
        case retiredID
        case emptyDisplayName
        case malformedGroup
        case conflictingGroupName
        case nonFiniteNumber
        case emptyRange
        case invalidStep
        case defaultOutOfRange
        case invalidCurve
        case noEnumCases
        case malformedEnumCase
        case duplicateEnumCase
        case unknownEnumDefault
        case colorOutOfRange
        case invalidModulationPolicy
    }

    /// The parameter concerned.
    public let parameter: ParameterID?
    public let problem: Problem
    /// A readable sentence naming the parameter and the defect.
    public let message: String

    public var description: String { message }
}

/// A rejected catalog: every issue found, one per line in `description`.
public struct ParameterRegistryError: Error, Sendable, Hashable, CustomStringConvertible {
    public let issues: [ParameterValidationIssue]

    public var description: String {
        (["Parameter catalog is invalid (\(issues.count) issue\(issues.count == 1 ? "" : "s")):"]
            + issues.map { "- " + $0.message }).joined(separator: "\n")
    }
}

enum ParameterValidator {
    static func validate(_ descriptors: [ParameterDescriptor], retiredIDs: Set<ParameterID>) -> [ParameterValidationIssue] {
        var issues: [ParameterValidationIssue] = []
        var firstByID: [ParameterID: ParameterDescriptor] = [:]
        var groupNames: [String: (name: String, by: ParameterID)] = [:]

        for d in descriptors {
            func add(_ problem: ParameterValidationIssue.Problem, _ text: String) {
                issues.append(ParameterValidationIssue(parameter: d.id, problem: problem,
                                                       message: "\"\(d.id.rawValue)\" (\(d.registrationSite)): \(text)"))
            }

            // Identity.
            if let syntax = d.id.syntaxProblem {
                add(.malformedID, "malformed ID: \(syntax)")
            }
            if retiredIDs.contains(d.id) {
                add(.retiredID, "the ID is retired and can never be registered again")
            }
            if let first = firstByID[d.id] {
                add(.duplicateID, "duplicate ID: registered as \"\(first.displayName)\" at \(first.registrationSite) "
                    + "and again as \"\(d.displayName)\" at \(d.registrationSite)")
            } else {
                firstByID[d.id] = d
            }

            // Names and group.
            if d.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                add(.emptyDisplayName, "the display name is empty")
            }
            if let syntax = d.group.syntaxProblem {
                add(.malformedGroup, "malformed group: \(syntax)")
            } else if d.group.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                add(.malformedGroup, "group \"\(d.group.id)\" has an empty display name")
            } else if let known = groupNames[d.group.id] {
                if known.name != d.group.displayName {
                    add(.conflictingGroupName, "group \"\(d.group.id)\" is named \"\(d.group.displayName)\" here "
                        + "but \"\(known.name)\" by \"\(known.by.rawValue)\"")
                }
            } else {
                groupNames[d.group.id] = (d.group.displayName, d.id)
            }

            // Kind.
            for (problem, text) in kindProblems(d.kind) { add(problem, text) }

            // Modulation policy.
            if let text = policyProblem(d.modulation, kind: d.kind) { add(.invalidModulationPolicy, text) }
        }
        return issues
    }

    static func kindProblems(_ kind: ParameterKind) -> [(ParameterValidationIssue.Problem, String)] {
        switch kind {
        case let .continuous(minimum, maximum, value, step, curve):
            let numbers = [minimum, maximum, value] + (step.map { [$0] } ?? [])
            if !numbers.allSatisfy(\.isFinite) {
                return [(.nonFiniteNumber, "minimum \(minimum), maximum \(maximum), default \(value)"
                         + (step.map { ", step \($0)" } ?? "") + " must all be finite")]
            }
            if minimum >= maximum { return [(.emptyRange, "minimum \(minimum) is not below maximum \(maximum)")] }
            var problems: [(ParameterValidationIssue.Problem, String)] = []
            if let step, step <= 0 { problems.append((.invalidStep, "step \(step) must be above 0")) }
            if curve == .logarithmic, minimum <= 0 {
                problems.append((.invalidCurve, "a logarithmic curve needs a minimum above 0 (minimum \(minimum))"))
            }
            if value < minimum || value > maximum {
                problems.append((.defaultOutOfRange, "default \(value) is outside \(minimum)…\(maximum)"))
            }
            return problems
        case let .integer(minimum, maximum, value, step):
            if minimum >= maximum { return [(.emptyRange, "minimum \(minimum) is not below maximum \(maximum)")] }
            if step < 1 { return [(.invalidStep, "step \(step) must be at least 1")] }
            if value < minimum || value > maximum {
                return [(.defaultOutOfRange, "default \(value) is outside \(minimum)…\(maximum)")]
            }
            if (value - minimum) % step != 0 {
                return [(.defaultOutOfRange, "default \(value) is not on a step of \(step) from \(minimum)")]
            }
            return []
        case .boolean:
            return []
        case let .enumeration(cases, value):
            if cases.isEmpty { return [(.noEnumCases, "an enum needs at least one case")] }
            var problems: [(ParameterValidationIssue.Problem, String)] = []
            var seen: Set<String> = []
            for c in cases {
                if !ParameterEnumCase.isWellFormedID(c.id) {
                    problems.append((.malformedEnumCase, "case ID \"\(c.id)\" must be a lowercase ASCII letter or digit followed by letters and digits"))
                } else if c.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    problems.append((.malformedEnumCase, "case \"\(c.id)\" has an empty display name"))
                }
                if !seen.insert(c.id).inserted { problems.append((.duplicateEnumCase, "case ID \"\(c.id)\" appears twice")) }
            }
            if !seen.contains(value) {
                problems.append((.unknownEnumDefault, "default \"\(value)\" is not one of the cases \(cases.map(\.id))"))
            }
            return problems
        case let .color(value):
            if !value.isFinite || !value.isInRange {
                return [(.colorOutOfRange, "default color \(value.components) must have finite components in 0…1")]
            }
            return []
        }
    }

    static func policyProblem(_ policy: ModulationPolicy, kind: ParameterKind) -> String? {
        if !policy.isModulatable, !policy.mixModes.isEmpty {
            return "a parameter that is not modulatable must list no mix modes"
        }
        if policy.isModulatable, policy.mixModes.isEmpty {
            return "a modulatable parameter needs at least one mix mode"
        }
        if Set(policy.mixModes).count != policy.mixModes.count {
            return "mix modes \(policy.mixModes.map(\.rawValue)) contain a duplicate"
        }
        if !kind.isNumeric, policy.mixModes.contains(where: { $0 != .replace }) {
            return "add and multiply apply only to continuous and integer parameters (this one is \(kind.name))"
        }
        return nil
    }
}
