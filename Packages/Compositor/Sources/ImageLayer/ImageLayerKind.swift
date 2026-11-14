// ImageLayerKind.swift — the photo's layer-stack kind (MED-001; CMP-002-R6). CPU, so it builds on
// Linux.
import Compositor

extension LayerKind {
    /// An imported still image. One per stack in MED-001 (one stored photo); MED-006 (slideshow) and
    /// MED-010 (logo) may lift the limit.
    public static let photo = LayerKind("photo", maximumInstances: 1)
}

extension LayerKind {
    /// MED-010: the logo overlay, the top layer of a compositor visual (one per stack).
    public static let logo = LayerKind("logo", maximumInstances: 1)
}
