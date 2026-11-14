// SceneValidation.swift — every issue of a decoded document (SCN-001-R9, R11; research SCN-001-D4
// to D6; contract C5).
//
// No second definition of validity: kind limits are the layer kinds' own `maximumInstances`
// (CMP-002), materials the SHD-001 catalog, text the MED-009 decoder, graphs the SHD-011 importer,
// parameter values a scratch MOD-001 `ParameterStore`, bindings a scratch MOD-002
// `AudioFeatureModulator`, expressions the SHD-009 compiler (compiled, never evaluated) and the
// modulation graph MOD-014's validator. Order: scene ID, name, layers, groups (CMP-011), assets,
// parameters, bindings, modulation.
import CameraLayer
import Compositor
import Foundation
import GeneratorGraph
import GeneratorGraphImport
import ImageLayer
import ParameterExpression
import ParameterGraph
import ProceduralMaterials
import SpectrumLayers
import TextLayer
import VideoLayer

/// Whether the app's stores hold a referenced photo or video (MED-001, MED-002). The app answers
/// from `PhotoStore`/`VideoStore` (SCN-002); tests use a fake.
public protocol SceneAssetAvailability: Sendable {
    func containsPhoto(storeID: String) -> Bool
    func containsVideo(storeID: String) -> Bool
}

extension SceneLayerContent {
    /// The live layer-stack kind (nil for unknown kinds, which are not shown).
    public var layerKind: LayerKind? {
        switch self {
        case .camera: .camera
        case .circularSpectrum: .circularSpectrum
        case .linearSpectrum: .linearSpectrum
        case .photo: .photo
        case .video: .video
        case .text: .text
        case .material: .material
        case .generatorGraph: .generatorGraph
        case .unknown: nil
        }
    }
}

extension SceneDocument {
    /// The SCN-001 name rule, shared with SCN-003's rename and duplicate (SceneEditing.swift): 1…120
    /// characters (grapheme clusters) once white space is trimmed from both ends, and no control
    /// characters (which also excludes line breaks and tabs).
    public static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= SceneLimits.maximumNameLength else { return false }
        return !name.unicodeScalars.contains { (s: Unicode.Scalar) -> Bool in s.properties.generalCategory == .control }
    }

    /// The text to store for a typed name: trimmed, or nil when it breaks the rule.
    public static func normalizedName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidName(trimmed) ? trimmed : nil
    }

    /// Every issue, in contract C5 order. Decode warnings are returned by `decode` separately.
    public func validate(registry: ParameterRegistry, assets availability: (any SceneAssetAvailability)? = nil) -> [SceneIssue] {
        var issues: [SceneIssue] = []
        validateHeader(into: &issues)
        validateLayers(into: &issues)
        issues += analyzeGroups().issues   // CMP-011
        validateAssets(availability, into: &issues)
        validateParameters(registry, into: &issues)
        validateModulation(registry, into: &issues)
        return issues
    }

    private func validateHeader(into issues: inout [SceneIssue]) {
        if !Self.isCanonicalUUID(id) {
            issues.append(SceneIssue(.invalidSceneID, path: "$.id", "The scene ID \"\(id)\" is not an uppercase UUID."))
        }
        if !Self.isValidName(name) {   // one rule with SCN-003's rename and duplicate (SceneEditing.swift)
            issues.append(SceneIssue(.invalidName, path: "$.name",
                                     "The scene name must be 1…\(SceneLimits.maximumNameLength) characters without control characters."))
        }
    }

    private func validateLayers(into issues: inout [SceneIssue]) {
        var firstIndexByInstance: [UInt64: Int] = [:]
        var countByKind: [String: Int] = [:]
        for (i, layer) in layers.enumerated() {
            let path = "$.layers[\(i)]"
            if layer.instance == 0 || layer.instance > SceneLimits.maximumInstanceID {
                issues.append(SceneIssue(.instanceOutOfRange, path: path + ".instance",
                                         "Layer \(i) has instance ID \(layer.instance); IDs are 1…\(SceneLimits.maximumInstanceID)."))
            }
            if let j = firstIndexByInstance[layer.instance] {
                issues.append(SceneIssue(.duplicateInstance, path: path + ".instance",
                                         "Layer \(i) uses instance ID \(layer.instance), already used by layer \(j)."))
            } else {
                firstIndexByInstance[layer.instance] = i
            }
            let n = (countByKind[layer.kind] ?? 0) + 1
            countByKind[layer.kind] = n
            if let limit = layer.content.layerKind?.maximumInstances, n > limit {
                issues.append(SceneIssue(.kindLimit, path: path + ".kind",
                                         "Layer \(i) is \"\(layer.kind)\" layer number \(n); a scene holds at most \(limit)."))
            }
            for name in layer.values.keys.sorted(by: SceneJSONWriter.utf8Precedes) where !Self.isValidValueName(name) {
                issues.append(SceneIssue(.invalidValueName, path: path + ".values",
                                         "Layer \(i) has a value named \"\(name)\"; names are 1…\(SceneLimits.maximumValueNameBytes) bytes without control characters."))
            }
            if case let .unknown(kind) = layer.content {
                issues.append(SceneIssue(.unknownLayerKind, path: path + ".kind",
                                         "Layer \(i) has the unknown kind \"\(kind)\"; it is kept but not shown."))
            }
            if LayerBlendMode(rawValue: layer.composite.blendMode) == nil {   // CMP-004: the six names are drawn
                issues.append(SceneIssue(.unsupportedBlendMode, path: path + ".composite.blend",
                                         "Layer \(i) uses the blend mode \"\(layer.composite.blendMode)\", which this version draws as normal."))
            }
            if let fit = layer.composite.fit, LayerFitMode(rawValue: fit.mode) == nil {   // CMP-006: four names are drawn
                issues.append(SceneIssue(.unsupportedFitMode, path: path + ".composite.fit.mode",
                                         "Layer \(i) uses the fit mode \"\(fit.mode)\", which this version draws as the layer's default."))
            }
            if let mask = layer.composite.mask, mask.layerMask == nil {   // CMP-007: three shapes are drawn
                issues.append(SceneIssue(.unsupportedMaskShape, path: path + ".composite.mask.shape",
                                         "Layer \(i) uses the mask shape \"\(mask.shape)\", which this version draws unmasked."))
            }
            if case let .material(id) = layer.content, ProceduralMaterialCatalog.material(withID: id) == nil {
                issues.append(SceneIssue(.unknownMaterial, path: path + ".content.material",
                                         "Layer \(i) uses the unknown material \"\(id)\"."))
            }
            if let key = layer.content.assetKey, let required = layer.content.requiredAssetType {
                if let asset = assets[key] {
                    if asset.kind.typeName != required {
                        issues.append(SceneIssue(.assetTypeMismatch, path: path + ".content.asset",
                                                 "Layer \(i) (\(layer.kind)) refers to the asset \"\(key)\", which is a \(asset.kind.typeName) asset."))
                    }
                } else {
                    issues.append(SceneIssue(.danglingAsset, path: path + ".content.asset",
                                             "Layer \(i) refers to the asset \"\(key)\", which the scene does not define."))
                }
            }
        }
    }

    static func isValidValueName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= SceneLimits.maximumValueNameBytes
            && !name.unicodeScalars.contains { (s: Unicode.Scalar) -> Bool in s.properties.generalCategory == .control }
    }

    private func validateAssets(_ availability: (any SceneAssetAvailability)?, into issues: inout [SceneIssue]) {
        let used = Set(layers.compactMap { (l: SceneLayer) -> String? in l.content.assetKey })
        for key in assets.keys.sorted(by: SceneJSONWriter.utf8Precedes) {
            guard let asset = assets[key] else { continue }
            let path = ScenePath.key("$.assets", key)
            if !Self.isValidAssetKey(key) {
                issues.append(SceneIssue(.invalidAssetKey, path: path,
                                         "The asset key \"\(key)\" must start with a lowercase ASCII letter and hold only ASCII letters and digits (at most \(SceneLimits.maximumAssetKeyBytes))."))
            }
            switch asset.kind {
            case let .photo(id), let .video(id):
                if !Self.isCanonicalUUID(id) {
                    issues.append(SceneIssue(.invalidStoreID, path: path + ".storeID",
                                             "Asset \"\(key)\" has the store ID \"\(id)\"; store IDs are uppercase UUIDs, never paths."))
                } else if let availability {
                    let present = if case .photo = asset.kind { availability.containsPhoto(storeID: id) } else { availability.containsVideo(storeID: id) }
                    if !present {
                        issues.append(SceneIssue(.missingAsset, path: path,
                                                 "Asset \"\(key)\" (\(asset.kind.typeName) \(id)) is not on this device; its layer draws nothing until it is restored."))
                    }
                }
            case let .text(spec):
                switch TextOverlaySpec.decodeStored(Data(spec.canonicalBytes)) {
                case .spec: break
                case .damaged:
                    issues.append(SceneIssue(.invalidTextAsset, path: path + ".spec", "Text asset \"\(key)\" is damaged."))
                case let .unsupportedVersion(v):
                    issues.append(SceneIssue(.invalidTextAsset, path: path + ".spec",
                                             "Text asset \"\(key)\" uses text format version \(v), which this version cannot read."))
                }
            case let .generatorGraph(document):
                do {
                    _ = try GeneratorGraphImporter.importGraph(Data(document.canonicalBytes))
                } catch {
                    issues.append(SceneIssue(.invalidGraphAsset, path: path + ".document",
                                             "Generator graph asset \"\(key)\" is refused: \(error.message)"))
                }
            case let .unknown(type):
                issues.append(SceneIssue(.unknownAssetType, path: path + ".type",
                                         "Asset \"\(key)\" has the unknown type \"\(type)\"; it is kept but not used."))
            }
            if asset.kind.isKnown, !used.contains(key) {
                issues.append(SceneIssue(.unusedAsset, path: path, "Asset \"\(key)\" is not used by any layer; it is kept."))
            }
        }
    }

    /// MOD-001 restore semantics (research SCN-001-D5), checked on a scratch store.
    private func validateParameters(_ registry: ParameterRegistry, into issues: inout [SceneIssue]) {
        let store = ParameterStore(registry: registry)
        for id in parameters.keys.sorted() {
            guard let value = parameters[id] else { continue }
            let path = ScenePath.key("$.parameters", id.rawValue)
            if let problem = id.syntaxProblem {
                issues.append(SceneIssue(.malformedParameterID, path: path, "The parameter ID \"\(id)\" is ill-formed: \(problem)."))
                continue
            }
            guard registry.contains(id) else {
                issues.append(SceneIssue(.orphanedParameter, path: path,
                                         "\"\(id)\" is not a parameter of this version; its value is kept but not applied."))
                continue
            }
            do {
                let stored = try store.set(value, for: id)
                if stored != value {
                    issues.append(SceneIssue(.parameterClamped, path: path,
                                             "\"\(id)\" value \(value) is outside its range; it is applied as \(stored)."))
                }
            } catch {
                issues.append(SceneIssue(.rejectedParameter, path: path, "\(error.description); the current value is kept."))
            }
        }
    }

    /// MOD-013 per-edge restore (contract M3, M4): bindings, generator declarations, connections.
    private func validateModulation(_ registry: ParameterRegistry, into issues: inout [SceneIssue]) {
        issues += restoreModulation(registry: registry).issues
    }
}

extension SceneAssetKind {
    var isKnown: Bool { if case .unknown = self { false } else { true } }
}
