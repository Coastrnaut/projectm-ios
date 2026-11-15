// AppCoordinator+LFOs.swift — MOD-007: a scene's oscillators feed the bindings that name them
// (MOD-007-R9; specs/156-mod-007-lfo, research MOD-007-D7, contract L7).
//
// When a native spectrum is created it gets the current scene's oscillators by position, exactly as it gets the
// restored bindings (SCN-002) and the threshold triggers (MOD-006); their shared origin is the visual's first frame.
// The visual caps them at 3 Hz while Reduce flashing is effective (ACC-012, FR-072).
// MOD-009 (specs/165-mod-009-tempo-lfo, research MOD-009-D5): tempo-synced oscillators follow SHOW-011's tempo snapshot
// (manual tap tempo, else a confident estimate, else their stored rate), read on each frame.
// VIS-015: the tunnel's speed follows the same snapshot (`tunnelTempo`), read on each frame while the tunnel is shown.
import ParameterGraph
import PerformanceControl
import VisualGenerators

extension AppCoordinator {
    func connectLFOs(_ host: NativeSpectrumHost) {
        try? host.setLFOs(sceneAutosave?.lfoOscillators ?? [])   // already read and limited; invalid ones are nil
        let tempo: TempoCoordinator = self.tempo
        host.lfoTempoBPM = { [weak tempo] () -> Double? in tempo?.snapshot.lfoTempoBPM }   // MOD-009
        host.tunnelTempo = { [weak tempo] () -> TunnelTempo in   // VIS-015: manual tap first, else a confident estimate
            guard let snapshot = tempo?.snapshot else { return .none }
            return TunnelTempo(bpm: snapshot.bpm, confidence: snapshot.confidence)
        }
    }
}
