// MaterialVariants.swift — which of a material's precompiled variants a layer draws, and why (SHD-004-R4, R5;
// specs/231-shd-004-shader-variant-switching, research SHD-004-D2, D4; contracts/material-variants.md V3).
//
// `MaterialGPUCapabilities` is the set of Apple GPU families a device supports (made from an `MTLDevice` in
// ProceduralMaterialShaders.swift, injected in tests). `MaterialVariantResolution.resolve` turns a layer's
// selection into the drawn variant: the selection when the material lists it, the GPU supports its family and
// its pipeline was built; otherwise the default variant with a notice. The selection itself is never changed
// here, so a scene keeps asking for its variant on a capable device. Plain Swift; builds on Linux.
import ShaderParameterMetadata

public struct MaterialGPUCapabilities: Sendable, Hashable {
    public let families: Set<ShaderGPUFamily>

    public init(families: Set<ShaderGPUFamily>) { self.families = families }

    /// Every family this version knows.
    public static let all = MaterialGPUCapabilities(families: Set(ShaderGPUFamily.allCases))
    /// No listed family (only variants without a requirement run).
    public static let none = MaterialGPUCapabilities(families: [])

    /// True when `variant` can run here (no requirement, or its family is supported).
    public func supports(_ variant: ShaderVariantSpec) -> Bool {
        guard let family = variant.requires else { return true }
        return families.contains(family)
    }
}

/// Why a layer draws its default variant instead of the selected one.
public enum MaterialVariantNotice: Sendable, Hashable {
    /// The material lists no variant with this ID (a newer or damaged scene).
    case unknownVariant(String)
    /// The GPU lacks the family the variant requires.
    case unsupported(variant: String, requires: ShaderGPUFamily)
    /// The variant's pipeline could not be built on this device.
    case pipelineUnavailable(String)

    /// One sentence for people.
    public var message: String {
        switch self {
        case let .unknownVariant(id): "The variant \"\(id)\" isn't available in this version, so Standard is shown."
        case let .unsupported(_, family): "This variant needs \(family.displayName), so Standard is shown on this device."
        case let .pipelineUnavailable(id): "The variant \"\(id)\" couldn't be prepared on this device, so Standard is shown."
        }
    }
}

public struct MaterialVariantResolution: Sendable, Hashable {
    /// The variant drawn.
    public let drawn: String
    /// Set when `drawn` is the default instead of the selection.
    public let notice: MaterialVariantNotice?

    public init(drawn: String, notice: MaterialVariantNotice? = nil) {
        self.drawn = drawn
        self.notice = notice
    }

    /// SHD-004-D4. `selection` nil means the default. `built` is the set of variants whose pipelines exist (nil
    /// before `prepare`: availability is not judged yet).
    public static func resolve(selection: String?, variants: [ShaderVariantSpec], capabilities: MaterialGPUCapabilities,
                               built: Set<String>?) -> MaterialVariantResolution {
        let defaultID: String = variants.first?.id ?? ""
        guard let selection, selection != defaultID else { return MaterialVariantResolution(drawn: defaultID) }
        guard let spec = variants.first(where: { (v: ShaderVariantSpec) -> Bool in v.id == selection }) else {
            return MaterialVariantResolution(drawn: defaultID, notice: .unknownVariant(selection))
        }
        if let family = spec.requires, !capabilities.families.contains(family) {
            return MaterialVariantResolution(drawn: defaultID, notice: .unsupported(variant: selection, requires: family))
        }
        if let built, !built.contains(selection) {
            return MaterialVariantResolution(drawn: defaultID, notice: .pipelineUnavailable(selection))
        }
        return MaterialVariantResolution(drawn: selection)
    }
}

extension MaterialDefinition {
    /// The resolution of `selection` for this material on a GPU with `capabilities` (before any pipeline is built).
    public func resolveVariant(_ selection: String?, capabilities: MaterialGPUCapabilities) -> MaterialVariantResolution {
        MaterialVariantResolution.resolve(selection: selection, variants: variants, capabilities: capabilities, built: nil)
    }
}
