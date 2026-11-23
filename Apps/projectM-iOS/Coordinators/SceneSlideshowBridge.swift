// SceneSlideshowBridge.swift — the image slideshow ↔ a scene's photo asset `slideshow` field (MED-006-R12;
// research MED-006-D7). Pure functions; scenes, undo states and show cues share them.
//
// * Capture: the photo asset is written when a photo is stored or the slideshow has slides (its store ID
//   is the photo, else the first slide), with the field when there is a slideshow to record.
// * Restore: only a document with a photo layer changes the slideshow (`SceneSlideshowRestore`); its
//   field absent turns the slideshow off. Scenes of other visuals leave it as it is.
import Compositor
import Foundation
import SceneFormat

/// A photo layer's slideshow as read from a document (`value` nil: the field is absent).
struct SceneSlideshowRestore: Sendable, Equatable {
    var value: SceneSlideshow?
    /// MED-007-R10: the photo asset's Ken Burns movement (nil: absent or malformed, Ken Burns off).
    var kenBurns: KenBurnsMotion? = nil
}

enum SceneSlideshowBridge {
    /// The photo asset for a captured scene (nil: nothing to show).
    static func photoAsset(photoID: UUID?, slideshow: SceneSlideshow?, kenBurns: KenBurnsMotion? = nil) -> SceneAsset? {
        let firstSlide: String? = slideshow?.storeIDs.first
        guard let storeID = photoID?.uuidString ?? firstSlide else { return nil }
        var asset = SceneAsset.photo(storeID: storeID)
        asset.photoSlideshow = slideshow
        asset.photoKenBurns = kenBurns   // MED-007
        return asset
    }

    /// SHOW-001 Clarification 2026-11-23: the first photo layer's own photo (nil: no photo layer, or its asset names
    /// only the slideshow's first picture, MED-006: a scene without a photo of its own).
    static func photoStoreID(in document: SceneDocument) -> String? {
        guard let key = document.layers.first(where: { (l: SceneLayer) -> Bool in l.kind == "photo" })?.content.assetKey,
              let asset = document.assets[key], case let .photo(storeID) = asset.kind else { return nil }
        if asset.photoSlideshow?.storeIDs.contains(storeID) == true { return nil }
        return storeID
    }

    /// The first photo layer's slideshow (nil: the document has no photo layer).
    static func restore(in document: SceneDocument) -> SceneSlideshowRestore? {
        guard let key = document.layers.first(where: { (l: SceneLayer) -> Bool in l.kind == "photo" })?.content.assetKey,
              let asset = document.assets[key], case .photo = asset.kind else { return nil }
        return SceneSlideshowRestore(value: asset.photoSlideshow, kenBurns: asset.photoKenBurns)
    }
}
