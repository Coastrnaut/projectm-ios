// EffectChainSetting.swift — FX-020: the order of Trails and Color and the saved chain presets (FX-020-R8, R10;
// specs/142-fx-020-effect-chains, contracts/effect-chain.md E3, E4, research FX-020-D8).
//
// `settings.effectChain.order` (String, `fx.trails,fx.grade`; absent or unreadable tokens → the standard order) and
// `settings.effectChain.presets` (Data, the canonical preset JSON of `EffectChainPresetList`; absent or unreadable → no
// presets, and unreadable data is left alone until the user saves). Both are included in library backups and removed by
// "Erase local data" (FILE-005 `LibrarySettingsPolicy.includedKeys`). `onChange` reports an order change; Trails and
// Color values stay in their own settings (`MotionFeedbackSetting`, `ColorGradeSetting`).
import Compositor
import Foundation
import Observation
import SceneFormat

@MainActor
@Observable
final class EffectChainSetting {
    static let orderKey = "settings.effectChain.order"
    static let presetsKey = "settings.effectChain.presets"
    static let allKeys: [String] = [orderKey, presetsKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after an order change.
    @ObservationIgnored var onChange: ((OutputEffectOrder) -> Void)?

    var order: OutputEffectOrder {
        didSet {
            guard order != oldValue else { return }
            if order == .standard {
                defaults.removeObject(forKey: Self.orderKey)
            } else {
                defaults.set(order.storageText, forKey: Self.orderKey)
            }
            onChange?(order)
        }
    }

    private(set) var presets: EffectChainPresetList

    init(defaults: UserDefaults) {
        self.defaults = defaults
        order = OutputEffectOrder(storageText: defaults.string(forKey: Self.orderKey) ?? "")
        let data: Data? = defaults.data(forKey: Self.presetsKey)
        presets = data.flatMap { (d: Data) -> EffectChainPresetList? in EffectChainPresetList.decode([UInt8](d)) } ?? EffectChainPresetList()
    }

    /// Saves `effects` under `name`; false when the name is empty or too long, or 32 presets exist.
    @discardableResult
    func savePreset(name: String, effects: [SceneEffectEntry]) -> Bool {
        guard let next = presets.saving(name: name, effects: effects) else { return false }
        store(next)
        return true
    }

    func deletePreset(named name: String) {
        store(presets.removing(name: name))
    }

    private func store(_ list: EffectChainPresetList) {
        presets = list
        if list.presets.isEmpty {
            defaults.removeObject(forKey: Self.presetsKey)
        } else {
            defaults.set(Data(list.encoded()), forKey: Self.presetsKey)
        }
    }

    // MARK: - Readouts

    /// "Trails" or "Color".
    static func name(_ kind: OutputEffectKind) -> String {
        switch kind {
        case .trails: "Trails"
        case .grade: "Color"
        }
    }

    /// "Trails → Color".
    static func summary(_ order: OutputEffectOrder) -> String {
        order.effects.map(name).joined(separator: " \u{2192} ")
    }
}
