// CameraLayerKind.swift — the camera's layer-stack kind (CMP-002-R6; spec Clarifications). CPU, so
// it builds on Linux.
import Compositor

extension LayerKind {
    /// The rear camera layer. One per stack: a stack never asks for a second capture session, so the
    /// privacy indicator and Stop camera (CAM-012) always concern exactly one camera.
    public static let camera = LayerKind("camera", maximumInstances: 1)
}
