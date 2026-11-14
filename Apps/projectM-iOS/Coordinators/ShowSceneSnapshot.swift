// ShowSceneSnapshot.swift — the shown look ↔ an SCN-001 scene document, for show cues (SHOW-001-R7,
// R8; research SHOW-001-D5).
//
// * `ShowLook` is what the user can set today: the visual, the spectra's bar count, orientation and
//   spacing, the glow, the Text visual's spec and the stored photo and video. Camera is session only
//   (CAM-001-R11): the visual chosen before it is recorded.
// * Layers per visual, bottom first (the hosts' fixed stacks): Circular `[spectrum.circular]`, Linear
//   `[spectrum.linear]`, Photo `[photo, spectrum.circular]`, Video `[video, spectrum.circular]`, Text
//   `[spectrum.circular, text]`, projectM `[]`.
// * Back from a validated document: the visual from the layer kinds the app draws (layers it cannot
//   draw — camera, materials, generator graphs, unknown kinds — are left out and named), the app-held
//   MOD-001 values that are present (clamped through a scratch store), and the first text layer's spec.
// * This is a minimal path because SCN-002's restore was not integrated when SHOW-001 was built;
//   unify the two (same layer mapping, same seven values) once it is (ADR-0033 follow-up).
// Pure functions; no files.
import Foundation
import ParameterGraph
import SceneFormat
import TextLayer
import VisualGenerators
import VisualParameters

struct ShowLook: Equatable, Sendable {
    var visual: VisualChoice
    var bars: Int
    var orientation: LinearSpectrumOrientation
    var spacing: Double
    var glowEnabled: Bool
    var glowIntensity: Double
    var glowRadius: Double
    var glowThreshold: Double
    var text: TextOverlaySpec
    var photoID: UUID?
    var videoID: UUID?
    /// MED-003-R8: the stored video's loop region (nil: the whole file).
    var videoLoop: SceneVideoLoop? = nil
    /// MED-004-R7: the stored video's speed in percent (nil: 1×).
    var videoSpeedPercent: Int? = nil
    /// MED-006-R12: the image slideshow (nil: off and empty).
    var slideshow: SceneSlideshow? = nil
    /// MED-010-R10: the logo and its placement (nil: none).
    var logo: SceneLogo? = nil
}

/// What applying a scene sets (contract S4).
struct ShowSceneApply: Equatable, Sendable {
    var visual: VisualChoice
    /// App-held values present in the document, after MOD-001 clamping.
    var parameters: [ParameterID: ParameterValue]
    var text: TextOverlaySpec?
    /// Layer kinds in the scene the app cannot draw (left out).
    var omittedKinds: [String]
    /// The scene names a photo or video that is no longer the stored one.
    var missingMedia: Bool
    /// MED-003-R8: the first video layer's stored-video ID and loop (nil: none).
    var videoStoreID: String? = nil
    var videoLoop: SceneVideoLoop? = nil
    /// MED-004-R7: the video asset's speed in percent (nil: 1×).
    var videoSpeedPercent: Int? = nil
    /// MED-006-R12: the photo layer's slideshow (nil: no photo layer).
    var slideshow: SceneSlideshowRestore? = nil
    /// MED-010-R10: the scene's logo (nil: the scene records none; the current logo stays).
    var logo: SceneLogo? = nil
}

enum ShowSceneSnapshot {
    /// MOD-001 IDs of the values the app holds in AppSettings.
    static let appParameterIDs: [ParameterID] = [
        VisualParameterIDs.circularSpectrumBarCount, VisualParameterIDs.linearSpectrumOrientation,
        VisualParameterIDs.linearSpectrumSpacing, VisualParameterIDs.bloomEnabled, VisualParameterIDs.bloomIntensity,
        VisualParameterIDs.bloomRadius, VisualParameterIDs.bloomThreshold,
    ]
    static let photoKey = "photo"
    static let videoKey = "video"
    static let textKey = "text"

    /// The visual a look records: Camera is session only, so the one chosen before it.
    static func recordedVisual(_ visual: VisualChoice, beforeCamera: VisualChoice) -> VisualChoice {
        visual.usesCamera ? (beforeCamera.usesCamera ? .projectM : beforeCamera) : visual
    }

    // MARK: Capture

    static func document(_ look: ShowLook, id: String, name: String) -> SceneDocument {
        var contents: [SceneLayerContent] = []
        var assets: [String: SceneAsset] = [:]
        switch look.visual {
        case .projectM, .camera, .oscilloscope:
            break   // camera never reaches here (recordedVisual); projectM and the oscilloscope (VIS-003-R12) are no compositor layer
        case .circularSpectrum:
            contents = [.circularSpectrum]
        case .linearSpectrum:
            contents = [.linearSpectrum]
        case .photo:
            if let asset = SceneSlideshowBridge.photoAsset(photoID: look.photoID, slideshow: look.slideshow) {   // MED-006
                assets[photoKey] = asset
                contents.append(.photo(asset: photoKey))
            }
            contents.append(.circularSpectrum)
        case .video:
            if let id = look.videoID {
                assets[videoKey] = SceneVideoLoopBridge.asset(storeID: id, loop: look.videoLoop, speedPercent: look.videoSpeedPercent)   // MED-003, MED-004
                contents.append(.video(asset: videoKey))
            }
            contents.append(.circularSpectrum)
        case .text:
            contents = [.circularSpectrum]
            if let spec = sceneJSON(look.text.encodedForStorage()) {
                assets[textKey] = SceneAsset(.text(spec: spec))
                contents.append(.text(asset: textKey))
            }
        }
        if let logo = look.logo {   // MED-010-R10
            assets[SceneLogo.assetKey] = .logo(storeID: logo.storeID, placement: logo.placement)
        }
        var instance: UInt64 = 0
        let layers = contents.map { (content: SceneLayerContent) -> SceneLayer in
            instance += 1
            return SceneLayer(instance: instance, content: content)
        }
        return SceneDocument(id: id, name: name, layers: layers, parameters: parameterValues(look), assets: assets)
    }

    static func parameterValues(_ look: ShowLook) -> [ParameterID: ParameterValue] {
        [
            VisualParameterIDs.circularSpectrumBarCount: .enumeration(String(look.bars)),
            VisualParameterIDs.linearSpectrumOrientation: .enumeration(look.orientation.rawValue),
            VisualParameterIDs.linearSpectrumSpacing: .continuous(look.spacing),
            VisualParameterIDs.bloomEnabled: .boolean(look.glowEnabled),
            VisualParameterIDs.bloomIntensity: .continuous(look.glowIntensity),
            VisualParameterIDs.bloomRadius: .continuous(look.glowRadius),
            VisualParameterIDs.bloomThreshold: .continuous(look.glowThreshold),
        ]
    }

    // MARK: Apply

    /// What a validated document applies. `warnings` are SCN-001's (a missing photo or video).
    static func apply(of document: SceneDocument, warnings: [SceneIssue], registry: ParameterRegistry) -> ShowSceneApply {
        let kinds = document.layers.map(\.kind)
        let drawn: Set<String> = ["spectrum.circular", "spectrum.linear", "photo", "video", "text"]
        let visual: VisualChoice
        if kinds.contains("photo") {
            visual = .photo
        } else if kinds.contains("video") {
            visual = .video
        } else if kinds.contains("text") {
            visual = .text
        } else if kinds.contains("spectrum.linear") {
            visual = .linearSpectrum
        } else if kinds.contains("spectrum.circular") {
            visual = .circularSpectrum
        } else {
            visual = .projectM
        }
        var omitted: [String] = []
        for kind in kinds where !drawn.contains(kind) && !omitted.contains(kind) { omitted.append(kind) }

        let scratch = ParameterStore(registry: registry)
        let present = document.parameters.filter { (entry: (key: ParameterID, value: ParameterValue)) -> Bool in
            appParameterIDs.contains(entry.key)
        }
        let report = scratch.restore(ParameterSnapshot(values: present))
        var parameters: [ParameterID: ParameterValue] = [:]
        for id in report.applied {
            if let value = scratch.value(for: id) { parameters[id] = value }
        }

        var text: TextOverlaySpec?
        if let key = document.layers.first(where: { (l: SceneLayer) -> Bool in l.kind == "text" })?.content.assetKey,
           case let .text(spec)? = document.assets[key]?.kind,
           case let .spec(decoded) = TextOverlaySpec.decodeStored(Data(spec.canonicalBytes)) {
            text = decoded
        }
        let missingMedia = warnings.contains { (issue: SceneIssue) -> Bool in issue.code == .missingAsset }
        let video = SceneVideoLoopBridge.video(in: document)   // MED-003-R8
        return ShowSceneApply(visual: visual, parameters: parameters, text: text, omittedKinds: omitted, missingMedia: missingMedia,
                              videoStoreID: video?.storeID, videoLoop: video?.loop, videoSpeedPercent: video?.speedPercent,
                              slideshow: SceneSlideshowBridge.restore(in: document),   // MED-006
                              logo: document.logo)   // MED-010
    }

    // MARK: JSON

    /// Foundation JSON → SCN-001's value (the text asset is embedded as a JSON value).
    static func sceneJSON(_ data: Data) -> SceneJSON? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return sceneJSON(any: object)
    }

    private static func sceneJSON(any value: Any) -> SceneJSON? {
        switch value {
        case is NSNull:
            return .null
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            if CFNumberIsFloatType(number) { return .double(number.doubleValue) }
            return .integer(number.int64Value)
        case let array as [Any]:
            var out: [SceneJSON] = []
            for element in array {
                guard let converted = sceneJSON(any: element) else { return nil }
                out.append(converted)
            }
            return .array(out)
        case let object as [String: Any]:
            var out: [String: SceneJSON] = [:]
            for (key, element) in object {
                guard let converted = sceneJSON(any: element) else { return nil }
                out[key] = converted
            }
            return .object(out)
        default:
            return nil
        }
    }
}
