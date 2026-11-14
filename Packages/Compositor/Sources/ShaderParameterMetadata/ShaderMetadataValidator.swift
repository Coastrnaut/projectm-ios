// ShaderMetadataValidator.swift — a metadata document read and validated into typed parameter specs
// (SHD-003-R1, R2, R3; data-model.md; contracts/shader-parameter-metadata.md M1).
//
// `ShaderMetadataReader.validate(json:document:requiredParameters:)` returns `ValidatedShaderMetadata` or
// throws the first problem in document order. Only a validated document reaches the descriptor mapping and
// the control builder. Plain Swift; builds on Linux.
import Foundation
import ParameterGraph

/// A parameter's kind with its constraints and default, as the metadata declares it.
public enum ShaderParameterKind: Sendable, Hashable {
    case float(minimum: Double, maximum: Double, step: Double, defaultValue: Double)
    case int(minimum: Int, maximum: Int, step: Int, defaultValue: Int)
    case bool(defaultValue: Bool)
    case enumeration(cases: [ParameterEnumCase], defaultValue: String)
    case color(defaultValue: ParameterColor)

    /// The metadata's kind name.
    public var name: String {
        switch self {
        case .float: "float"
        case .int: "int"
        case .bool: "bool"
        case .enumeration: "enum"
        case .color: "color"
        }
    }

    public var isColor: Bool {
        if case .color = self { return true }
        return false
    }
}

/// One validated parameter.
public struct ShaderParameterSpec: Sendable, Hashable {
    /// The parameter's name inside its variant (`speed`); the registry ID is `<prefix>.<id>`.
    public let id: String
    public let label: String
    /// The uniform slot (equal to the parameter's position).
    public let slot: Int
    public let unit: ParameterUnit
    public let kind: ShaderParameterKind
}

/// A document that passed every check of SHD-003-R2 and R3.
public struct ValidatedShaderMetadata: Sendable, Hashable {
    /// The name errors use (`material.gradient`).
    public let document: String
    public let variant: String
    public let name: String
    public let summary: String
    /// In slot order.
    public let parameters: [ShaderParameterSpec]

    public func parameter(_ id: String) -> ShaderParameterSpec? { parameters.first { $0.id == id } }
}

public enum ShaderMetadataReader {
    public static let schemaVersion = 1.0
    public static let maximumParameters = 8
    public static let maximumLabelLength = 64
    public static let maximumSummaryLength = 200
    public static let enumCaseCount = 2...16

    static let documentKeys: Set<String> = ["schema", "variant", "name", "summary", "parameters"]
    static let parameterKeys: Set<String> = ["id", "label", "kind", "slot", "unit", "min", "max", "step", "default", "cases"]
    static let caseKeys: Set<String> = ["id", "label"]

    /// Reads and validates `json`. `requiredParameters` are parameter IDs the variant must declare (a
    /// material's `speed` and `audioReactivity`).
    public static func validate(json: String, document: String,
                                requiredParameters: [String] = []) throws(ShaderMetadataError) -> ValidatedShaderMetadata {
        let root: ShaderMetadataObject = try ShaderMetadataObject(ShaderMetadataJSON.parse(json, document: document),
                                                                 document: document, path: "document")
        try root.requireOnly(documentKeys)
        let schema: Double = try root.number("schema")
        guard schema == schemaVersion else { throw .unsupportedSchema(document: document, version: schema) }
        let variant: String = try root.string("variant")
        guard ParameterEnumCase.isWellFormedID(variant) else {
            throw .invalidID(document: document, path: "document", key: "variant", value: variant)
        }
        let name: String = try label(root, "name", limit: maximumLabelLength)
        let summary: String = try label(root, "summary", limit: maximumSummaryLength)
        let items: [ShaderMetadataJSON] = try root.array("parameters")
        guard (1...maximumParameters).contains(items.count) else { throw .parameterCount(document: document, count: items.count) }
        var parameters: [ShaderParameterSpec] = []
        var seen: Set<String> = []
        for (position, item) in items.enumerated() {
            let object: ShaderMetadataObject = try ShaderMetadataObject(item, document: document, path: "parameters[\(position)]")
            let spec: ShaderParameterSpec = try parameter(object)
            guard seen.insert(spec.id).inserted else { throw .duplicateParameterID(document: document, parameterID: spec.id) }
            guard spec.slot == position else {
                throw .slotMismatch(document: document, parameterID: spec.id, slot: spec.slot, position: position)
            }
            parameters.append(spec)
        }
        for required in requiredParameters where !seen.contains(required) {
            throw .missingRequiredParameter(document: document, parameterID: required)
        }
        return ValidatedShaderMetadata(document: document, variant: variant, name: name, summary: summary, parameters: parameters)
    }

    // MARK: - Parameters

    static func parameter(_ o: ShaderMetadataObject) throws(ShaderMetadataError) -> ShaderParameterSpec {
        try o.requireOnly(parameterKeys)
        let id: String = try o.string("id")
        guard ParameterEnumCase.isWellFormedID(id) else { throw .invalidID(document: o.document, path: o.path, key: "id", value: id) }
        let text: String = try label(o, "label", limit: maximumLabelLength)
        let kindName: String = try o.string("kind")
        let slot: Int = try o.whole("slot")
        let kind: ShaderParameterKind
        switch kindName {
        case "float": kind = try float(o)
        case "int": kind = try integer(o)
        case "bool":
            try o.refuse(["unit", "min", "max", "step", "cases"], kind: kindName)
            kind = .bool(defaultValue: try o.bool("default"))
        case "enum": kind = try enumeration(o)
        case "color": kind = try color(o)
        default: throw .unknownKind(document: o.document, path: o.path, kind: kindName)
        }
        return ShaderParameterSpec(id: id, label: text, slot: slot, unit: try unit(o), kind: kind)
    }

    static func unit(_ o: ShaderMetadataObject) throws(ShaderMetadataError) -> ParameterUnit {
        guard o.has("unit") else { return .none }
        let raw: String = try o.string("unit")
        guard let unit = ParameterUnit(rawValue: raw) else { throw .unknownUnit(document: o.document, path: o.path, unit: raw) }
        return unit
    }

    static func float(_ o: ShaderMetadataObject) throws(ShaderMetadataError) -> ShaderParameterKind {
        try o.refuse(["cases"], kind: "float")
        let minimum: Double = try o.number("min")
        let maximum: Double = try o.number("max")
        guard minimum < maximum else { throw .invertedRange(document: o.document, path: o.path) }
        let step: Double = try o.number("step")
        guard step > 0, step <= maximum - minimum else { throw .invalidStep(document: o.document, path: o.path) }
        let value: Double = try o.number("default")
        guard value >= minimum, value <= maximum else { throw .defaultOutOfRange(document: o.document, path: o.path) }
        return .float(minimum: minimum, maximum: maximum, step: step, defaultValue: value)
    }

    static func integer(_ o: ShaderMetadataObject) throws(ShaderMetadataError) -> ShaderParameterKind {
        try o.refuse(["cases"], kind: "int")
        let minimum: Int = try o.whole("min")
        let maximum: Int = try o.whole("max")
        guard minimum < maximum else { throw .invertedRange(document: o.document, path: o.path) }
        let step: Int = o.has("step") ? try o.whole("step") : 1
        guard step >= 1, step <= maximum - minimum else { throw .invalidStep(document: o.document, path: o.path) }
        let value: Int = try o.whole("default")
        guard value >= minimum, value <= maximum else { throw .defaultOutOfRange(document: o.document, path: o.path) }
        guard (value - minimum) % step == 0 else { throw .defaultOffStep(document: o.document, path: o.path) }
        return .int(minimum: minimum, maximum: maximum, step: step, defaultValue: value)
    }

    static func enumeration(_ o: ShaderMetadataObject) throws(ShaderMetadataError) -> ShaderParameterKind {
        try o.refuse(["unit", "min", "max", "step"], kind: "enum")
        let items: [ShaderMetadataJSON] = try o.array("cases")
        guard enumCaseCount.contains(items.count) else { throw .caseCount(document: o.document, path: o.path, count: items.count) }
        var cases: [ParameterEnumCase] = []
        var seen: Set<String> = []
        for (index, item) in items.enumerated() {
            let c: ShaderMetadataObject = try ShaderMetadataObject(item, document: o.document, path: o.path + ".cases[\(index)]")
            try c.requireOnly(caseKeys)
            let id: String = try c.string("id")
            guard ParameterEnumCase.isWellFormedID(id) else { throw .invalidID(document: o.document, path: c.path, key: "id", value: id) }
            guard seen.insert(id).inserted else { throw .duplicateCaseID(document: o.document, path: o.path, caseID: id) }
            cases.append(ParameterEnumCase(id: id, displayName: try label(c, "label", limit: maximumLabelLength)))
        }
        let value: String = try o.string("default")
        guard seen.contains(value) else { throw .defaultNotACase(document: o.document, path: o.path, value: value) }
        return .enumeration(cases: cases, defaultValue: value)
    }

    static func color(_ o: ShaderMetadataObject) throws(ShaderMetadataError) -> ShaderParameterKind {
        try o.refuse(["unit", "min", "max", "step", "cases"], kind: "color")
        let items: [ShaderMetadataJSON] = try o.array("default")
        var components: [Double] = []
        for item in items {
            guard case let .number(v) = item, v.isFinite, v >= 0, v <= 1 else { throw .invalidColor(document: o.document, path: o.path) }
            components.append(v)
        }
        guard components.count == 4 else { throw .invalidColor(document: o.document, path: o.path) }
        return .color(defaultValue: ParameterColor(red: components[0], green: components[1], blue: components[2], alpha: components[3]))
    }

    /// Text of 1…`limit` characters that is not only white space.
    static func label(_ o: ShaderMetadataObject, _ key: String, limit: Int) throws(ShaderMetadataError) -> String {
        let text: String = try o.string(key)
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text.count <= limit else { throw .invalidLabel(document: o.document, path: o.path, key: key) }
        return text
    }
}
