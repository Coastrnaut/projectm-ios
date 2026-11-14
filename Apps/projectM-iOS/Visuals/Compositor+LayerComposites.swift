// Compositor+LayerComposites.swift — the layer inspector's live path (CMP-015-R4, R8; research
// CMP-015-D3; contracts/layer-inspector.md L3, L4).
//
// * `applyLayerComposites`: copies the applied stack, gives each entry its kind's saved composite (the
//   default when the kind has none) and applies it. Every ID is kept, so the factory is never called:
//   layer objects, their state and their cached pictures stay (CMP-013), placement changes only
//   re-composite, and opacity changes are immediate (exact undo). An equal stack changes nothing.
// * `applySoloMute`: CMP-012's overlay for the kinds soloed and muted (never part of the stack).
import Compositor
import SceneFormat

extension Compositor {
    /// False when no stack is applied or the stack was refused (the previous one stays).
    @discardableResult
    func applyLayerComposites(_ composites: [String: SceneComposite]) -> Bool {
        guard var stack = appliedStack else { return false }
        for entry in stack.entries {
            let saved: SceneComposite = composites[entry.descriptor.kind.identifier] ?? SceneComposite()
            let settings: LayerCompositeSettings = LayerCompositeMapping.settings(saved)
            do { try stack.setSettings(settings, of: entry.id) } catch { return false }
        }
        do {
            try apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in throw .notReady }
        } catch {
            return false
        }
        return true
    }

    func applySoloMute(soloed: Set<String>, muted: Set<String>) {
        guard let stack = appliedStack else { return }
        var overlay = LayerSoloMute()
        for entry in stack.entries {
            let kind: String = entry.descriptor.kind.identifier
            if soloed.contains(kind) { overlay.setSolo(true, layer: entry.id) }
            if muted.contains(kind) { overlay.setMute(true, layer: entry.id) }
        }
        setSoloMute(overlay)
    }
}
