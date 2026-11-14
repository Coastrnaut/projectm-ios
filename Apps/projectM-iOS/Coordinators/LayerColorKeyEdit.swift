// LayerColorKeyEdit.swift — the layer inspector's colour key rules (CMP-010-R10; contracts/color-key.md C4 in
// specs/230-cmp-010-color-key).
//
// Plain values over a saved `SceneComposite` (the view only binds): on gives `LayerColorKey.greenKey` (or keeps the
// current key), off removes it; the picked colour is stored opaque as displayed sRGB, each component clamped to 0…1
// and rounded to 1/1000 (research CMP-010-D4); Color Tolerance and Color Feather edit the current key. Edits to a
// layer without a key change nothing. History: a colour change is "<Layer> Key Color #RRGGBB" with the coalescing key
// `layer.<kind>.colorKeyColor` (the picker reports many values while the user drags in it). Every intermediate is a
// named, typed value (type-checker budgets).
import Compositor
import Foundation
import SceneFormat

enum LayerColorKeyEdit {
    static let parameters: [LayerInspectorParameter] = [.colorKey, .colorKeyColor, .colorTolerance, .colorFeather]

    /// The shown value: the key's, or the green key's when there is none (so turning it on changes no slider).
    static func value(_ parameter: LayerInspectorParameter, of composite: SceneComposite) -> Double {
        let k: LayerColorKey = composite.colorKey ?? .greenKey
        switch parameter {
        case .colorKey: return composite.colorKey == nil ? 0 : 1
        case .colorTolerance: return k.tolerance
        case .colorFeather: return k.feather
        default: return 0
        }
    }

    static func text(_ parameter: LayerInspectorParameter, of composite: SceneComposite) -> String {
        let k: LayerColorKey = composite.colorKey ?? .greenKey
        switch parameter {
        case .colorKey: return composite.colorKey == nil ? "Off" : "On"
        case .colorKeyColor: return hex(k)
        default: return String(format: "%.2f", value(parameter, of: composite))
        }
    }

    /// "#RRGGBB" of the key colour (displayed sRGB).
    static func hex(_ k: LayerColorKey) -> String {
        let r: Int = Int((k.red * 255).rounded())
        let g: Int = Int((k.green * 255).rounded())
        let b: Int = Int((k.blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func setting(_ parameter: LayerInspectorParameter, to value: Double, on composite: SceneComposite) -> SceneComposite {
        guard value.isFinite else { return composite }
        var result: SceneComposite = composite
        if parameter == .colorKey {
            result.colorKey = value > 0.5 ? (composite.colorKey ?? .greenKey) : nil
            return result
        }
        guard let k = composite.colorKey else { return composite }
        switch parameter {
        case .colorTolerance:
            result.colorKey = LayerColorKey(red: k.red, green: k.green, blue: k.blue, tolerance: value, feather: k.feather)
        case .colorFeather:
            result.colorKey = LayerColorKey(red: k.red, green: k.green, blue: k.blue, tolerance: k.tolerance, feather: value)
        default:
            return composite
        }
        return result
    }

    /// One component as stored: clamped to 0…1 and rounded to 1/1000; non-finite leaves `current`.
    static func component(_ v: Double, current: Double) -> Double {
        guard v.isFinite else { return current }
        let clamped: Double = min(max(v, 0), 1)
        let rounded: Double = (clamped * 1000).rounded() / 1000
        return rounded == 0 ? 0 : rounded
    }

    /// The picked colour (extended sRGB components; any opacity is not passed and so ignored).
    static func settingColor(red: Double, green: Double, blue: Double, on composite: SceneComposite) -> SceneComposite {
        guard let k = composite.colorKey else { return composite }
        let r: Double = component(red, current: k.red)
        let g: Double = component(green, current: k.green)
        let b: Double = component(blue, current: k.blue)
        var result: SceneComposite = composite
        result.colorKey = LayerColorKey(red: r, green: g, blue: b, tolerance: k.tolerance, feather: k.feather)
        return result
    }

    /// The parameters that differ (the toggle when the key appears or goes).
    static func changed(from old: SceneComposite, to new: SceneComposite) -> [LayerInspectorParameter] {
        if (old.colorKey == nil) != (new.colorKey == nil) { return [.colorKey] }
        guard let a = old.colorKey, let b = new.colorKey, a != b else { return [] }
        var result: [LayerInspectorParameter] = []
        if a.red != b.red || a.green != b.green || a.blue != b.blue { result.append(.colorKeyColor) }
        if a.tolerance != b.tolerance { result.append(.colorTolerance) }
        if a.feather != b.feather { result.append(.colorFeather) }
        return result
    }

    /// A colour change alone: "<Layer> Key Color #RRGGBB", key `layer.<kind>.colorKeyColor`.
    static func colorEdit(_ parameters: [LayerInspectorParameter], title: String, kind: String,
                          after: SceneComposite) -> (label: String, key: String?)? {
        guard parameters == [.colorKeyColor], let k = after.colorKey else { return nil }
        return ("\(title) Key Color \(hex(k))", "layer.\(kind).colorKeyColor")
    }
}
