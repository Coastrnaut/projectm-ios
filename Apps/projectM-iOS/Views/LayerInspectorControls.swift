// LayerInspectorControls.swift — the layer inspector's building blocks (CMP-015-R7, R10; contracts/
// layer-inspector.md L1, L2).
//
// * `LayerParameterHeader`: a parameter's title and shown value as one accessibility element
//   (`layerValue.<parameter>`), side by side or stacked at accessibility text sizes, with its help button.
// * `LayerHelpButton`: "?" opens the parameter's entry from `LayerInspectorHelp` in a popover.
// * `LayerParameterSlider`: a slider; releasing it ends the history step (one drag = one undo step).
//   VoiceOver uses ACC-005's `.accessibleParameter` (one element: label, spoken value with its unit,
//   identifier `layerControl.<parameter>`, swipe by the parameter's step, each swipe its own undo step).
// Bodies stay small (Xcode 26 type-check budget): each piece is its own view.
import SceneFormat
import SwiftUI

struct LayerHelpButton: View {
    let parameter: LayerInspectorParameter
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: { Image(systemName: "questionmark.circle") }
            .buttonStyle(.borderless)
            .accessibilityLabel("Help for \(parameter.title)")
            .accessibilityIdentifier("layerHelp.\(parameter.rawValue)")
            .popover(isPresented: $shown) { popoverText }
    }

    private var popoverText: some View {
        Text(parameter.help)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(idealWidth: 280)
            .padding()
            .presentationCompactAdaptation(.popover)
            .accessibilityIdentifier("layerHelpText")
    }
}

struct LayerParameterHeader: View {
    let parameter: LayerInspectorParameter
    let value: String
    /// False when a control below carries the title and value for VoiceOver (no duplicate element).
    var isAccessibilityElement = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            readout
            LayerHelpButton(parameter: parameter)
        }
    }

    private var readout: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(parameter.title)
                Spacer(minLength: 8)
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(parameter.title)
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parameter.title)
        .accessibilityValue(value)
        .accessibilityIdentifier("layerValue.\(parameter.rawValue)")
        .accessibilityHidden(!isAccessibilityElement)
    }
}

struct LayerParameterSlider: View {
    let parameter: LayerInspectorParameter
    let kind: String
    let layers: LayerInspectorCoordinator

    private var composite: SceneComposite { layers.composite(for: kind) }
    private var spec: AccessibleParameterSpec { LayerParameterSpecs.spec(parameter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LayerParameterHeader(parameter: parameter, value: LayerCompositeEdit.text(parameter, of: composite), isAccessibilityElement: false)
            slider
        }
    }

    private var target: ParameterTarget { LayerParameterSpecs.target(parameter, kind: kind, layers: layers) }

    private var binding: Binding<Double> {
        let target: ParameterTarget = self.target
        return Binding<Double>(get: { () -> Double in target.get() }, set: { (v: Double) -> Void in target.set(v) })
    }

    private var slider: some View {
        Slider(value: binding, in: spec.range) { (editing: Bool) in
            if !editing { layers.endEdit() }   // SCN-010-R4: a drag is one step
        }
        .accessibleParameter(spec, target: target, didStep: { [layers] () -> Void in layers.endEdit() })   // ACC-005: each swipe is one step
    }
}

/// ACC-005 specs and targets of the inspector's sliders (identifier `layerControl.<parameter>`).
@MainActor
enum LayerParameterSpecs {
    static func spec(_ parameter: LayerInspectorParameter) -> AccessibleParameterSpec {
        AccessibleParameterSpec(id: "layerControl.\(parameter.rawValue)", label: parameter.title,
                                range: LayerCompositeEdit.range(parameter), step: LayerCompositeEdit.step(parameter),
                                unit: unit(parameter))
    }

    static func unit(_ parameter: LayerInspectorParameter) -> SpokenUnit {
        switch parameter {
        case .opacity: .percent(decimals: 0)
        case .rotation, .gradientAngle: .degrees
        case .scale: .multiplier
        default: .number(decimals: 2)
        }
    }

    /// Get and set over the inspector's live composite (the view's own write path).
    static func target(_ parameter: LayerInspectorParameter, kind: String, layers: LayerInspectorCoordinator) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in LayerCompositeEdit.value(parameter, of: layers.composite(for: kind)) },
                        set: { (value: Double) -> Void in layers.setValue(parameter, value, kind: kind) })
    }
}
