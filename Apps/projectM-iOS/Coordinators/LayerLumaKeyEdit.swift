// LayerLumaKeyEdit.swift — the layer inspector's luma key rules (CMP-009-R10; contracts/luma-key.md L2 in
// specs/220-cmp-009-luma-key).
//
// Plain values over a saved `SceneComposite` (the view only binds): on gives `LayerLumaKey.blackKey` (or keeps the
// current key), off removes it; Low above High moves High with it, High below Low moves Low with it, so low ≤ high
// always holds; Softness and Invert edit the current key. Edits to a layer without a key change nothing. History:
// Low and High share the label "Luma Range" and the coalescing key `layer.<kind>.lumaRange` (a drag that pushes the
// other end changes both). Every intermediate is a named, typed value (type-checker budgets).
import Compositor
import Foundation
import SceneFormat

enum LayerLumaKeyEdit {
    static let parameters: [LayerInspectorParameter] = [.lumaKey, .lumaLow, .lumaHigh, .lumaSoftness, .lumaInverted]

    static func key(_ composite: SceneComposite) -> LayerLumaKey? { composite.lumaKey }

    /// The shown value: the key's, or the black key's when there is none (so turning it on changes no slider).
    static func value(_ parameter: LayerInspectorParameter, of composite: SceneComposite) -> Double {
        let k: LayerLumaKey = composite.lumaKey ?? .blackKey
        switch parameter {
        case .lumaKey: return composite.lumaKey == nil ? 0 : 1
        case .lumaLow: return k.low
        case .lumaHigh: return k.high
        case .lumaSoftness: return k.softness
        case .lumaInverted: return (composite.lumaKey?.inverted ?? false) ? 1 : 0
        default: return 0
        }
    }

    static func text(_ parameter: LayerInspectorParameter, of composite: SceneComposite) -> String {
        let v: Double = value(parameter, of: composite)
        switch parameter {
        case .lumaKey, .lumaInverted: return v > 0.5 ? "On" : "Off"
        default: return String(format: "%.2f", v)
        }
    }

    static func setting(_ parameter: LayerInspectorParameter, to value: Double, on composite: SceneComposite) -> SceneComposite {
        guard value.isFinite else { return composite }
        var result: SceneComposite = composite
        if parameter == .lumaKey {
            result.lumaKey = value > 0.5 ? (composite.lumaKey ?? .blackKey) : nil
            return result
        }
        guard let k = composite.lumaKey else { return composite }
        let limits: ClosedRange<Double> = LayerLumaKey.rangeLimits
        let v: Double = min(max(value, limits.lowerBound), limits.upperBound)
        switch parameter {
        case .lumaLow:
            result.lumaKey = LayerLumaKey(low: v, high: max(k.high, v), softness: k.softness, inverted: k.inverted)
        case .lumaHigh:
            result.lumaKey = LayerLumaKey(low: min(k.low, v), high: v, softness: k.softness, inverted: k.inverted)
        case .lumaSoftness:
            result.lumaKey = LayerLumaKey(low: k.low, high: k.high, softness: value, inverted: k.inverted)
        case .lumaInverted:
            result.lumaKey = LayerLumaKey(low: k.low, high: k.high, softness: k.softness, inverted: value > 0.5)
        default:
            return composite
        }
        return result
    }

    /// The parameters that differ (Low and High as their own entries; the toggle when the key appears or goes).
    static func changed(from old: SceneComposite, to new: SceneComposite) -> [LayerInspectorParameter] {
        if (old.lumaKey == nil) != (new.lumaKey == nil) { return [.lumaKey] }
        guard let a = old.lumaKey, let b = new.lumaKey, a != b else { return [] }
        var result: [LayerInspectorParameter] = []
        if a.low != b.low { result.append(.lumaLow) }
        if a.high != b.high { result.append(.lumaHigh) }
        if a.softness != b.softness { result.append(.lumaSoftness) }
        if a.inverted != b.inverted { result.append(.lumaInverted) }
        return result
    }

    /// A Low and/or High change alone: "<Layer> Luma Range 0.10–0.30", key `layer.<kind>.lumaRange`.
    static func rangeEdit(_ parameters: [LayerInspectorParameter], title: String, kind: String,
                          after: SceneComposite) -> (label: String, key: String?)? {
        guard !parameters.isEmpty, parameters.allSatisfy({ (p: LayerInspectorParameter) -> Bool in p == .lumaLow || p == .lumaHigh }),
              let k = after.lumaKey else { return nil }
        let range: String = String(format: "%.2f–%.2f", k.low, k.high)
        return ("\(title) Luma Range \(range)", "layer.\(kind).lumaRange")
    }
}
