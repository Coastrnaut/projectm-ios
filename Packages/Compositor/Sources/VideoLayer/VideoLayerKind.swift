// VideoLayerKind.swift — the video's layer-stack kind (MED-002; CMP-002-R6). CPU, so it builds on
// Linux.
import Compositor

extension LayerKind {
    /// An imported video. One per stack in MED-002 (one stored video).
    public static let video = LayerKind("video", maximumInstances: 1)
}
