// AppCoordinator+EffectChain.swift — FX-020: the effect order reaches the compositor-backed visuals, and chain presets
// are saved and applied (FX-020-R8 to R10; specs/142-fx-020-effect-chains, contracts/effect-chain.md E4; ADR-0052).
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
        SceneEffectSettings(order: effectChain.order, grade: colorGrade.grade, gradeEnabled: colorGrade.isEnabled,
                            trails: motionFeedback.feedback)
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
        SceneAutosaveCapture.applyEffects(preset.effects, chain: effectChain, grade: colorGrade, trails: motionFeedback)
        announcer.announce("Applied effect preset " + preset.name, kind: .parameter)
    }
}
