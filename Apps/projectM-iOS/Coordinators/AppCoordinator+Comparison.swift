// AppCoordinator+Comparison.swift — roadmap PRE-009: creates the browser's preset comparison model
// (specs/235-pre-009-preset-comparison, contract C3). Preset bytes come from the same provider as the
// thumbnails (PRE-012: imported presets only from the playable copy); the previews use the renderer's
// comparison runner and attached reader; both previews pass the current safety clamp's envelope (R9); the
// shown visual pauses while comparing and the normal visual switch restores it (R10).
import FlashSafety
import AudioCore
import Foundation
import PresetLibrary
import Rendering

extension AppCoordinator {
    func makeComparison(loader: RendererPresetLoader) -> PresetComparisonModel {
        let model = PresetComparisonModel(
            contents: Self.presetContents(loader: loader),
            comparing: { [weak self] () -> (any PresetComparing)? in self?.renderer?.presetComparison },
            reader: { [weak self] () -> (any NormalizedPCMReader)? in self?.renderer?.sharedPCMReader },
            configuration: { [weak self] () -> PresetComparisonConfiguration in
                let clamp: SafetyClamp = self?.settings.safetyClamp ?? .standard
                let flash: FlashEnvelopeConfiguration = clamp.flashLimitsOverride ?? .forReduceFlashing(clamp.reducesFlashing)
                let rate: Double = PresetComparisonModel.rate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                                               thermal: ProcessInfo.processInfo.thermalState)
                return PresetComparisonConfiguration(rate: rate, flash: flash)
            })
        model.pauseVisual = { [weak self] in self?.pauseVisualsForComparison() }
        model.resumeVisual = { [weak self] in self?.resumeVisualsAfterComparison() }
        model.announce = { [weak self] (text: String) in self?.presets.announceLibrary(text) }   // library lane
        return model
    }
}
