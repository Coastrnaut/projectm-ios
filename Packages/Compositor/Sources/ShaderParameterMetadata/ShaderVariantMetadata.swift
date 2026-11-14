// ShaderVariantMetadata.swift — a document's alternative precompiled implementations (SHD-004-R1; specs/231-
// shd-004-shader-variant-switching, data-model.md, contracts/material-variants.md V1).
//
// An optional `variants` list names 2-4 implementations of the same parameters: each has an ID (well-formed,
// unique, starting with the document's `variant`), a label and an optional Apple GPU family it requires. The
// first entry is the default: its ID is the document's `variant` and it requires nothing, so a fallback always
// exists. Without the list the document has one implicit variant, labelled "Standard". Data only: nothing here
// is compiled or loaded (SHD-011). Plain Swift; builds on Linux.
import ParameterGraph

/// An Apple GPU family a variant may require (the names every SDK in use knows).
public enum ShaderGPUFamily: String, Sendable, Hashable, CaseIterable, Comparable {
    case apple7
    case apple8
    case apple9

    /// "Apple GPU family 9".
    public var displayName: String {
        switch self {
        case .apple7: "Apple GPU family 7"
        case .apple8: "Apple GPU family 8"
        case .apple9: "Apple GPU family 9"
        }
    }

    private var order: Int { ShaderGPUFamily.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: ShaderGPUFamily, rhs: ShaderGPUFamily) -> Bool { lhs.order < rhs.order }
}

/// One validated variant.
public struct ShaderVariantSpec: Sendable, Hashable {
    public let id: String
    public let label: String
    /// nil: runs on every supported GPU.
    public let requires: ShaderGPUFamily?

    public init(id: String, label: String, requires: ShaderGPUFamily? = nil) {
        self.id = id
        self.label = label
        self.requires = requires
    }
}

extension ShaderMetadataReader {
    public static let variantCount = 2...4
    public static let defaultVariantLabel = "Standard"
    static let variantKeys: Set<String> = ["id", "label", "requires"]

    /// The document's variants (first = default); one implicit "Standard" variant when the key is absent.
    static func variants(_ root: ShaderMetadataObject, variant: String) throws(ShaderMetadataError) -> [ShaderVariantSpec] {
        guard root.has("variants") else { return [ShaderVariantSpec(id: variant, label: defaultVariantLabel)] }
        let items: [ShaderMetadataJSON] = try root.array("variants")
        guard variantCount.contains(items.count) else { throw .variantCount(document: root.document, count: items.count) }
        var result: [ShaderVariantSpec] = []
        var seen: Set<String> = []
        for (index, item) in items.enumerated() {
            let o: ShaderMetadataObject = try ShaderMetadataObject(item, document: root.document, path: "variants[\(index)]")
            let spec: ShaderVariantSpec = try variantSpec(o, base: variant, isDefault: index == 0)
            guard seen.insert(spec.id).inserted else { throw .duplicateVariantID(document: root.document, variantID: spec.id) }
            result.append(spec)
        }
        return result
    }

    static func variantSpec(_ o: ShaderMetadataObject, base: String, isDefault: Bool) throws(ShaderMetadataError) -> ShaderVariantSpec {
        try o.requireOnly(variantKeys)
        let id: String = try o.string("id")
        guard ParameterEnumCase.isWellFormedID(id) else { throw .invalidID(document: o.document, path: o.path, key: "id", value: id) }
        if isDefault, id != base { throw .defaultVariantMismatch(document: o.document, variantID: id, expected: base) }
        guard id.hasPrefix(base) else { throw .variantPrefix(document: o.document, path: o.path, variantID: id, prefix: base) }
        let text: String = try label(o, "label", limit: maximumLabelLength)
        var family: ShaderGPUFamily? = nil
        if o.has("requires") {
            let raw: String = try o.string("requires")
            guard let known = ShaderGPUFamily(rawValue: raw) else {
                throw .unknownGPUFamily(document: o.document, path: o.path, family: raw)
            }
            if isDefault { throw .defaultVariantRequirement(document: o.document, variantID: id) }
            family = known
        }
        return ShaderVariantSpec(id: id, label: text, requires: family)
    }
}

extension ValidatedShaderMetadata {
    /// The default variant (always present).
    public var defaultVariant: ShaderVariantSpec { variants.first ?? ShaderVariantSpec(id: variant, label: ShaderMetadataReader.defaultVariantLabel) }

    /// The variant whose ID is exactly `id`, or nil.
    public func variantSpec(_ id: String) -> ShaderVariantSpec? { variants.first { $0.id == id } }
}
