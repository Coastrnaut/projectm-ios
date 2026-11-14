// LayerLumaKeySection.swift — the layer inspector's luma key editor (CMP-009-R10; contracts/luma-key.md L2 in
// specs/220-cmp-009-luma-key).
//
// * Editable layers: the Luma Key toggle (`layerControl.lumaKey`); when on, Key Low, Key High (0…1) and Key Softness
//   (0…0.5) as ACC-005 sliders (`LayerParameterSlider`, `layerControl.lumaLow|lumaHigh|lumaSoftness`) and the Invert
//   Key toggle (`layerControl.lumaInverted`).
// * Read-only layers: the same values as read-outs (`layerValue.<parameter>`).
// * A drag is one undo step (the release ends the history's coalescing); each toggle is one step.
// Bodies stay small (Xcode 26 type-check budget): each piece is its own property.
import SceneFormat
import SwiftUI

struct LayerLumaKeySection: View {
    let row: LayerInspectorRow
    let layers: LayerInspectorCoordinator

    private var kind: String { row.kind }
    private var composite: SceneComposite { row.isEditable ? layers.composite(for: kind) : row.composite }
    private var isOn: Bool { composite.lumaKey != nil }

    var body: some View {
        Section("Luma Key") {
            if row.isEditable { editableRows } else { readOnlyRows }
        }
    }

    @ViewBuilder private var readOnlyRows: some View {
        LayerParameterHeader(parameter: .lumaKey, value: LayerCompositeEdit.text(.lumaKey, of: composite))
        if isOn {
            ForEach([LayerInspectorParameter.lumaLow, .lumaHigh, .lumaSoftness, .lumaInverted], id: \.self) { (p: LayerInspectorParameter) in
                LayerParameterHeader(parameter: p, value: LayerCompositeEdit.text(p, of: composite))
            }
        }
    }

    @ViewBuilder private var editableRows: some View {
        toggleRow(.lumaKey)
        if isOn {
            LayerParameterSlider(parameter: .lumaLow, kind: kind, layers: layers)
            LayerParameterSlider(parameter: .lumaHigh, kind: kind, layers: layers)
            LayerParameterSlider(parameter: .lumaSoftness, kind: kind, layers: layers)
            toggleRow(.lumaInverted)
        }
    }

    private func toggleRow(_ parameter: LayerInspectorParameter) -> some View {
        HStack(spacing: 8) {
            Toggle(parameter.title, isOn: binding(parameter))
                .accessibilityIdentifier("layerControl.\(parameter.rawValue)")
            LayerHelpButton(parameter: parameter)
        }
    }

    private func binding(_ parameter: LayerInspectorParameter) -> Binding<Bool> {
        let layers: LayerInspectorCoordinator = self.layers
        let kind: String = self.kind
        return Binding<Bool>(get: { () -> Bool in LayerCompositeEdit.value(parameter, of: layers.composite(for: kind)) > 0.5 },
                             set: { (on: Bool) -> Void in layers.setValue(parameter, on ? 1 : 0, kind: kind) })
    }
}
