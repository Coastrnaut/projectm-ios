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
    /// Writes a new value; nil while the layer is read-only (the controls are disabled).
    var write: (@MainActor (ParameterID, ParameterValue) -> Void)? = nil

    var body: some View {
        if !controls.isEmpty {
            Section {
                ForEach(controls) { (control: ShaderParameterControl) in
                    MaterialParameterControlView(control: control, write: write)
                }
            } header: {
                // The identifier sits on the header only: on the Section it would replace every control's.
                Text(MaterialInspectorModel.sectionTitle).accessibilityIdentifier("materialSettings")
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
                Slider(value: Binding<Double>(get: target.get, set: target.set), in: spec.range, step: spec.step)
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
