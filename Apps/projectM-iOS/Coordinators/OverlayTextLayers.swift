// OverlayTextLayers.swift — the text overlays' layers on the compositor visuals (MED-011-R6, shared with MED-012-R7).
//
// * `OverlayTextLayers` holds each compositor visual's overlay `TextLayerSource` weakly (the compositor owns it; a
//   released visual drops out), pushes a new spec to every live layer and sums their shown frames (DEBUG probes).
// * `Compositor.attachOverlay(_:kind:)` adds the layer as the top entry of the applied stack, like MED-010's
//   `attachLogo`: the clock first, then the countdown above it. Kept entries keep their layers and state.
import Compositor
import Foundation
import Metal
import TextLayer

@MainActor
final class OverlayTextLayers {
    let kind: LayerKind
    private var layers: [WeakTextLayer] = []

    init(kind: LayerKind) { self.kind = kind }

    /// Gives `compositor` its overlay layer (named after the kind) showing `spec`, on top of its stack; nil when it
    /// has one or the stack refused it.
    func attach(to compositor: Compositor, spec: TextOverlaySpec) -> TextLayerSource? {
        let layer = TextLayerSource(device: compositor.device, name: kind.identifier)
        layer.spec = spec
        guard compositor.attachOverlay(layer, kind: kind) else { return nil }
        layers = layers.filter { (box: WeakTextLayer) -> Bool in box.layer != nil } + [WeakTextLayer(layer)]
        return layer
    }

    func push(_ spec: TextOverlaySpec) {
        for layer in live { layer.spec = spec }
    }

    var live: [TextLayerSource] { layers.compactMap { (box: WeakTextLayer) -> TextLayerSource? in box.layer } }

    var isEmpty: Bool { live.isEmpty }

    /// Frames in which any live layer showed its text.
    var framesShown: Int { live.reduce(0) { (sum: Int, layer: TextLayerSource) -> Int in sum + layer.framesShown } }
}

/// A weakly held overlay layer (the compositor owns it).
private struct WeakTextLayer {
    weak var layer: TextLayerSource?
    init(_ layer: TextLayerSource) { self.layer = layer }
}

extension Compositor {
    /// Adds `layer` as the top `kind` entry of the applied stack. False when no stack is applied, the kind is already
    /// there or the stack refuses it.
    @discardableResult
    func attachOverlay(_ layer: TextLayerSource, kind: LayerKind) -> Bool {
        guard var stack = appliedStack,
              !stack.entries.contains(where: { (entry: LayerStackEntry) -> Bool in entry.descriptor.kind == kind }) else { return false }
        do {
            try stack.add(LayerDescriptor(kind: kind))
            try apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
                guard entry.descriptor.kind == kind else { throw .notReady }
                return layer
            }
        } catch {
            return false
        }
        return true
    }

    /// MED-011-R6: the clock's layer (the overlay attach for `.clock`).
    @discardableResult
    func attachClock(_ layer: TextLayerSource) -> Bool { attachOverlay(layer, kind: .clock) }
}
