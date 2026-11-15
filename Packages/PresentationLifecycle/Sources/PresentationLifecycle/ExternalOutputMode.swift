// ExternalOutputMode.swift — OUT-006: what an external display output shows (spec
// specs/261-out-006-output-mirroring; research OUT-006-D1; contract contracts/output-mode.md C1).
//
// OUT-001 renders the one visual once and shows it on one target (the device or an external display).
// The mode decides which layer classes reach the external output:
//
//     target     mode          visual  sceneOverlay  interface
//     device     (any)         yes     yes           yes
//     external   Same scene    yes     yes           no
//     external   Clean output  yes     no            no
//
// The interface (controls, badges, HUD, guides, performance overlay, captions, notes) never reaches an
// external display. Pure Swift with no UIKit (tested on the host and Linux).

/// The user's choice for the external output (OUT-006-R1). Raw values are the stored names.
public enum ExternalOutputMode: String, Sendable, Equatable, CaseIterable {
    /// The scene as composed: the visual and its scene overlay layers (the default; OUT-001's behaviour).
    case sameScene
    /// The visual content only: scene overlay layers are left out while the visual is on the display.
    case clean

    public static let `default` = ExternalOutputMode.sameScene

    /// A stored value; absent or unknown reads Same scene (OUT-006-R7).
    public init(stored: String?) {
        self = stored.flatMap(ExternalOutputMode.init(rawValue:)) ?? .default
    }
}

/// What a layer is, for output routing (OUT-006 data model).
public enum OutputLayerClass: Sendable, Equatable, CaseIterable {
    /// The chosen visual and its own layers (MED-009's text included).
    case visual
    /// Layers drawn over the scene, such as MED-010's logo.
    case sceneOverlay
    /// The app's interface on the device's screen.
    case interface
}

public enum OutputLayerRouting {
    /// Whether layers of `layerClass` reach a target (`external` false: the device) under `mode`.
    public static func includes(_ layerClass: OutputLayerClass, external: Bool, mode: ExternalOutputMode) -> Bool {
        guard external else { return true }
        switch layerClass {
        case .visual: return true
        case .sceneOverlay: return mode == .sameScene
        case .interface: return false
        }
    }

    /// Whether scene overlays are drawn while the visual is shown on `target` (OUT-006-R2, R3).
    public static func routesSceneOverlays(target: VisualOutputTarget, mode: ExternalOutputMode) -> Bool {
        let external: Bool
        switch target {
        case .device: external = false
        case .external: external = true
        }
        return includes(.sceneOverlay, external: external, mode: mode)
    }
}
