// LayerInspectorModel.swift — the layer inspector's plain values (CMP-015-R1 to R3, R7, R9; research
// CMP-015-D1, D2, D5; data-model; contracts/layer-inspector.md L1, L2).
//
// * `LayerInspectorParameter` and `LayerInspectorHelp.entries`: every inspector parameter's title and
//   contextual help, in ONE table (the views read nothing else for help).
// * `LayerInspectorScene.rows`: the current scene's layers — the document the autosave would save —
//   top first, with position, saved composite, editability and the read-only reason, group name and the
//   layer's own app-held MOD-001 values. Only photo, video, text and the circular spectrum of the
//   Photo, Video and Text scenes are drawn by a compositor, so only they are editable.
// * `LayerCompositeEdit`: reads and writes one parameter of a saved `SceneComposite` (unknown blend,
//   fit and mask names are kept until the user picks a known value), plus ranges, steps and the shown
//   text. `LayerCompositeMapping`: a saved composite as the compositor's settings (SceneLiveState's rule).
// * Every intermediate is a named, typed value: long mixed expressions time out the type checker.
import Compositor
import Foundation
import ParameterGraph
import SceneFormat
import VisualParameters

// MARK: - Parameters and help (CMP-015-R7)

enum LayerInspectorParameter: String, CaseIterable, Sendable {
    case opacity, blendMode, positionX, positionY, scale, rotation
    case fitMode, fitAnchorX, fitAnchorY
    case maskShape, maskSize, maskCornerRadius, maskFeather, maskInverted
    case group, ownParameters, solo, mute

    /// The sliders (continuous values).
    static let sliders: [LayerInspectorParameter] = [
        .opacity, .positionX, .positionY, .scale, .rotation, .fitAnchorX, .fitAnchorY, .maskSize, .maskCornerRadius, .maskFeather,
    ]

    var title: String { LayerInspectorHelp.entry(self).title }
    var help: String { LayerInspectorHelp.entry(self).help }
}

struct LayerInspectorHelpEntry: Equatable, Sendable {
    let title: String
    let help: String
}

enum LayerInspectorHelp {
    typealias Entry = LayerInspectorHelpEntry

    /// The one help table (research CMP-015-D5).
    static let entries: [LayerInspectorParameter: Entry] = [
        .opacity: Entry(title: "Opacity", help: "How much of the layer shows. At 0% it is invisible; at 100% it fully covers what is below where it is opaque."),
        .blendMode: Entry(title: "Blend Mode", help: "How the layer mixes with the layers below. Normal paints over them; Add and Screen brighten; Multiply darkens; Overlay adds contrast; Difference shows how the colours differ."),
        .positionX: Entry(title: "Position X", help: "Moves the layer left or right, as a fraction of the screen's width. 0 is centred."),
        .positionY: Entry(title: "Position Y", help: "Moves the layer up or down, as a fraction of the screen's height. 0 is centred; positive moves it down."),
        .scale: Entry(title: "Scale", help: "Makes the layer bigger or smaller around its centre. 1× is its normal size."),
        .rotation: Entry(title: "Rotation", help: "Turns the layer around its centre, in degrees. Positive turns it clockwise."),
        .fitMode: Entry(title: "Fit", help: "How a photo or video fills the screen. Fill covers the screen and crops the edges; Fit shows all of it with empty bars; Stretch covers the screen exactly and may distort it; Pixel accurate shows one picture pixel per screen pixel."),
        .fitAnchorX: Entry(title: "Fit Anchor X", help: "Which part of the picture stays in view when it is cropped or smaller than the screen: 0 keeps the left edge, 1 the right edge."),
        .fitAnchorY: Entry(title: "Fit Anchor Y", help: "Which part of the picture stays in view when it is cropped or smaller than the screen: 0 keeps the top edge, 1 the bottom edge."),
        .maskShape: Entry(title: "Mask", help: "Shows the layer only inside a shape. None shows all of it."),
        .maskSize: Entry(title: "Mask Size", help: "The size of the mask shape, compared with the layer's shorter side."),
        .maskCornerRadius: Entry(title: "Corner Radius", help: "Rounds the corners of a rectangle mask. 0 gives sharp corners."),
        .maskFeather: Entry(title: "Feather", help: "Softens the mask's edge so the layer fades out instead of stopping sharply."),
        .maskInverted: Entry(title: "Invert Mask", help: "Shows the layer outside the shape instead of inside it."),
        .group: Entry(title: "Group", help: "The group this layer belongs to. A group's settings apply to all of its layers together."),
        .ownParameters: Entry(title: "Layer Settings", help: "Settings that belong to this kind of layer, such as the spectrum's bar count. Change them in Settings."),
        .solo: Entry(title: "Solo", help: "Shows only the soloed layers while you check them. Solo is never saved and cannot be undone; it ends when the visual changes."),
        .mute: Entry(title: "Mute", help: "Hides the layer while you check the others. Mute is never saved and cannot be undone; it ends when the visual changes."),
    ]

    static func entry(_ parameter: LayerInspectorParameter) -> Entry {
        entries[parameter] ?? Entry(title: parameter.rawValue, help: "")
    }
}

// MARK: - Rows (CMP-015-R1 to R3)

struct LayerOwnValue: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let value: String
}

struct LayerInspectorRow: Equatable, Sendable, Identifiable {
    let instance: UInt64
    let kind: String
    let title: String
    /// 1-based from the bottom.
    let position: Int
    let count: Int
    let composite: SceneComposite
    let isEditable: Bool
    let readOnlyReason: String?
    let groupName: String?
    let ownValues: [LayerOwnValue]

    var id: UInt64 { instance }

    /// The row's VoiceOver value (contract L1).
    var accessibilityValue: String {
        let place: String = "Layer \(position) of \(count)"
        return isEditable ? "\(place), editable" : "\(place), read only"
    }
}

struct LayerInspectorGroupRow: Equatable, Sendable, Identifiable {
    let id: UInt64
    let name: String
    let isEnabled: Bool
    let opacity: Double
    let memberCount: Int
}

enum LayerInspectorScene {
    /// Kinds a compositor visual draws (research CMP-015-D1).
    static let composedKinds: Set<String> = ["photo", "video", "text", "spectrum.circular"]
    /// Visuals built as a compositor stack and recorded in scenes (Camera is session only).
    static let composedVisuals: Set<VisualChoice> = [.photo, .video, .text]

    static let notDrawnReason = "This version keeps this layer in the scene but doesn't draw it, so its settings can't be changed here."
    static let directVisualReason = "This visual draws its layer directly, so layer settings don't apply. Choose Photo, Video or Text to edit layers."

    /// The scene's layers, top first.
    static func rows(document: SceneDocument, visual: VisualChoice) -> [LayerInspectorRow] {
        let count: Int = document.layers.count
        var rows: [LayerInspectorRow] = []
        rows.reserveCapacity(count)
        for (index, layer) in document.layers.enumerated() {
            rows.append(row(layer, index: index, count: count, document: document, visual: visual))
        }
        return rows.reversed()
    }

    static func groups(document: SceneDocument) -> [LayerInspectorGroupRow] {
        document.groups.map { (group: SceneGroup) -> LayerInspectorGroupRow in
            LayerInspectorGroupRow(id: group.id, name: groupTitle(group), isEnabled: group.enabled, opacity: group.opacity,
                                   memberCount: group.children.count)
        }
    }

    private static func row(_ layer: SceneLayer, index: Int, count: Int, document: SceneDocument, visual: VisualChoice) -> LayerInspectorRow {
        let kind: String = layer.kind
        let drawn: Bool = composedKinds.contains(kind)
        let composed: Bool = composedVisuals.contains(visual)
        let editable: Bool = drawn && composed
        let reason: String? = editable ? nil : (drawn || kind.hasPrefix("spectrum.") ? directVisualReason : notDrawnReason)
        return LayerInspectorRow(instance: layer.instance, kind: kind, title: title(of: layer.content), position: index + 1, count: count,
                                 composite: layer.composite, isEditable: editable, readOnlyReason: reason,
                                 groupName: groupName(of: layer.instance, in: document),
                                 ownValues: ownValues(kind: kind, parameters: document.parameters))
    }

    static func title(of content: SceneLayerContent) -> String {
        switch content {
        case .camera: "Camera"
        case .circularSpectrum: "Circular Spectrum"
        case .linearSpectrum: "Linear Spectrum"
        case .photo: "Photo"
        case .video: "Video"
        case .text: "Text"
        case let .material(id): "Material (\(id.replacingOccurrences(of: "material.", with: "")))"
        case .generatorGraph: "Generator Graph"
        case let .unknown(kind): "Unknown (\(kind))"
        }
    }

    private static func groupTitle(_ group: SceneGroup) -> String {
        group.name.isEmpty ? "Group \(group.id)" : group.name
    }

    private static func groupName(of instance: UInt64, in document: SceneDocument) -> String? {
        for group in document.groups {
            for child in group.children {
                if case let .layer(member) = child, member == instance { return groupTitle(group) }
            }
        }
        return nil
    }

    /// The layer kind's MOD-001 values present in the scene (read-only; changed in Settings).
    static func ownValues(kind: String, parameters: [ParameterID: ParameterValue]) -> [LayerOwnValue] {
        let groupID: String
        switch kind {
        case "spectrum.circular": groupID = VisualParameterCatalog.circularSpectrumGroup.id
        case "spectrum.linear": groupID = VisualParameterCatalog.linearSpectrumGroup.id
        default: return []
        }
        var values: [LayerOwnValue] = []
        for descriptor in VisualParameterCatalog.descriptors where descriptor.group.id == groupID {
            guard let value = parameters[descriptor.id] else { continue }
            values.append(LayerOwnValue(id: descriptor.id.rawValue, title: descriptor.displayName, value: text(value, kind: descriptor.kind)))
        }
        return values
    }

    private static func text(_ value: ParameterValue, kind: ParameterKind) -> String {
        if let caseID = value.enumCaseID {
            if case let .enumeration(cases, _) = kind,
               let match = cases.first(where: { (c: ParameterEnumCase) -> Bool in c.id == caseID }) {
                return match.displayName
            }
            return caseID
        }
        if let flag = value.boolValue { return flag ? "On" : "Off" }
        if let number = value.doubleValue { return String(format: "%.2f", number) }
        return ""
    }
}

// MARK: - Editing one parameter of a saved composite (CMP-015-R2, R9; contract L2, L3)

enum LayerCompositeEdit {
    static let blendTitles: [(name: String, title: String)] = [
        ("normal", "Normal"), ("add", "Add"), ("screen", "Screen"), ("multiply", "Multiply"), ("overlay", "Overlay"), ("difference", "Difference"),
    ]
    static let fitTitles: [(name: String, title: String)] = [
        ("fill", "Fill"), ("fit", "Fit"), ("stretch", "Stretch"), ("pixelAccurate", "Pixel accurate"),
    ]
    static let maskTitles: [(name: String, title: String)] = [("ellipse", "Ellipse"), ("rectangle", "Rectangle")]
    static let defaultCornerRadius = 0.1

    static func range(_ parameter: LayerInspectorParameter) -> ClosedRange<Double> {
        switch parameter {
        case .positionX, .positionY: -1...1
        case .scale: 0.1...4
        case .rotation: -180...180
        case .maskSize: 0.1...2
        case .maskCornerRadius: LayerMask.cornerRadiusRange
        case .maskFeather: 0...0.5
        default: 0...1
        }
    }

    /// VoiceOver's increment and decrement step.
    static func step(_ parameter: LayerInspectorParameter) -> Double {
        switch parameter {
        case .rotation: 5
        case .scale, .positionX, .positionY, .maskSize: 0.05
        case .maskCornerRadius, .maskFeather: 0.02
        default: 0.05
        }
    }

    // MARK: Reading

    static func value(_ parameter: LayerInspectorParameter, of composite: SceneComposite) -> Double {
        let transform: LayerTransform = composite.transform
        switch parameter {
        case .opacity: return composite.opacity
        case .positionX: return transform.translation.x
        case .positionY: return transform.translation.y
        case .scale: return transform.scale.x
        case .rotation: return transform.rotation * 180 / Double.pi
        case .fitAnchorX: return composite.fit?.anchor.x ?? 0.5
        case .fitAnchorY: return composite.fit?.anchor.y ?? 0.5
        case .maskSize: return knownMask(composite)?.transform.scale.x ?? 1
        case .maskCornerRadius: return cornerRadius(knownMask(composite)) ?? defaultCornerRadius
        case .maskFeather: return knownMask(composite)?.feather ?? 0
        case .maskInverted: return (knownMask(composite)?.inverted ?? false) ? 1 : 0
        default: return 0
        }
    }

    static func knownMask(_ composite: SceneComposite) -> LayerMask? { composite.mask?.layerMask }

    private static func cornerRadius(_ mask: LayerMask?) -> Double? {
        if case let .rectangle(radius)? = mask?.shape { return radius }
        return nil
    }

    /// The blend picker's selection: a known mode name, else the saved unknown name.
    static func blendName(_ composite: SceneComposite) -> String { composite.blendMode }

    static func blendTitle(_ name: String) -> String {
        blendTitles.first { (entry: (name: String, title: String)) -> Bool in entry.name == name }?.title ?? "Other (\(name))"
    }

    /// nil: the layer's default (fill at the centre).
    static func fitName(_ composite: SceneComposite) -> String? { composite.fit?.mode }

    static func fitTitle(_ name: String?) -> String {
        guard let name else { return "Default" }
        return fitTitles.first { (entry: (name: String, title: String)) -> Bool in entry.name == name }?.title ?? "Other (\(name))"
    }

    /// nil: no mask.
    static func maskName(_ composite: SceneComposite) -> String? { composite.mask?.shape }

    static func maskTitle(_ composite: SceneComposite) -> String {
        guard let mask = composite.mask else { return "None" }
        switch mask {
        case let .known(live):
            if case let .polygon(points) = live.shape { return "Polygon (\(points.count) points)" }
            return maskTitles.first { (entry: (name: String, title: String)) -> Bool in entry.name == live.shape.kindName }?.title ?? live.shape.kindName
        case let .unknown(shape, _):
            return "Other (\(shape))"
        }
    }

    /// The shown text of a parameter (contract L2).
    static func text(_ parameter: LayerInspectorParameter, of composite: SceneComposite) -> String {
        let v: Double = value(parameter, of: composite)
        switch parameter {
        case .opacity: return String(format: "%.0f%%", v * 100)
        case .blendMode: return blendTitle(composite.blendMode)
        case .positionX, .positionY, .fitAnchorX, .fitAnchorY, .maskSize, .maskCornerRadius, .maskFeather: return String(format: "%.2f", v)
        case .scale: return String(format: "%.2f×", v)
        case .rotation: return String(format: "%.0f°", v)
        case .fitMode: return fitTitle(composite.fit?.mode)
        case .maskShape: return maskTitle(composite)
        case .maskInverted: return v > 0.5 ? "On" : "Off"
        default: return ""
        }
    }

    // MARK: Writing (the composite types clamp; unknown names survive unrelated edits)

    static func setting(_ parameter: LayerInspectorParameter, to value: Double, on composite: SceneComposite) -> SceneComposite {
        guard value.isFinite else { return composite }
        var result: SceneComposite = composite
        switch parameter {
        case .opacity: result.opacity = min(max(value, 0), 1)
        case .positionX, .positionY, .scale, .rotation: result.transform = transform(composite.transform, parameter, value)
        case .fitAnchorX, .fitAnchorY: result.fit = fit(composite.fit, parameter, value)
        case .maskSize, .maskCornerRadius, .maskFeather: result.mask = mask(composite.mask, parameter, value)
        case .maskInverted: result.mask = inverted(composite.mask, value > 0.5)
        default: break
        }
        return result
    }

    private static func transform(_ t: LayerTransform, _ parameter: LayerInspectorParameter, _ value: Double) -> LayerTransform {
        var translation: LayerPoint = t.translation
        var scale: LayerPoint = t.scale
        var rotation: Double = t.rotation
        switch parameter {
        case .positionX: translation.x = value
        case .positionY: translation.y = value
        case .scale: scale = LayerPoint(x: value, y: value)
        case .rotation: rotation = value * Double.pi / 180
        default: break
        }
        let made: LayerTransform? = try? LayerTransform(translation: translation, scale: scale, rotation: rotation, anchor: t.anchor)
        return made ?? t
    }

    private static func fit(_ fit: SceneFit?, _ parameter: LayerInspectorParameter, _ value: Double) -> SceneFit {
        let mode: String = fit?.mode ?? LayerFitMode.fill.rawValue
        var anchor: LayerPoint = fit?.anchor ?? LayerPoint(x: 0.5, y: 0.5)
        let clamped: Double = min(max(value, 0), 1)
        if parameter == .fitAnchorX { anchor.x = clamped } else { anchor.y = clamped }
        return SceneFit(mode: mode, anchor: anchor)
    }

    private static func mask(_ saved: SceneMask?, _ parameter: LayerInspectorParameter, _ value: Double) -> SceneMask? {
        guard case let .known(live)? = saved else { return saved }   // none or unknown: nothing to adjust
        var shape: LayerMaskShape = live.shape
        var transform: LayerMaskTransform = live.transform
        var feather: Double = live.feather
        switch parameter {
        case .maskSize:
            transform = LayerMaskTransform(center: live.transform.center, scale: LayerPoint(x: value, y: value), rotation: live.transform.rotation)
        case .maskCornerRadius:
            if case .rectangle = live.shape { shape = .rectangle(cornerRadius: value) }
        case .maskFeather:
            feather = value
        default:
            break
        }
        let made: LayerMask? = try? LayerMask(shape: shape, transform: transform, feather: feather, inverted: live.inverted)
        return made.map(SceneMask.known) ?? saved
    }

    private static func inverted(_ saved: SceneMask?, _ on: Bool) -> SceneMask? {
        guard case let .known(live)? = saved else { return saved }
        let made: LayerMask? = try? LayerMask(shape: live.shape, transform: live.transform, feather: live.feather, inverted: on)
        return made.map(SceneMask.known) ?? saved
    }

    static func settingBlend(_ name: String, on composite: SceneComposite) -> SceneComposite {
        var result: SceneComposite = composite
        result.blendMode = name
        return result
    }

    /// nil: the layer's default fit. A known mode keeps the current anchor.
    static func settingFit(_ name: String?, on composite: SceneComposite) -> SceneComposite {
        var result: SceneComposite = composite
        guard let name else {
            result.fit = nil
            return result
        }
        let anchor: LayerPoint = composite.fit?.anchor ?? LayerPoint(x: 0.5, y: 0.5)
        result.fit = SceneFit(mode: name, anchor: anchor)
        return result
    }

    /// nil: no mask. A new shape keeps the current mask's placement, feather and invert.
    static func settingMask(_ name: String?, on composite: SceneComposite) -> SceneComposite {
        var result: SceneComposite = composite
        guard let name else {
            result.mask = nil
            return result
        }
        let current: LayerMask? = knownMask(composite)
        if current?.shape.kindName == name { return composite }
        let shape: LayerMaskShape
        switch name {
        case "ellipse": shape = .ellipse
        case "rectangle": shape = .rectangle(cornerRadius: defaultCornerRadius)
        default: return composite   // polygons and unknown shapes come only from scene files
        }
        let made: LayerMask? = try? LayerMask(shape: shape, transform: current?.transform ?? .identity, feather: current?.feather ?? 0,
                                              inverted: current?.inverted ?? false)
        result.mask = made.map(SceneMask.known)
        return result
    }
}

// MARK: - Saved composite → compositor settings

enum LayerCompositeMapping {
    /// As `SceneDocument.liveState`: unknown blend names draw as normal, unknown fits and masks as none.
    static func settings(_ composite: SceneComposite) -> LayerCompositeSettings {
        let mode: LayerBlendMode = LayerBlendMode(rawValue: composite.blendMode) ?? .normal
        return LayerCompositeSettings(opacity: composite.opacity, blendMode: mode, transform: composite.transform,
                                      fit: composite.fit?.layerFit, mask: composite.mask?.layerMask)
    }

    /// Default composites left out (research CMP-015-D2).
    static func normalized(_ composites: [String: SceneComposite]) -> [String: SceneComposite] {
        let defaultComposite = SceneComposite()
        return composites.filter { (entry: (key: String, value: SceneComposite)) -> Bool in entry.value != defaultComposite }
    }
}
