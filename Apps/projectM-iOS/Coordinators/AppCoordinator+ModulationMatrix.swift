// AppCoordinator+ModulationMatrix.swift — MOD-012: the modulation matrix's link to the live routes (research
// MOD-012-D5; contract modulation-matrix M2, M4).
//
// * The live list is the native spectrum's modulator while one exists, else the scene autosave carry.
// * An edit applies in place on the host (signals kept, effective at once) and always replaces the carried list, so
//   a visual change before the next commit loses nothing. The matrix then refreshes its mirror, which
//   `SceneInputs.bindings` reads: SCN-002 saves it and SCN-010 records it as one step.
// * The route detail's live values are read on demand (10 Hz, only while it is open); nothing is observed per frame.
import Foundation
import ParameterGraph
import VisualParameters

extension AppCoordinator {
    /// Wires the matrix (called once in init, after the launch restore and before the history starts).
    func connectModulationMatrix() {
        modulationMatrix.live = { [weak self] () -> [AudioFeatureBinding] in self?.liveModulationRoutes ?? [] }
        modulationMatrix.store = { [weak self] (edit: ModulationRouteEdit) -> Bool in self?.applyModulationEdit(edit) ?? false }
        modulationMatrix.didEdit = { [weak self] () -> Void in self?.sceneHistory.endCoalescing() }   // SCN-010: one step each
        #if DEBUG
        UITestModulationMatrixFixture.seedIfRequested(self)   // MOD-012: ModulationMatrixUITests
        #endif
        modulationMatrix.refresh()
    }

    /// The current scene's routes in list order.
    var liveModulationRoutes: [AudioFeatureBinding] { nativeVisual?.bindings ?? sceneAutosave?.bindings ?? [] }

    /// Applies one edit to the live routes; false (nothing changed) when refused.
    func applyModulationEdit(_ edit: ModulationRouteEdit) -> Bool {
        guard let next = edit.applied(to: liveModulationRoutes) else { return false }
        if let host = nativeVisual {
            do {
                switch edit {
                case let .setEnabled(enabled, target, layer): try host.setLayerEnabled(enabled, for: target, layer: layer)
                case let .move(target, from, to): try host.moveLayer(of: target, from: from, to: to)
                case let .replace(list): try host.replaceBindings(list)
                }
            } catch {
                return false
            }
        }
        sceneAutosave?.replaceCarriedBindings(next)
        return true
    }

    /// MOD-012-R7: one route's live values, nil without a native visual (the detail then says so).
    func modulationRouteReading(target: ParameterID, layer: Int) -> ModulationRouteReading? {
        guard let host = nativeVisual, let signal = host.layerSignal(for: target, layer: layer),
              let index = ModulationRouteList.index(in: host.bindings, target: target, layer: layer) else { return nil }
        let binding: AudioFeatureBinding = host.bindings[index]
        let mapped: Double = binding.mapping.interpolate(binding.curve.apply(signal))
        let manual: Double = modulationBase(for: target)
        let destination: Double = host.modulatorValue(for: target, manual: manual) ?? manual
        return ModulationRouteReading(signal: signal, mapped: mapped, destination: destination)
    }

    /// The destination's base value: the Settings value when the inspector knows it, else the registry default.
    func modulationBase(for id: ParameterID) -> Double {
        if let value = ParameterInspectorTargets.target(for: id, settings: settings)?.get().numericValue { return value }
        return ParameterInspectorCatalog.descriptor(id)?.defaultValue.numericValue ?? 0
    }

    /// The modulated (pre-ACC-012) value of every destination, from the host, else from a scratch modulator over the
    /// carried list at signal 0 (DEBUG probe and tests).
    func modulationProbeValues() -> [(target: ParameterID, value: Double)] {
        let routes: [AudioFeatureBinding] = modulationMatrix.routes
        var scratch: AudioFeatureModulator?
        if nativeVisual == nil, let registry = ParameterInspectorCatalog.registry {
            let m = AudioFeatureModulator(registry: registry)
            try? m.replaceBindings(routes)
            scratch = m
        }
        return ModulationRouteList.groups(routes).map { (group: ModulationRouteGroup) -> (target: ParameterID, value: Double) in
            let manual: Double = modulationBase(for: group.target)
            let value: Double = nativeVisual?.modulatorValue(for: group.target, manual: manual)
                ?? scratch?.value(for: group.target, manual: manual) ?? manual
            return (group.target, value)
        }
    }
}

/// One route's live values (MOD-012-R7).
struct ModulationRouteReading: Equatable {
    /// The layer's enveloped 0…1 signal.
    let signal: Double
    /// The layer's mapped value (curve, then output range).
    let mapped: Double
    /// The destination's value after every enabled layer (before the sensory safety clamp).
    let destination: Double
}
