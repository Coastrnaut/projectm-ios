// LayerInspectorControls.swift — the layer inspector's building blocks (CMP-015-R7, R10; contracts/
// layer-inspector.md L1, L2).
//
// * `LayerParameterHeader`: a parameter's title and shown value as one accessibility element
//   (`layerValue.<parameter>`), side by side or stacked at accessibility text sizes, with its help button.
// * `LayerHelpButton`: "?" opens the parameter's entry from `LayerInspectorHelp` in a popover.
// * `LayerParameterSlider`: a labelled slider; releasing it ends the history step (one drag = one undo
//   step); VoiceOver increment and decrement move by the parameter's fixed step, each its own step.
//   ACC-005's shared `.accessibleParameter(...)` helper was not in this base: this is the same pattern,
//   left for ACC-005 to adopt.
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
    }
}

struct LayerParameterSlider: View {
    let parameter: LayerInspectorParameter
    let kind: String
    let layers: LayerInspectorCoordinator

    private var composite: SceneCompositeBox { SceneCompositeBox(layers.composite(for: kind)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LayerParameterHeader(parameter: parameter, value: composite.text(parameter))
            slider
        }
    }

    private var binding: Binding<Double> {
        Binding<Double>(get: { () -> Double in composite.value(parameter) },
                        set: { (v: Double) -> Void in layers.setValue(parameter, v, kind: kind) })
    }

    private var slider: some View {
        Slider(value: binding, in: LayerCompositeEdit.range(parameter)) { (editing: Bool) in
            if !editing { layers.endEdit() }   // SCN-010-R4: a drag is one step
        }
        .accessibilityLabel(parameter.title)
        .accessibilityValue(composite.text(parameter))
        .accessibilityIdentifier("layerControl.\(parameter.rawValue)")
        .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) in adjust(direction) }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let step: Double = LayerCompositeEdit.step(parameter)
        let range: ClosedRange<Double> = LayerCompositeEdit.range(parameter)
        let current: Double = composite.value(parameter)
        let delta: Double = direction == .increment ? step : (direction == .decrement ? -step : 0)
        let next: Double = min(max(current + delta, range.lowerBound), range.upperBound)
        layers.setValue(parameter, next, kind: kind)
        layers.endEdit()   // each VoiceOver step is its own undo step
    }
}

/// A saved composite with the inspector's read helpers (keeps call sites short).
struct SceneCompositeBox {
    let composite: SceneComposite

    init(_ composite: SceneComposite) { self.composite = composite }

    func value(_ parameter: LayerInspectorParameter) -> Double { LayerCompositeEdit.value(parameter, of: composite) }
    func text(_ parameter: LayerInspectorParameter) -> String { LayerCompositeEdit.text(parameter, of: composite) }
}
