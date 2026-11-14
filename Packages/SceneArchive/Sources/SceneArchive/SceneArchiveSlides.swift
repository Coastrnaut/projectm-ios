// SceneArchiveSlides.swift — a photo asset's MED-006 slideshow pictures in a scene archive (SCN-014-R1,
// R3, R4; research SCN-014-D1; contract specs/187-scn-014-dependency-pack/contracts/scene-pack.md P1, P2).
//
// The scene names its slides by store UUID inside the photo asset's `slideshow` object; the archive packs
// each picture once per position as `assets/<key>-slide-<NN>.<ext>` (NN = 01…20) and lists it in the
// optional manifest field `slides`. A pack without slides has no `slides` field (FILE-001's bytes).
// Remapping replaces only `slideshow.storeIDs`, keeping every other field of the slideshow and the asset.
import Foundation
import SceneFormat

/// One slideshow picture packed or read. `index` is the 1-based position in the slideshow.
public struct SceneArchiveSlide: Sendable, Equatable {
    public var key: String
    public var index: Int
    /// `png` or `jpg`.
    public var fileExtension: String
    public var data: Data

    public init(key: String, index: Int, fileExtension: String, data: Data) {
        self.key = key
        self.index = index
        self.fileExtension = fileExtension
        self.data = data
    }

    public var path: String { SceneArchiveFormat.slidePath(key: key, index: index, fileExtension: fileExtension) }
}

/// The manifest's record of one slide.
public struct SceneArchiveSlideRecord: Codable, Sendable, Equatable {
    public var key: String
    public var index: Int
    public var path: String

    public init(key: String, index: Int, path: String) {
        self.key = key
        self.index = index
        self.path = path
    }
}

extension SceneArchiveFormat {
    /// MED-006's limit: at most 20 slides.
    public static let maximumSlides = SceneSlideshow.maximumStoreIDs

    /// `assets/<key>-slide-<NN>.<ext>`; keys are ASCII letters and digits, so the path stays in the folder
    /// and never equals an asset path (`assets/<key>.<ext>`).
    public static func slidePath(key: String, index: Int, fileExtension: String) -> String {
        let number = index < 10 ? "0" + String(index) : String(index)
        return assetFolder + key + "-slide-" + number + "." + fileExtension
    }
}

extension SceneDocument {
    /// The photo asset's slideshow identifiers (key, identifiers in order), for photo assets whose
    /// slideshow reads and names at least one picture. Sorted by key.
    public var slideStoreIDs: [(key: String, storeIDs: [String])] {
        assets.keys.sorted().compactMap { (key: String) -> (key: String, storeIDs: [String])? in
            guard let ids = assets[key]?.photoSlideshow?.storeIDs, !ids.isEmpty else { return nil }
            return (key, ids)
        }
    }

    /// The document with each listed photo asset's `slideshow.storeIDs` replaced (asset key → new
    /// identifiers in order). Other slideshow fields, the asset's other fields and keys not naming a photo
    /// asset with a slideshow object are left as they are.
    public func remappingSlideIDs(_ storeIDs: [String: [String]]) -> SceneDocument {
        var copy = self
        for (key, ids) in storeIDs {
            guard var asset = copy.assets[key], case .photo = asset.kind,
                  var object = asset.extra[SceneSlideshow.key]?.objectValue else { continue }
            object["storeIDs"] = .array(ids.map { (id: String) -> SceneJSON in .string(id) })
            asset.extra[SceneSlideshow.key] = .object(object)
            copy.assets[key] = asset
        }
        return copy
    }
}
