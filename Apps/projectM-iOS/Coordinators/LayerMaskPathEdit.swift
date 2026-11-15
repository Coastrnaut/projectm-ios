// LayerMaskPathEdit.swift — SHD-008-T11 (specs/279-shd-008-vector-path-editor, SHD-008-R5, R9): the layer inspector's
// path mask. "Path" in the mask picker gives the layer `VectorPath.default` (LayerCompositeEdit.settingMask); the
// "Edit path" row opens the path editor, and each path it commits replaces the mask's path, keeping the mask's
// placement, feather and invert (one scene-history step per committed path).
import Compositor
import SceneFormat
import SwiftUI
import VisualGenerators

enum LayerMaskPathEdit {
    /// The layer's path when its mask is a known path mask.
    static func path(of composite: SceneComposite) -> VectorPath? {
        guard case let .path(path)? = LayerCompositeEdit.knownMask(composite)?.shape else { return nil }
        return path
    }

    /// The composite with its mask's path replaced (a non-path or unknown mask becomes a path mask with its
    /// placement, feather and invert kept; no mask gets a default placement).
    static func settingPath(_ path: VectorPath, on composite: SceneComposite) -> SceneComposite {
        let current: LayerMask? = LayerCompositeEdit.knownMask(composite)
        let made: LayerMask? = try? LayerMask(shape: .path(path), transform: current?.transform ?? .identity,
                                              feather: current?.feather ?? 0, inverted: current?.inverted ?? false)
        var result: SceneComposite = composite
        if let made { result.mask = .known(made) }
        return result
    }
}

/// "Edit path" in the layer detail's Mask section.
struct LayerMaskPathLink: View {
    let path: VectorPath
    let row: LayerInspectorRow
    let layers: LayerInspectorCoordinator

    var body: some View {
        if row.isEditable {
            NavigationLink { editor } label: { LabeledContent("Edit path", value: "\(path.points.count) points") }
                .accessibilityIdentifier("layerControl.maskPathEdit")
        } else {
            LabeledContent("Path", value: "\(path.points.count) points")
        }
    }

    private var editor: some View {
        let kind: String = row.kind
        let coordinator: LayerInspectorCoordinator = layers
        return VectorPathEditorView(title: "Mask Path", path: path) { (made: VectorPath) -> Void in
            coordinator.setMaskPath(made, kind: kind)
        }
    }
}
