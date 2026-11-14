// LayerGradientEdit.swift — the layer inspector's gradient mask rules (CMP-008-R10; research CMP-008-D6;
// contracts/gradient-masks.md G4 in specs/207-cmp-008-gradient-masks).
//
// Plain values over a saved `SceneComposite` (the view only binds): the kind (None, Linear, Radial; a new gradient
// takes the kind's default geometry and keeps the current stops), the linear angle (degrees; the gradient keeps its
// midpoint and length in layer fractions and turns), the radial radius, and the stops (position and alpha, add at the
// middle of the widest gap with the alpha the gradient already has there, remove down to two). An unknown saved kind
// is kept until the user picks a known one. History: `stopEdit` names a one-stop, one-field change for its undo label
// and coalescing key. Every intermediate is a named, typed value (type-checker budgets).
import Compositor
import Foundation
import SceneFormat

enum LayerGradientField: String, Sendable {
    case position, alpha

    var title: String { self == .position ? "Position" : "Alpha" }
}

enum LayerGradientEdit {
    static let kindTitles: [(name: String, title: String)] = [("linear", "Linear"), ("radial", "Radial")]
    static let angleRange: ClosedRange<Double> = -180...180
    static let radiusRange: ClosedRange<Double> = 0.1...2
    static let stopStep = 0.05

    static func known(_ composite: SceneComposite) -> LayerGradientMask? { composite.gradientMask?.layerGradientMask }

    /// nil: no gradient.
    static func kindName(_ composite: SceneComposite) -> String? { composite.gradientMask?.kind }

    static func kindTitle(_ composite: SceneComposite) -> String {
        guard let name = kindName(composite) else { return "None" }
        return kindTitles.first { (entry: (name: String, title: String)) -> Bool in entry.name == name }?.title ?? "Other (\(name))"
    }

    static func isUnknownKind(_ name: String) -> Bool {
        kindTitles.allSatisfy { (entry: (name: String, title: String)) -> Bool in entry.name != name }
    }

    // MARK: Kind

    /// nil removes the gradient; a known kind keeps the current stops (or the defaults) with that kind's default geometry.
    static func settingKind(_ name: String?, on composite: SceneComposite) -> SceneComposite {
        var result: SceneComposite = composite
        guard let name else {
            result.gradientMask = nil
            return result
        }
        if kindName(composite) == name, known(composite) != nil { return composite }
        let base: LayerGradientMask
        switch name {
        case "linear": base = .linearDefault
        case "radial": base = .radialDefault
        default: return composite
        }
        let stops: [LayerGradientStop] = known(composite)?.stops ?? base.stops
        let made: LayerGradientMask? = try? LayerGradientMask(kind: base.kind, stops: stops)
        result.gradientMask = .known(made ?? base)
        return result
    }

    // MARK: Angle (linear) and radius (radial)

    /// Degrees, 0 = left to right, positive clockwise on screen (y down); 0 for a radial or no gradient.
    static func angle(_ composite: SceneComposite) -> Double {
        guard case let .linear(start, end)? = known(composite)?.kind else { return 0 }
        let dx: Double = end.x - start.x
        let dy: Double = end.y - start.y
        let radians: Double = atan2(dy, dx)
        let degrees: Double = radians * 180 / Double.pi
        return degrees == 0 ? 0 : degrees
    }

    static func settingAngle(_ degrees: Double, on composite: SceneComposite) -> SceneComposite {
        guard degrees.isFinite, let gradient = known(composite), case let .linear(start, end) = gradient.kind else { return composite }
        let clamped: Double = min(max(degrees, angleRange.lowerBound), angleRange.upperBound)
        let radians: Double = clamped * Double.pi / 180
        let mx: Double = (start.x + end.x) / 2
        let my: Double = (start.y + end.y) / 2
        let dx: Double = end.x - start.x
        let dy: Double = end.y - start.y
        let half: Double = 0.5 * (dx * dx + dy * dy).squareRoot()
        let hx: Double = half * cos(radians)
        let hy: Double = half * sin(radians)
        let kind = LayerGradientKind.linear(start: LayerPoint(x: mx - hx, y: my - hy), end: LayerPoint(x: mx + hx, y: my + hy))
        return replacing(kind: kind, stops: gradient.stops, on: composite)
    }

    /// The radial radius; 0.5 otherwise.
    static func radius(_ composite: SceneComposite) -> Double {
        guard case let .radial(_, r)? = known(composite)?.kind else { return LayerGradientMask.defaultRadius }
        return r
    }

    static func settingRadius(_ radius: Double, on composite: SceneComposite) -> SceneComposite {
        guard radius.isFinite, let gradient = known(composite), case let .radial(center, _) = gradient.kind else { return composite }
        let clamped: Double = min(max(radius, radiusRange.lowerBound), radiusRange.upperBound)
        return replacing(kind: .radial(center: center, radius: clamped), stops: gradient.stops, on: composite)
    }

    // MARK: Stops

    static func stops(_ composite: SceneComposite) -> [LayerGradientStop] { known(composite)?.stops ?? [] }

    static func canAddStop(_ composite: SceneComposite) -> Bool {
        guard let gradient = known(composite) else { return false }
        return gradient.stops.count < LayerGradientMask.maximumStops
    }

    static func canRemoveStop(_ composite: SceneComposite) -> Bool {
        guard let gradient = known(composite) else { return false }
        return gradient.stops.count > LayerGradientMask.minimumStops
    }

    /// Sets one field of stop `index` (0-based, in position order); the stops are re-sorted.
    static func settingStop(_ index: Int, _ field: LayerGradientField, to value: Double, on composite: SceneComposite) -> SceneComposite {
        guard value.isFinite, let gradient = known(composite), gradient.stops.indices.contains(index) else { return composite }
        var stops: [LayerGradientStop] = gradient.stops
        let old: LayerGradientStop = stops[index]
        switch field {
        case .position: stops[index] = LayerGradientStop(position: value, alpha: old.alpha)
        case .alpha: stops[index] = LayerGradientStop(position: old.position, alpha: value)
        }
        return replacing(kind: gradient.kind, stops: stops, on: composite)
    }

    /// A stop at the middle of the widest gap (ends included) with the gradient's own alpha there, so the picture
    /// does not change.
    static func addingStop(on composite: SceneComposite) -> SceneComposite {
        guard canAddStop(composite), let gradient = known(composite) else { return composite }
        let positions: [Double] = gradient.stops.map(\.position)
        var bounds: [Double] = [0]
        bounds.append(contentsOf: positions)
        bounds.append(1)
        var best: Double = -1
        var middle: Double = 0.5
        for k in 1..<bounds.count {
            let gap: Double = bounds[k] - bounds[k - 1]
            if gap > best {
                best = gap
                middle = (bounds[k] + bounds[k - 1]) / 2
            }
        }
        let stop = LayerGradientStop(position: middle, alpha: gradient.alpha(at: middle))
        return replacing(kind: gradient.kind, stops: gradient.stops + [stop], on: composite)
    }

    static func removingStop(_ index: Int, on composite: SceneComposite) -> SceneComposite {
        guard canRemoveStop(composite), let gradient = known(composite), gradient.stops.indices.contains(index) else { return composite }
        var stops: [LayerGradientStop] = gradient.stops
        stops.remove(at: index)
        return replacing(kind: gradient.kind, stops: stops, on: composite)
    }

    private static func replacing(kind: LayerGradientKind, stops: [LayerGradientStop], on composite: SceneComposite) -> SceneComposite {
        guard let made = try? LayerGradientMask(kind: kind, stops: stops) else { return composite }
        var result: SceneComposite = composite
        result.gradientMask = .known(made)
        return result
    }

    // MARK: Texts and history

    static func stopsText(_ composite: SceneComposite) -> String {
        let count: Int = stops(composite).count
        return count == 1 ? "1 stop" : "\(count) stops"
    }

    static func stopText(_ value: Double) -> String { String(format: "%.2f", value) }

    /// A change of exactly one field of one stop (same count and kind): its index, field and new value.
    static func stopEdit(from old: SceneComposite, to new: SceneComposite) -> (index: Int, field: LayerGradientField, value: Double)? {
        guard let before = known(old), let after = known(new), before.kind == after.kind, before.stops.count == after.stops.count else {
            return nil
        }
        var found: (index: Int, field: LayerGradientField, value: Double)?
        for k in before.stops.indices where before.stops[k] != after.stops[k] {
            let a: LayerGradientStop = before.stops[k]
            let b: LayerGradientStop = after.stops[k]
            let positionChanged: Bool = a.position != b.position
            let alphaChanged: Bool = a.alpha != b.alpha
            guard found == nil, positionChanged != alphaChanged else { return nil }
            found = positionChanged ? (k, .position, b.position) : (k, .alpha, b.alpha)
        }
        return found
    }
}
