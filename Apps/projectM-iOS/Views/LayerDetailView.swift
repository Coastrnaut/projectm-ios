// LayerDetailView.swift — one layer's parameters (CMP-015-R2, R3, R6, R7, R9, R10; contracts/
// layer-inspector.md L1-L3).
//
// * Editable layers read and write the inspector's live composite for their kind; read-only layers show
//   the scene's saved values and the reason (footer).
// * Sections: Appearance (opacity, blend), Placement (position, scale, rotation), Fit (photo and video),
//   Mask, Gradient (CMP-008, LayerGradientSection), Layer (group, own MOD-001 values, Reset Layer). Every parameter has a "?" help button. Read-only
//   parameters show a read-out (`layerValue.<parameter>`); editable sliders a visible read-out over an
//   ACC-005 slider (`layerControl.<parameter>`), editable choices their picker or toggle.
// * Pickers record one undo step per choice; sliders one per drag (LayerParameterSlider).
// Bodies stay small (Xcode 26 type-check budget): each section is its own property.
import SceneFormat
import SwiftUI

struct LayerDetailView: View {
    let row: LayerInspectorRow
    let layers: LayerInspectorCoordinator
    let history: SceneHistoryCoordinator

    private var kind: String { row.kind }
    private var composite: SceneComposite { row.isEditable ? layers.composite(for: kind) : row.composite }
    private var showsFit: Bool { kind == "photo" || kind == "video" }

    var body: some View {
        List {
            appearanceSection
            placementSection
            if showsFit { fitSection }
            maskSection
            LayerGradientSection(row: row, layers: layers)   // CMP-008
            layerSection
        }
        .navigationTitle(row.title)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SceneUndoRedoButtons(history: history) } }
        .accessibilityIdentifier("layerDetail")
    }

    // MARK: Sections

    private var appearanceSection: some View {
        Section {
            parameter(.opacity)
            choice(.blendMode) { blendPicker }
        } header: {
            Text("Appearance")
        } footer: {
            if let reason = row.readOnlyReason { Text(reason).accessibilityIdentifier("layerReadOnlyReason") }
        }
    }

    private var placementSection: some View {
        Section("Placement") {
            parameter(.positionX)
            parameter(.positionY)
            parameter(.scale)
            parameter(.rotation)
        }
    }

    private var fitSection: some View {
        Section("Fit") {
            choice(.fitMode) { fitPicker }
            parameter(.fitAnchorX)
            parameter(.fitAnchorY)
        }
    }

    private var maskSection: some View {
        Section("Mask") {
            choice(.maskShape) { maskPicker }
            if LayerCompositeEdit.knownMask(composite) != nil { maskDetails }
        }
    }

    @ViewBuilder private var maskDetails: some View {
        parameter(.maskSize)
        if case .rectangle? = LayerCompositeEdit.knownMask(composite)?.shape { parameter(.maskCornerRadius) }
        parameter(.maskFeather)
        choice(.maskInverted) { invertToggle }
    }

    private var layerSection: some View {
        Section("Layer") {
            LayerParameterHeader(parameter: .group, value: row.groupName ?? "None")
            ForEach(row.ownValues) { (own: LayerOwnValue) in ownValueRow(own) }
            if row.isEditable { resetButton }
        }
    }

    // MARK: Rows and controls

    @ViewBuilder private func parameter(_ parameter: LayerInspectorParameter) -> some View {
        if row.isEditable {
            LayerParameterSlider(parameter: parameter, kind: kind, layers: layers)
        } else {
            LayerParameterHeader(parameter: parameter, value: LayerCompositeEdit.text(parameter, of: composite))
        }
    }

    /// An editable choice: its control (which shows the title and value) and the help button; read-only:
    /// the header read-out.
    @ViewBuilder private func choice(_ parameter: LayerInspectorParameter, @ViewBuilder control: () -> some View) -> some View {
        if row.isEditable {
            HStack(spacing: 8) {
                control()
                LayerHelpButton(parameter: parameter)
            }
        } else {
            LayerParameterHeader(parameter: parameter, value: LayerCompositeEdit.text(parameter, of: composite))
        }
    }

    private func ownValueRow(_ own: LayerOwnValue) -> some View {
        LabeledContent(own.title, value: own.value)
            .accessibilityIdentifier("layerOwnValue.\(own.id)")
    }

    private var blendPicker: some View {
        Picker(LayerInspectorParameter.blendMode.title, selection: blendBinding) {
            ForEach(LayerCompositeEdit.blendTitles, id: \.name) { (entry: (name: String, title: String)) in
                Text(entry.title).tag(entry.name)
            }
            if LayerCompositeEdit.blendTitles.allSatisfy({ (e: (name: String, title: String)) -> Bool in e.name != composite.blendMode }) {
                Text(LayerCompositeEdit.blendTitle(composite.blendMode)).tag(composite.blendMode)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("layerControl.blendMode")
    }

    private var blendBinding: Binding<String> {
        Binding<String>(get: { () -> String in composite.blendMode },
                        set: { (name: String) -> Void in layers.setBlend(name, kind: kind) })
    }

    private var fitPicker: some View {
        Picker(LayerInspectorParameter.fitMode.title, selection: fitBinding) {
            Text("Default").tag(String?.none)
            ForEach(LayerCompositeEdit.fitTitles, id: \.name) { (entry: (name: String, title: String)) in
                Text(entry.title).tag(String?.some(entry.name))
            }
            if let name = composite.fit?.mode, LayerFitModeNames.isUnknown(name) {
                Text(LayerCompositeEdit.fitTitle(name)).tag(String?.some(name))
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("layerControl.fitMode")
    }

    private var fitBinding: Binding<String?> {
        Binding<String?>(get: { () -> String? in composite.fit?.mode },
                         set: { (name: String?) -> Void in layers.setFit(name, kind: kind) })
    }

    private var maskPicker: some View {
        Picker(LayerInspectorParameter.maskShape.title, selection: maskBinding) {
            Text("None").tag(String?.none)
            ForEach(LayerCompositeEdit.maskTitles, id: \.name) { (entry: (name: String, title: String)) in
                Text(entry.title).tag(String?.some(entry.name))
            }
            if let name = composite.mask?.shape, !["ellipse", "rectangle"].contains(name) {
                Text(LayerCompositeEdit.maskTitle(composite)).tag(String?.some(name))
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("layerControl.maskShape")
    }

    private var maskBinding: Binding<String?> {
        Binding<String?>(get: { () -> String? in composite.mask?.shape },
                         set: { (name: String?) -> Void in layers.setMask(name, kind: kind) })
    }

    private var invertToggle: some View {
        Toggle(LayerInspectorParameter.maskInverted.title, isOn: invertBinding)
            .accessibilityIdentifier("layerControl.maskInverted")
    }

    private var invertBinding: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in LayerCompositeEdit.value(.maskInverted, of: composite) > 0.5 },
                      set: { (on: Bool) -> Void in layers.setValue(.maskInverted, on ? 1 : 0, kind: kind) })
    }

    private var resetButton: some View {
        Button("Reset Layer") { layers.reset(kind: kind) }
            .disabled(composite == SceneComposite())
            .accessibilityIdentifier("layerReset")
    }
}

/// Fit mode names this version draws.
enum LayerFitModeNames {
    static func isUnknown(_ name: String) -> Bool {
        LayerCompositeEdit.fitTitles.allSatisfy { (e: (name: String, title: String)) -> Bool in e.name != name }
    }
}
