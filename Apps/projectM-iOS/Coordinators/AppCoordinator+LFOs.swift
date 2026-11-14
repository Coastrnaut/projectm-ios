// AppCoordinator+LFOs.swift — MOD-007: a scene's oscillators feed the bindings that name them
// (MOD-007-R9; specs/156-mod-007-lfo, research MOD-007-D7, contract L7).
//
// When a native spectrum is created it gets the current scene's oscillators by position, exactly as it gets the
// restored bindings (SCN-002) and the threshold triggers (MOD-006); their shared origin is the visual's first frame.
// The visual caps them at 3 Hz while Reduce flashing is effective (ACC-012, FR-072).
import ParameterGraph

extension AppCoordinator {
    func connectLFOs(_ host: NativeSpectrumHost) {
        try? host.setLFOs(sceneAutosave?.lfoOscillators ?? [])   // already read and limited; invalid ones are nil
    }
}
