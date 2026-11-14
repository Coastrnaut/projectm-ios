// MaterialInspectorModel.swift — a material layer's inspector controls and their texts (SHD-003-R7, R8;
// specs/218-shd-003-shader-parameter-metadata, contracts/shader-parameter-metadata.md M4, M5).
//
// * `controls(for:parameters:)`: the layer's material (exact catalog ID only) → the generic controls the
//   ShaderParameterMetadata builder makes from its validated metadata, showing the scene's values (or the
//   defaults). Nothing here names a particular material or parameter.
// * `display(_:)` / `spoken(_:)`: UIX-003's text of the control's value (one formatter for both inspectors).
// * `identifier(_:)`: `materialControl.<parameter ID>`.
// * `variantChoice(for:stored:capabilities:)` (SHD-004-R8): the material's variants for the "Variant" picker
//   (nil for a material with one variant), the stored choice and a note when it can't be drawn on this GPU.
// Every intermediate is a named, typed value (CI's type-check budget).
import Foundation
import Metal
import ParameterGraph
import ProceduralMaterials
import SceneFormat
import ShaderParameterMetadata

/// SHD-004: what the "Variant" picker shows.
struct MaterialVariantChoice: Equatable, Sendable {
    /// In metadata order, default first.
    let options: [ShaderVariantSpec]
    /// The stored variant, or the default when none (or an unknown one) is stored.
    let selectedID: String
    /// Why the stored variant isn't drawn here (nil when it is).
    let note: String?

    static let title = "Variant"
}

enum MaterialInspectorModel {
    static let sectionTitle = "Material settings"

    /// The controls of a `material` layer, in metadata order; empty for other contents or unknown IDs.
    static func controls(for content: SceneLayerContent, parameters: [ParameterID: ParameterValue]) -> [ShaderParameterControl] {
        guard case let .material(id) = content, let definition = ProceduralMaterialCatalog.material(withID: id) else { return [] }
        return definition.controls(values: parameters)
    }

    /// SHD-004: the GPU families of this device, read once (none without a Metal device).
    static let deviceCapabilities: MaterialGPUCapabilities = {
        guard let device: MTLDevice = MTLCreateSystemDefaultDevice() else { return MaterialGPUCapabilities.none }
        return MaterialGPUCapabilities(device: device)
    }()

    /// SHD-004-R8: the "Variant" picker of a material layer, or nil (other contents, unknown IDs, one variant).
    static func variantChoice(for content: SceneLayerContent, stored: String?,
                              capabilities: MaterialGPUCapabilities = deviceCapabilities) -> MaterialVariantChoice? {
        guard case let .material(id) = content, let definition = ProceduralMaterialCatalog.material(withID: id),
              definition.variants.count > 1 else { return nil }
        let resolution: MaterialVariantResolution = definition.resolveVariant(stored, capabilities: capabilities)
        let listed: Bool = stored.map { (s: String) -> Bool in definition.variant(s) != nil } ?? false
        let selected: String = listed ? (stored ?? definition.defaultVariantID) : definition.defaultVariantID
        return MaterialVariantChoice(options: definition.variants, selectedID: selected, note: resolution.notice?.message)
    }

    static func identifier(_ control: ShaderParameterControl) -> String { "materialControl." + control.id.rawValue }

    /// The visible value ("45%", "0.12/s", "Linear", "On").
    static func display(_ control: ShaderParameterControl) -> String {
        ParameterValueText.display(control.value, descriptor: control.descriptor)
    }

    /// The VoiceOver value: a slider's is what its ACC-005 element speaks ("45 percent", "0.12"); every other
    /// control's is UIX-003's spoken text ("3", "Linear", "On").
    static func spoken(_ control: ShaderParameterControl) -> String {
        if let spec = sliderSpec(control), let number = number(control) {
            return SpokenValueFormatter.text(number, unit: spec.unit)
        }
        return ParameterValueText.spoken(control.value, descriptor: control.descriptor)
    }

    /// The ACC-005 spec of a slider (nil for other controls): label, range, step and spoken unit from the metadata.
    static func sliderSpec(_ control: ShaderParameterControl) -> AccessibleParameterSpec? {
        guard control.kind == .slider, let range = control.range, let step = control.step else { return nil }
        let unit: SpokenUnit = ParameterValueText.spokenUnit(control.unit, step: step)
        return AccessibleParameterSpec(id: identifier(control), label: control.label, range: range, step: step, unit: unit)
    }

    /// A slider or stepper's number (nil for other controls).
    static func number(_ control: ShaderParameterControl) -> Double? { control.value.numericValue }

    /// A picker's selected case ID.
    static func caseID(_ control: ShaderParameterControl) -> String { control.value.enumCaseID ?? "" }

    /// A toggle's state.
    static func isOn(_ control: ShaderParameterControl) -> Bool { control.value.boolValue ?? false }

    /// A color well's color (the value's components).
    static func color(_ control: ShaderParameterControl) -> ParameterColor {
        control.value.colorValue ?? ParameterColor(red: 0, green: 0, blue: 0)
    }
}
