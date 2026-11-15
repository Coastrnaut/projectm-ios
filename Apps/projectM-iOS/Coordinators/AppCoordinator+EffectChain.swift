// AppCoordinator+EffectChain.swift — FX-020: the effect order reaches the compositor-backed visuals, and chain presets
// are saved and applied (FX-020-R8 to R10; specs/142-fx-020-effect-chains, contracts/effect-chain.md E4; ADR-0054).
//
// * The order goes to the Camera, Photo, Video and Text compositors when it changes and when a visual is created (the
//   native spectra and projectM have neither Trails nor Color). Flash safety and the tone map stay last in every order.
// * The live chain (`liveEffectSettings`) is the order plus the user's Color and Trails values (before ACC-012's caps);
//   scenes capture it (`SceneInputs.effects`), presets save it, and applying a preset sets the three settings exactly as
//   opening a scene with that list does.
import Compositor
import SceneFormat

extension AppCoordinator {
    /// The chain as the user set it.
    var liveEffectSettings: SceneEffectSettings {
        var live = SceneEffectSettings(order: effectChain.order, grade: colorGrade.grade, gradeEnabled: colorGrade.isEnabled,
                                       trails: motionFeedback.feedback, chromatic: chromaticSplit.split,
                                       directionalBlur: directionalBlur.blur, radialBlur: radialBlur.blur,
                                       echo: echoFeedback.feedback, mosaic: mosaic.mosaic,
                                       edgeOutline: edgeOutline.outline)   // FX-006, FX-007, FX-008, FX-010, FX-012, FX-014
        live.lensDistortion = lensDistortion.lens   // FX-016
        live.vignette = vignette.vignette   // FX-015
        live.pixelSort = pixelSort.sort   // FX-011
        live.filmGrain = filmGrain.grain   // FX-017
        return live
    }

    /// Wires the setting to the visuals (called once from init).
    func connectEffectChain() {
        effectChain.onChange = { [weak self] (_: OutputEffectOrder) -> Void in self?.applyEffectOrder() }
    }

    func applyEffectOrder() {
        Self.apply(effectChain.order, to: trailsCompositors)
    }

    static func apply(_ order: OutputEffectOrder, to compositors: [Compositor]) {
        for compositor in compositors { compositor.outputEffectOrder = order }
    }

    /// Saves the live chain under `name`; false when the name is not usable or the list is full.
    @discardableResult
    func saveEffectPreset(named name: String) -> Bool {
        let saved: Bool = effectChain.savePreset(name: name, effects: liveEffectSettings.entries(over: nil))
        if saved { announcer.announce("Saved effect preset " + name, kind: .parameter) }
        return saved
    }

    /// Applies the preset called `name` (order, Color and Trails).
    func applyEffectPreset(named name: String) {
        guard let preset = effectChain.presets.preset(named: name) else { return }
        SceneAutosaveCapture.applyEffects(preset.effects, chain: effectChain, grade: colorGrade, trails: motionFeedback, chromatic: chromaticSplit,
                                          directionalBlur: directionalBlur, radialBlur: radialBlur,
                                          echo: echoFeedback, mosaic: mosaic,
                                          edgeOutline: edgeOutline, lensDistortion: lensDistortion,
                                          vignette: vignette, pixelSort: pixelSort, filmGrain: filmGrain)   // FX-007, FX-008, FX-010, FX-012, FX-014, FX-016, FX-015, FX-011, FX-017
        announcer.announce("Applied effect preset " + preset.name, kind: .parameter)
    }
}
