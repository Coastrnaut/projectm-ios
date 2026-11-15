// MaterialParametersSection.swift — a material layer's "Material settings", one control per metadata parameter
// (SHD-003-R8; contracts/shader-parameter-metadata.md M5).
//
// Generic: the control's kind picks the SwiftUI control (slider, stepper, picker, toggle, color well); labels,
// ranges, steps, options and values all come from the validated metadata via `row.materialControls`. No code
// here names a material. This version keeps material layers in scenes but does not draw them, so the controls
// show the scene's values and are disabled (the Appearance footer gives the reason); `write` is nil then.
// Every control is one accessibility element: label, value and identifier `materialControl.<parameter ID>`.
// Bodies stay small (Xcode 26 type-check budget).
import ParameterGraph
import ShaderParameterMetadata
import SwiftUI

struct MaterialParametersSection: View {
    let controls: [ShaderParameterControl]
    /// SHD-004-R8: the variant picker, first in the section (nil for a material with one variant).
    var variant: MaterialVariantChoice? = nil
    /// Writes a new value; nil while the layer is read-only (the controls are disabled).
    var write: (@MainActor (ParameterID, ParameterValue) -> Void)? = nil

    var body: some View {
        if !controls.isEmpty {
            Section {
                if let variant { MaterialVariantPicker(choice: variant, enabled: write != nil) }
                ForEach(controls) { (control: ShaderParameterControl) in
                    MaterialParameterControlView(control: control, write: write)
                }
            } header: {
                // The identifier sits on the header only: on the Section it would replace every control's.
                Text(MaterialInspectorModel.sectionTitle).accessibilityIdentifier("materialSettings")
            } footer: {
                if let note = variant?.note { Text(note).accessibilityIdentifier("materialVariantNote") }
            }
        }
    }
}

struct MaterialParameterControlView: View {
    let control: ShaderParameterControl
    let write: (@MainActor (ParameterID, ParameterValue) -> Void)?
    @Environment(\.self) private var environment

    /// A picked color as linear RGBA (the metadata's color space), opaque.
    static func linear(_ color: Color, in environment: EnvironmentValues) -> ParameterColor {
        let resolved: Color.Resolved = color.resolve(in: environment)
        return ParameterColor(red: Double(resolved.linearRed), green: Double(resolved.linearGreen), blue: Double(resolved.linearBlue)).clamped
    }

    var body: some View {
        content
            .disabled(write == nil)
    }

    @ViewBuilder private var content: some View {
        switch control.kind {
        case .slider: slider
        case .stepper: stepper
        case .picker: picker
        case .toggle: toggle
        case .color: colorWell
        }
    }

    private func send(_ value: ParameterValue) { write?(control.id, value) }

    private var header: some View {
        HStack {
            Text(control.label)
            Spacer(minLength: 8)
            Text(MaterialInspectorModel.display(control)).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var slider: some View {
        if let spec = MaterialInspectorModel.sliderSpec(control) {
            let target = ParameterTarget(get: { () -> Double in MaterialInspectorModel.number(control) ?? spec.range.lowerBound },
                                         set: { (v: Double) -> Void in send(.continuous(v)) })
            VStack(alignment: .leading, spacing: 2) {
                header
                // Closure literals, not `target.get`/`target.set` passed as values: converting the @MainActor
                // function values to Binding's closures crashed Xcode 26.6's IR generation (CI run 43673306095).
                Slider(value: Binding<Double>(get: { () -> Double in target.get() },
                                              set: { (v: Double) -> Void in target.set(v) }),
                       in: spec.range, step: spec.step)
                    .accessibleParameter(spec, target: target)
            }
        }
    }

    private var stepper: some View {
        let number: Double = MaterialInspectorModel.number(control) ?? 0
        let range: ClosedRange<Double> = control.range ?? 0...0
        let step: Double = control.step ?? 1
        let binding = Binding<Double>(get: { () -> Double in number },
                                      set: { (v: Double) -> Void in send(.integer(Int(v.rounded()))) })
        return Stepper(value: binding, in: range, step: step) { header }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(control.label)
            .accessibilityValue(MaterialInspectorModel.spoken(control))
            .accessibilityIdentifier(MaterialInspectorModel.identifier(control))
            .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) -> Void in   // SHD-006: swipe to step
                let next: Double = direction == .increment ? number + step : number - step
                guard write != nil, range.contains(next) else { return }
                send(.integer(Int(next.rounded())))
            }
    }

    private var picker: some View {
        let binding = Binding<String>(get: { () -> String in MaterialInspectorModel.caseID(control) },
                                      set: { (id: String) -> Void in send(.enumeration(id)) })
        return Picker(control.label, selection: binding) {
            ForEach(control.options, id: \.id) { (option: ParameterEnumCase) in
                Text(option.displayName).tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel(control.label)
        .accessibilityValue(MaterialInspectorModel.spoken(control))
        .accessibilityIdentifier(MaterialInspectorModel.identifier(control))
    }

    private var toggle: some View {
        let binding = Binding<Bool>(get: { () -> Bool in MaterialInspectorModel.isOn(control) },
                                    set: { (on: Bool) -> Void in send(.boolean(on)) })
        return Toggle(control.label, isOn: binding)
            .accessibilityIdentifier(MaterialInspectorModel.identifier(control))
    }

    private var colorWell: some View {
        let c: ParameterColor = MaterialInspectorModel.color(control)
        let shown = Color(.sRGBLinear, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        let environment: EnvironmentValues = self.environment
        let binding = Binding<Color>(get: { () -> Color in shown },
                                     set: { (color: Color) -> Void in send(.color(MaterialParameterControlView.linear(color, in: environment))) })
        return ColorPicker(control.label, selection: binding, supportsOpacity: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(control.label)
            .accessibilityValue(MaterialInspectorModel.spoken(control))
            .accessibilityIdentifier(MaterialInspectorModel.identifier(control))
    }
}

/// SHD-004-R8: the material's variants from its metadata; read-only while material layers are not drawn.
struct MaterialVariantPicker: View {
    let choice: MaterialVariantChoice
    let enabled: Bool

    var body: some View {
        let binding = Binding<String>(get: { () -> String in choice.selectedID }, set: { (_: String) -> Void in })
        return Picker(MaterialVariantChoice.title, selection: binding) {
            ForEach(choice.options, id: \.id) { (option: ShaderVariantSpec) in
                Text(option.label).tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .disabled(!enabled)
        .accessibilityIdentifier("materialVariant")   // the menu picker speaks its title and the selected label
    }
}
