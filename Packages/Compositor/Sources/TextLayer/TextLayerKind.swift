// TextLayerKind.swift — the text overlay's layer-stack kind (MED-009; CMP-002-R6). CPU, so it builds
// on Linux.
import Compositor

extension LayerKind {
    /// A styled message (MED-009). One per stack for now; MED-011 (clock) and MED-012 (countdown)
    /// feed the same layer changing strings.
    public static let text = LayerKind("text", maximumInstances: 1)
}
