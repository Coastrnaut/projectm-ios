// SceneTemplates.swift — SCN-011 (specs/181-scn-011-template-gallery; SCN-011-R1 to R5; contract T1, T2, T4;
// research SCN-011-D2 to D4): bundled starter scenes and their independent copies.
//
// * The app bundles a folder `SceneTemplates/` holding `manifest.json` and one SCN-001 `.scene.json` per
//   template scene. `SceneTemplateCatalog.load(directory:)` reads it (only reads): a template is offered
//   only when every scene file decodes with no warnings, uses only the native layer kinds, and every asset
//   key is listed in the manifest with an allowed licence (SPDX `MIT`, the project's own). Anything else
//   leaves that template out (`skipped`); a bad manifest gives an empty catalog.
// * `ShowStore.storeTemplateCopy` writes SCN-001 `duplicated(newID:name:)` of a template scene under a new
//   scene ID (never over a stored file). The template's folder is never written, so editing or deleting a
//   copy cannot reach the template or another copy.
// Foundation only (builds on Linux). No networking; nothing read is executed.
import Foundation
import SceneFormat
import ShowControl

/// One asset of a template scene and its licence (contract T4).
public struct SceneTemplateAssetRecord: Codable, Sendable, Hashable {
    public let key: String
    public let kind: String
    public let source: String
    public let licence: String

    public init(key: String, kind: String, source: String, licence: String) {
        self.key = key
        self.kind = kind
        self.source = source
        self.licence = licence
    }
}

public struct SceneTemplateTransitionRecord: Codable, Sendable, Hashable {
    public let type: String
    public let seconds: Double
}

public struct SceneTemplateSceneRecord: Codable, Sendable, Hashable {
    public let file: String
    public let label: String
    public let assets: [SceneTemplateAssetRecord]
    public let transition: SceneTemplateTransitionRecord?
}

public struct SceneTemplateRecord: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let summary: String
    public let symbol: String
    public let tags: [String]
    public let scenes: [SceneTemplateSceneRecord]
}

/// `manifest.json` (data-model.md).
public struct SceneTemplateManifest: Codable, Sendable, Hashable {
    public static let formatName = "projectm-ios.scene-templates"
    public static let currentVersion = 1
    public static let fileName = "manifest.json"

    public let format: String
    public let version: Int
    public let licenceNote: String?
    public let templates: [SceneTemplateRecord]
}

/// A template scene ready to copy.
public struct SceneTemplateScene: Sendable, Hashable {
    public let label: String
    public let document: SceneDocument
    public let transition: ShowCueTransition?
    /// The bundled file (read-only).
    public let file: URL
    public let assets: [SceneTemplateAssetRecord]
}

public struct SceneTemplate: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let symbol: String
    public let tags: [String]
    public let scenes: [SceneTemplateScene]
}

public struct SceneTemplateCatalog: Sendable {
    /// SCN-011-R2: the native kinds a cue shows (no camera, photo, video, material or generator graph).
    public static let allowedLayerKinds: Set<String> = ["spectrum.circular", "spectrum.linear", "text"]
    /// SCN-011-R3: the project's own licence (repository `LICENSE`).
    public static let allowedLicences: Set<String> = ["MIT"]
    public static let maximumScenesPerTemplate = 8
    public static let maximumSummaryLength = 200

    /// Offered templates, in manifest order.
    public let templates: [SceneTemplate]
    /// IDs of templates left out (unreadable, warnings, unlisted assets, or not allowed).
    public let skipped: [String]

    public init(templates: [SceneTemplate], skipped: [String]) {
        self.templates = templates
        self.skipped = skipped
    }

    public static let empty = SceneTemplateCatalog(templates: [], skipped: [])

    public func template(_ id: String) -> SceneTemplate? {
        templates.first { (template: SceneTemplate) -> Bool in template.id == id }
    }

    /// Contract T1. Reads only.
    public static func load(directory: URL) -> SceneTemplateCatalog {
        let manifestURL = directory.appendingPathComponent(SceneTemplateManifest.fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(SceneTemplateManifest.self, from: data),
              manifest.format == SceneTemplateManifest.formatName, manifest.version == SceneTemplateManifest.currentVersion else {
            return .empty
        }
        var templates: [SceneTemplate] = []
        var skipped: [String] = []
        var seenIDs: Set<String> = []
        var seenSceneIDs: Set<String> = []
        for record in manifest.templates {
            guard !seenIDs.contains(record.id), let template = load(record, directory: directory),
                  seenSceneIDs.isDisjoint(with: template.scenes.map(\.document.id)) else {
                skipped.append(record.id)
                continue
            }
            seenIDs.insert(record.id)
            for scene in template.scenes { seenSceneIDs.insert(scene.document.id) }
            templates.append(template)
        }
        return SceneTemplateCatalog(templates: templates, skipped: skipped)
    }

    private static func load(_ record: SceneTemplateRecord, directory: URL) -> SceneTemplate? {
        guard isTemplateID(record.id),
              let name = SceneDocument.normalizedName(record.name), name == record.name,
              !record.summary.isEmpty, record.summary.count <= maximumSummaryLength, !record.symbol.isEmpty,
              (1...maximumScenesPerTemplate).contains(record.scenes.count) else { return nil }
        var scenes: [SceneTemplateScene] = []
        for sceneRecord in record.scenes {
            guard let scene = loadScene(sceneRecord, directory: directory) else { return nil }
            scenes.append(scene)
        }
        return SceneTemplate(id: record.id, name: name, summary: record.summary, symbol: record.symbol, tags: record.tags,
                             scenes: scenes)
    }

    private static func loadScene(_ record: SceneTemplateSceneRecord, directory: URL) -> SceneTemplateScene? {
        guard isPlainFileName(record.file), let label = ShowCueList.normalizedLabel(record.label), label == record.label else { return nil }
        let file = directory.appendingPathComponent(record.file, isDirectory: false)
        guard let data = try? Data(contentsOf: file), let decoded = try? SceneDocument.decode([UInt8](data)),
              decoded.warnings.isEmpty, !decoded.migration.migrated else { return nil }
        let document = decoded.document
        guard ShowCueList.isSceneID(document.id), licencesCover(document, records: record.assets) else { return nil }
        var transition: ShowCueTransition?
        if let entry = record.transition {
            guard let type = ShowTransitionType(text: entry.type), type.isKnown,
                  let made = try? ShowCueTransition(type: type, durationSeconds: entry.seconds) else { return nil }
            transition = made
        }
        return SceneTemplateScene(label: label, document: document, transition: transition, file: file, assets: record.assets)
    }

    /// Contract T4: only native layer kinds; every asset key listed exactly once with an allowed licence and a
    /// source, and no record for a key the scene does not have.
    public static func licencesCover(_ document: SceneDocument, records: [SceneTemplateAssetRecord]) -> Bool {
        guard document.layers.allSatisfy({ (layer: SceneLayer) -> Bool in allowedLayerKinds.contains(layer.kind) }) else { return false }
        let keys: [String] = records.map(\.key)
        guard Set(keys).count == keys.count, Set(keys) == Set(document.assets.keys) else { return false }
        return records.allSatisfy { (record: SceneTemplateAssetRecord) -> Bool in
            allowedLicences.contains(record.licence) && !record.source.isEmpty && record.kind == "text"
                && document.assets[record.key].map { (asset: SceneAsset) -> Bool in
                    if case .text = asset.kind { return true }
                    return false
                } == true
        }
    }

    /// Lowercase letters, digits and hyphens, 1…64 characters.
    static func isTemplateID(_ text: String) -> Bool {
        guard (1...64).contains(text.count) else { return false }
        return text.unicodeScalars.allSatisfy { (scalar: Unicode.Scalar) -> Bool in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
    }

    /// A file directly in the templates folder ending in `.scene.json`.
    static func isPlainFileName(_ text: String) -> Bool {
        text.hasSuffix(ShowStore.sceneFileSuffix) && !text.contains("/") && !text.contains("\\") && !text.hasPrefix(".")
    }
}

extension ShowStore {
    /// Contract T2: stores a copy of `template` under `newID` named `name` (canonical bytes) and returns it.
    /// Refuses an invalid ID or name and an ID that already has a file. Never writes the template's file.
    @discardableResult
    public func storeTemplateCopy(_ template: SceneDocument, newID: String, name: String) throws(ShowSceneEditError) -> SceneDocument {
        let copy: SceneDocument
        do {
            copy = try template.duplicated(newID: newID, name: name)
        } catch {
            throw .invalid(error)
        }
        guard ShowCueList.isSceneID(newID) else { throw .writeFailed }
        guard !FileManager.default.fileExists(atPath: sceneFile(newID).path) else { throw .sceneIDTaken(newID) }
        do throws(ShowStoreError) {
            try saveScene(copy)
        } catch {
            throw .writeFailed
        }
        return copy
    }
}
