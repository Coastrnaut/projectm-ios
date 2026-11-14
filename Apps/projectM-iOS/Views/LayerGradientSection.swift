// LayerGradientSection.swift — the layer inspector's gradient mask editor (CMP-008-R10; contracts/gradient-masks.md
// G4 in specs/207-cmp-008-gradient-masks).
//
// * Editable layers: a kind picker (`layerControl.gradientKind`: None, Linear, Radial), the Angle (linear) or Radius
//   (radial) slider, one row per stop with Position and Alpha sliders (ACC-005 `.accessibleParameter`, identifiers
//   `layerControl.gradientStop<n>.position` / `.alpha`, n 1-based in position order) and a Remove button
//   (`layerGradientRemoveStop<n>`, disabled at 2 stops), and Add Stop (`layerGradientAddStop`, disabled at 8).
// * Read-only layers: the kind and the stop count as read-outs.
// * A drag is one undo step (the release ends the history's coalescing); kind, add and remove are one step each.
// Bodies stay small (Xcode 26 type-check budget): each piece is its own property or view.
import Compositor
import SceneFormat
import SwiftUI

struct LayerGradientSection: View {
    let row: LayerInspectorRow
    let layers: LayerInspectorCoordinator

    private var kind: String { row.kind }
    private var composite: SceneComposite { row.isEditable ? layers.composite(for: kind) : row.composite }

    var body: some View {
        Section("Gradient") {
            if row.isEditable { editableRows } else { readOnlyRows }
        }
    }

    @ViewBuilder private var readOnlyRows: some View {
        LayerParameterHeader(parameter: .gradientKind, value: LayerGradientEdit.kindTitle(composite))
        if LayerGradientEdit.known(composite) != nil {
            LayerParameterHeader(parameter: .gradientStops, value: LayerGradientEdit.stopsText(composite))
        }
    }

    @ViewBuilder private var editableRows: some View {
        HStack(spacing: 8) {
            kindPicker
            LayerHelpButton(parameter: .gradientKind)
        }
        if let gradient = LayerGradientEdit.known(composite) {
            geometrySlider(gradient.kind)
            LayerParameterHeader(parameter: .gradientStops, value: LayerGradientEdit.stopsText(composite))
            ForEach(Array(gradient.stops.indices), id: \.self) { (index: Int) in
                LayerGradientStopRow(index: index, kind: kind, layers: layers)
            }
            addButton
        }
    }

    @ViewBuilder private func geometrySlider(_ gradientKind: LayerGradientKind) -> some View {
        switch gradientKind {
        case .linear: LayerParameterSlider(parameter: .gradientAngle, kind: kind, layers: layers)
        case .radial: LayerParameterSlider(parameter: .gradientRadius, kind: kind, layers: layers)
        }
    }

    private var kindPicker: some View {
        Picker(LayerInspectorParameter.gradientKind.title, selection: kindBinding) {
            Text("None").tag(String?.none)
            ForEach(LayerGradientEdit.kindTitles, id: \.name) { (entry: (name: String, title: String)) in
                Text(entry.title).tag(String?.some(entry.name))
            }
            if let name = LayerGradientEdit.kindName(composite), LayerGradientEdit.isUnknownKind(name) {
                Text(LayerGradientEdit.kindTitle(composite)).tag(String?.some(name))
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("layerControl.gradientKind")
    }

    private var kindBinding: Binding<String?> {
        let layers: LayerInspectorCoordinator = self.layers
        let kind: String = self.kind
        return Binding<String?>(get: { () -> String? in LayerGradientEdit.kindName(layers.composite(for: kind)) },
                                set: { (name: String?) -> Void in layers.setGradientKind(name, kind: kind) })
    }

    private var addButton: some View {
        Button("Add Stop") { layers.addGradientStop(kind: kind) }
            .disabled(!LayerGradientEdit.canAddStop(composite))
            .accessibilityIdentifier("layerGradientAddStop")
    }
}

/// One stop: its title and Remove button, then Position and Alpha sliders.
struct LayerGradientStopRow: View {
    let index: Int
    let kind: String
    let layers: LayerInspectorCoordinator

    private var number: Int { index + 1 }
    private var composite: SceneComposite { layers.composite(for: kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            LayerGradientStopSlider(index: index, field: .position, kind: kind, layers: layers)
            LayerGradientStopSlider(index: index, field: .alpha, kind: kind, layers: layers)
        }
    }

    private var header: some View {
        HStack {
            Text("Stop \(number)").font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            removeButton
        }
    }

    private var removeButton: some View {
        Button(role: .destructive) { layers.removeGradientStop(index, kind: kind) } label: {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .disabled(!LayerGradientEdit.canRemoveStop(composite))
        .accessibilityLabel("Remove Stop \(number)")
        .accessibilityIdentifier("layerGradientRemoveStop\(number)")
    }
}

/// A stop's Position or Alpha: a visible read-out over an ACC-005 slider; a drag or a VoiceOver swipe is one undo step.
struct LayerGradientStopSlider: View {
    let index: Int
    let field: LayerGradientField
    let kind: String
    let layers: LayerInspectorCoordinator

    private var title: String { "Stop \(index + 1) \(field.title)" }

    private var current: Double {
        let stops = LayerGradientEdit.stops(layers.composite(for: kind))
        guard stops.indices.contains(index) else { return 0 }
        return field == .position ? stops[index].position : stops[index].alpha
    }

    private var spec: AccessibleParameterSpec {
        AccessibleParameterSpec(id: "layerControl.gradientStop\(index + 1).\(field.rawValue)", label: title, range: 0...1,
                                step: LayerGradientEdit.stopStep, unit: .number(decimals: 2))
    }

    private var target: ParameterTarget {
        let layers: LayerInspectorCoordinator = self.layers
        let kind: String = self.kind
        let index: Int = self.index
        let field: LayerGradientField = self.field
        return ParameterTarget(get: { () -> Double in
            let stops = LayerGradientEdit.stops(layers.composite(for: kind))
            guard stops.indices.contains(index) else { return 0 }
            return field == .position ? stops[index].position : stops[index].alpha
        }, set: { (value: Double) -> Void in layers.setGradientStop(index, field, value, kind: kind) })
    }

    private var binding: Binding<Double> {
        let target: ParameterTarget = self.target
        return Binding<Double>(get: { () -> Double in target.get() }, set: { (v: Double) -> Void in target.set(v) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            readout
            slider
        }
    }

    private var readout: some View {
        HStack {
            Text(field.title)
            Spacer(minLength: 8)
            Text(LayerGradientEdit.stopText(current)).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
        .accessibilityHidden(true)   // the slider carries the label and value
    }

    private var slider: some View {
        Slider(value: binding, in: 0...1) { (editing: Bool) in
            if !editing { layers.endEdit() }   // SCN-010-R4: a drag is one step
        }
        .accessibleParameter(spec, target: target, didStep: { [layers] () -> Void in layers.endEdit() })
    }
}
