// ShaderMetadataError.swift — every way a shader parameter metadata document can be refused (SHD-003-R2, R3,
// R4; contracts/shader-parameter-metadata.md M1).
//
// Each case carries the document's name and the path of the offending value (`parameters[2]`,
// `parameters[2].cases[1]`), and `description` says what is wrong in one sentence that names the key.
// Plain Swift; builds on Linux.

public enum ShaderMetadataError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The text is not JSON.
    case malformedJSON(document: String)
    /// A value that must be an object is not.
    case notAnObject(document: String, path: String)
    case unknownKey(document: String, path: String, key: String)
    case missingKey(document: String, path: String, key: String)
    /// A known key that does not apply to the parameter's kind (`cases` on a float).
    case keyNotAllowed(document: String, path: String, key: String, kind: String)
    case wrongType(document: String, path: String, key: String, expected: String)
    case unsupportedSchema(document: String, version: Double)
    case invalidID(document: String, path: String, key: String, value: String)
    case invalidLabel(document: String, path: String, key: String)
    case unknownKind(document: String, path: String, kind: String)
    case unknownUnit(document: String, path: String, unit: String)
    case nonFinite(document: String, path: String, key: String)
    case notWhole(document: String, path: String, key: String)
    case invertedRange(document: String, path: String)
    case invalidStep(document: String, path: String)
    case defaultOutOfRange(document: String, path: String)
    case defaultOffStep(document: String, path: String)
    case invalidColor(document: String, path: String)
    case caseCount(document: String, path: String, count: Int)
    case duplicateCaseID(document: String, path: String, caseID: String)
    case defaultNotACase(document: String, path: String, value: String)
    case duplicateParameterID(document: String, parameterID: String)
    case parameterCount(document: String, count: Int)
    case slotMismatch(document: String, parameterID: String, slot: Int, position: Int)
    case missingRequiredParameter(document: String, parameterID: String)
    /// The shader reads a slot no parameter declares.
    case undeclaredSlotRead(document: String, function: String, slot: Int)
    /// The shader reads a color's slot as one component, or a number's slot as a vector.
    case slotTypeMismatch(document: String, parameterID: String, slot: Int, kind: String, read: String)
    /// The variant's fragment function is not in the shader source.
    case missingFunction(document: String, function: String)
    /// SHD-004: `variants` has fewer than 2 or more than 4 entries.
    case variantCount(document: String, count: Int)
    case duplicateVariantID(document: String, variantID: String)
    /// SHD-004: the first variant is not the document's own `variant`.
    case defaultVariantMismatch(document: String, variantID: String, expected: String)
    /// SHD-004: a variant ID that does not start with the document's `variant` (keeps entry points unique).
    case variantPrefix(document: String, path: String, variantID: String, prefix: String)
    case unknownGPUFamily(document: String, path: String, family: String)
    /// SHD-004: the default variant must run everywhere.
    case defaultVariantRequirement(document: String, variantID: String)

    public var description: String {
        switch self {
        case let .malformedJSON(d): return "\(d): not valid JSON"
        case let .notAnObject(d, p): return "\(d): \(p) must be an object"
        case let .unknownKey(d, p, k): return "\(d): \(p) has unknown key \"\(k)\""
        case let .missingKey(d, p, k): return "\(d): \(p) is missing key \"\(k)\""
        case let .keyNotAllowed(d, p, k, kind): return "\(d): \(p) key \"\(k)\" does not apply to kind \"\(kind)\""
        case let .wrongType(d, p, k, e): return "\(d): \(p) key \"\(k)\" must be \(e)"
        case let .unsupportedSchema(d, v): return "\(d): schema \(v) is not supported (expected 1)"
        case let .invalidID(d, p, k, v): return "\(d): \(p) key \"\(k)\" value \"\(v)\" is not a well-formed ID"
        case let .invalidLabel(d, p, k): return "\(d): \(p) key \"\(k)\" is empty or too long"
        case let .unknownKind(d, p, kind): return "\(d): \(p) key \"kind\" value \"\(kind)\" is not float, int, bool, enum or color"
        case let .unknownUnit(d, p, u): return "\(d): \(p) key \"unit\" value \"\(u)\" is not a known unit"
        case let .nonFinite(d, p, k): return "\(d): \(p) key \"\(k)\" is not finite"
        case let .notWhole(d, p, k): return "\(d): \(p) key \"\(k)\" must be a whole number"
        case let .invertedRange(d, p): return "\(d): \(p) key \"min\" must be below \"max\""
        case let .invalidStep(d, p): return "\(d): \(p) key \"step\" must be positive and at most max - min"
        case let .defaultOutOfRange(d, p): return "\(d): \(p) key \"default\" is outside min...max"
        case let .defaultOffStep(d, p): return "\(d): \(p) key \"default\" is not on a step from min"
        case let .invalidColor(d, p): return "\(d): \(p) key \"default\" must be four numbers in 0...1"
        case let .caseCount(d, p, n): return "\(d): \(p) key \"cases\" has \(n) cases (2 to 16 allowed)"
        case let .duplicateCaseID(d, p, c): return "\(d): \(p) key \"cases\" repeats case ID \"\(c)\""
        case let .defaultNotACase(d, p, v): return "\(d): \(p) key \"default\" value \"\(v)\" is not a case ID"
        case let .duplicateParameterID(d, id): return "\(d): parameter \"\(id)\" is declared twice (key \"id\")"
        case let .parameterCount(d, n): return "\(d): key \"parameters\" has \(n) parameters (1 to 8 allowed)"
        case let .slotMismatch(d, id, s, p): return "\(d): parameter \"\(id)\" key \"slot\" is \(s) but its position is \(p)"
        case let .missingRequiredParameter(d, id): return "\(d): required parameter \"\(id)\" is missing (key \"parameters\")"
        case let .undeclaredSlotRead(d, f, s): return "\(d): \(f) reads slot \(s), which no parameter declares (key \"slot\")"
        case let .slotTypeMismatch(d, id, s, kind, read):
            return "\(d): parameter \"\(id)\" (kind \(kind)) is on slot \(s), which the shader reads as \(read) (key \"slot\")"
        case let .missingFunction(d, f): return "\(d): the shader has no function \(f)"
        case let .variantCount(d, n): return "\(d): key \"variants\" has \(n) variants (2 to 4 allowed)"
        case let .duplicateVariantID(d, id): return "\(d): variant \"\(id)\" is declared twice (key \"variants\")"
        case let .defaultVariantMismatch(d, id, e):
            return "\(d): variants[0] key \"id\" is \"\(id)\" but the default variant must be \"\(e)\" (key \"variant\")"
        case let .variantPrefix(d, p, id, prefix): return "\(d): \(p) key \"id\" value \"\(id)\" must start with \"\(prefix)\""
        case let .unknownGPUFamily(d, p, f): return "\(d): \(p) key \"requires\" value \"\(f)\" is not apple7, apple8 or apple9"
        case let .defaultVariantRequirement(d, id): return "\(d): default variant \"\(id)\" may not have key \"requires\""
        }
    }
}
