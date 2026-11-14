// LayerColorKeySection.swift — the layer inspector's colour key editor (CMP-010-R10; contracts/color-key.md C4 in
// specs/230-cmp-010-color-key).
//
// * Editable layers: the Color Key toggle (`layerControl.colorKey`); when on, the system colour picker "Key Color"
//   (`layerControl.colorKeyColor`, no opacity) and Color Tolerance (0…1) and Color Feather (0…0.5) as ACC-005 sliders
//   (`LayerParameterSlider`, `layerControl.colorTolerance|colorFeather`).
// * Read-only layers: the same values as read-outs (`layerValue.<parameter>`; the colour as #RRGGBB).
// * The picked colour is read as extended sRGB through `UIColor` and stored clamped and rounded
//   (`LayerColorKeyEdit.settingColor`); a drag is one undo step, picker updates coalesce in the history.
// Bodies stay small (Xcode 26 type-check budget): each piece is its own property.
import Compositor
import SceneFormat
import SwiftUI
import UIKit

struct LayerColorKeySection: View {
    let row: LayerInspectorRow
    let layers: LayerInspectorCoordinator

    private var kind: String { row.kind }
    private var composite: SceneComposite { row.isEditable ? layers.composite(for: kind) : row.composite }
    private var isOn: Bool { composite.colorKey != nil }

    var body: some View {
        Section("Color Key") {
            if row.isEditable { editableRows } else { readOnlyRows }
        }
    }

    @ViewBuilder private var readOnlyRows: some View {
        LayerParameterHeader(parameter: .colorKey, value: LayerCompositeEdit.text(.colorKey, of: composite))
        if isOn {
            ForEach([LayerInspectorParameter.colorKeyColor, .colorTolerance, .colorFeather], id: \.self) { (p: LayerInspectorParameter) in
                LayerParameterHeader(parameter: p, value: LayerCompositeEdit.text(p, of: composite))
            }
        }
    }

    @ViewBuilder private var editableRows: some View {
        toggleRow
        if isOn {
            colorRow
            LayerParameterSlider(parameter: .colorTolerance, kind: kind, layers: layers)
            LayerParameterSlider(parameter: .colorFeather, kind: kind, layers: layers)
        }
    }

    private var toggleRow: some View {
        HStack(spacing: 8) {
            Toggle(LayerInspectorParameter.colorKey.title, isOn: toggleBinding)
                .accessibilityIdentifier("layerControl.colorKey")
            LayerHelpButton(parameter: .colorKey)
        }
    }

    private var colorRow: some View {
        HStack(spacing: 8) {
            ColorPicker(LayerInspectorParameter.colorKeyColor.title, selection: colorBinding, supportsOpacity: false)
                .accessibilityLabel(LayerInspectorParameter.colorKeyColor.title)
                .accessibilityValue(LayerCompositeEdit.text(.colorKeyColor, of: composite))
                .accessibilityIdentifier("layerControl.colorKeyColor")
            LayerHelpButton(parameter: .colorKeyColor)
        }
    }

    private var toggleBinding: Binding<Bool> {
        let layers: LayerInspectorCoordinator = self.layers
        let kind: String = self.kind
        return Binding<Bool>(get: { () -> Bool in LayerCompositeEdit.value(.colorKey, of: layers.composite(for: kind)) > 0.5 },
                             set: { (on: Bool) -> Void in layers.setValue(.colorKey, on ? 1 : 0, kind: kind) })
    }

    private var colorBinding: Binding<Color> {
        let layers: LayerInspectorCoordinator = self.layers
        let kind: String = self.kind
        return Binding<Color>(get: { () -> Color in Self.color(layers.composite(for: kind).colorKey ?? .greenKey) },
                              set: { (picked: Color) -> Void in Self.apply(picked, kind: kind, layers: layers) })
    }

    private static func color(_ k: LayerColorKey) -> Color {
        Color(.sRGB, red: k.red, green: k.green, blue: k.blue, opacity: 1)
    }

    /// Reads the picked colour in extended sRGB (opacity ignored) and stores it.
    private static func apply(_ picked: Color, kind: String, layers: LayerInspectorCoordinator) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard UIColor(picked).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
        layers.setColorKeyColor(red: Double(r), green: Double(g), blue: Double(b), kind: kind)
    }
}
