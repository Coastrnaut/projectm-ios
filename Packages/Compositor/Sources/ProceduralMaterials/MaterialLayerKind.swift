// MaterialLayerKind.swift — the procedural material's layer-stack kind (SHD-001; CMP-002-R6;
// SCN-001 research SCN-001-D7). CPU, so it builds on Linux.
import Compositor

extension LayerKind {
    /// A curated procedural material (SHD-001). Which material a layer draws is its content (a scene
    /// stores `material.<name>`); its values are the material's MOD-001 parameters. No instance limit
    /// beyond the stack's.
    public static let material = LayerKind("material")
}
