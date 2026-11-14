// SceneMediaReferences.swift — MED-013 (contract specs/146-med-013-media-relinking/contracts/media-relink.md
// L3): every stored-media identifier a scene names, and replacing one identifier by another.
//
// Photo folder roles: a `photo` asset's `storeID` (MED-001), its slideshow's `storeIDs` (MED-006) and a
// `logo` asset's `storeID` (MED-010). Video folder role: a `video` asset's `storeID` (MED-002).
// Replacing keeps every other field and every unknown field verbatim (the asset's `extra`, the
// slideshow's other values); a malformed slideshow value (which reads as absent) is left as it is.
// Pure value code; no files.

/// The app's two content-addressed media folders.
public enum SceneMediaStore: String, Sendable, Hashable, CaseIterable, Comparable {
    case photos, videos

    public static func < (a: SceneMediaStore, b: SceneMediaStore) -> Bool { a.rawValue < b.rawValue }
}

public enum SceneMediaRole: String, Sendable, Hashable {
    case photo, slide, logo, video

    public var store: SceneMediaStore { self == .video ? .videos : .photos }
}

/// One identifier named by one asset of a scene.
public struct SceneMediaReference: Sendable, Hashable {
    public var assetKey: String
    public var role: SceneMediaRole
    public var storeID: String

    public init(assetKey: String, role: SceneMediaRole, storeID: String) {
        self.assetKey = assetKey
        self.role = role
        self.storeID = storeID
    }

    public var store: SceneMediaStore { role.store }
}

extension SceneDocument {
    /// Every media reference, by asset key (then the asset's own identifier, then its slides in order).
    public var mediaReferences: [SceneMediaReference] {
        var result: [SceneMediaReference] = []
        for key in assets.keys.sorted() {
            guard let asset = assets[key] else { continue }
            switch asset.kind {
            case let .photo(storeID):
                result.append(SceneMediaReference(assetKey: key, role: .photo, storeID: storeID))
                for slide in asset.photoSlideshow?.storeIDs ?? [] {
                    result.append(SceneMediaReference(assetKey: key, role: .slide, storeID: slide))
                }
            case let .logo(storeID):
                result.append(SceneMediaReference(assetKey: key, role: .logo, storeID: storeID))
            case let .video(storeID):
                result.append(SceneMediaReference(assetKey: key, role: .video, storeID: storeID))
            default:
                break
            }
        }
        return result
    }

    /// The identifiers of one store this scene names.
    public func mediaIDs(in store: SceneMediaStore) -> Set<String> {
        Set(mediaReferences.filter { (r: SceneMediaReference) -> Bool in r.store == store }.map(\.storeID))
    }

    /// This scene with every reference to `old` in `store`'s roles replaced by `new`, and how many were
    /// replaced (0: the document is unchanged).
    public func replacingMediaReference(store: SceneMediaStore, from old: String, to new: String) -> (document: SceneDocument, replaced: Int) {
        guard old != new else { return (self, 0) }
        var copy = self
        var replaced = 0
        for key in assets.keys.sorted() {
            guard var asset = copy.assets[key] else { continue }
            let count = Self.replace(in: &asset, store: store, from: old, to: new)
            if count > 0 {
                copy.assets[key] = asset
                replaced += count
            }
        }
        return (replaced > 0 ? copy : self, replaced)
    }

    private static func replace(in asset: inout SceneAsset, store: SceneMediaStore, from old: String, to new: String) -> Int {
        var count = 0
        switch (asset.kind, store) {
        case let (.photo(storeID), .photos):
            var slideshow = asset.photoSlideshow
            if storeID == old {
                asset.kind = .photo(storeID: new)
                count += 1
            }
            if var value = slideshow, value.storeIDs.contains(old) {
                value.storeIDs = value.storeIDs.map { (id: String) -> String in id == old ? new : id }
                count += slideshow?.storeIDs.filter { (id: String) -> Bool in id == old }.count ?? 0
                slideshow = value
                asset.photoSlideshow = slideshow
            }
        case let (.logo(storeID), .photos) where storeID == old:
            asset.kind = .logo(storeID: new)
            count += 1
        case let (.video(storeID), .videos) where storeID == old:
            asset.kind = .video(storeID: new)
            count += 1
        default:
            break
        }
        return count
    }
}
