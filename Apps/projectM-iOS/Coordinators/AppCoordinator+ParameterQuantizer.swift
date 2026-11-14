// AppCoordinator+ParameterQuantizer.swift — MOD-017: the quantizer's link to the tempo, the show and the announcer
// (specs/206-mod-017-quantized-changes; R4, R6, R9). The grid is SHOW-011's snapshot; announcements use the
// `.parameter` lane (ACC-004). The cue boundary is called from the show's `applyScene` hook (AppCoordinator+Show).
// SHOW-003: the cue step quantizer shares the grid; it announces on the `.cue` lane and runs MOD-017's tick first at
// its boundary (research SHOW-003-D6).
import Foundation
import PerformanceControl

extension AppCoordinator {
    func connectParameterQuantizer() {
        settings.parameterQuantizer.connect(
            settings: settings,
            tempo: { [weak self] () -> TempoSnapshot in self?.tempo.snapshot ?? .none },
            hasCues: { [weak self] () -> Bool in self?.show.hasCues ?? false },
            announce: { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .parameter) })
        connectShowCueQuantizer()
    }

    /// SHOW-003: the show's beat or bar gate.
    func connectShowCueQuantizer() {
        let cues: ShowCueQuantizer = settings.showCueQuantizer
        let parameters: ParameterQuantizer = settings.parameterQuantizer
        cues.tempo = { [weak self] () -> TempoSnapshot in self?.tempo.snapshot ?? .none }
        cues.announce = { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .cue) }
        cues.willStep = { (deadline: UInt64) -> Void in parameters.tick(at: deadline) }
        show.cueQuantizer = cues
    }
}
