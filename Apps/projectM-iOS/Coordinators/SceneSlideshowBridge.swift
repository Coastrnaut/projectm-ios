// SceneSlideshowBridge.swift — the image slideshow ↔ a scene's photo asset `slideshow` field (MED-006-R12;
// research MED-006-D7). Pure functions; scenes, undo states and show cues share them.
//
// * Capture: the photo asset is written when a photo is stored or the slideshow has slides (its store ID
//   is the photo, else the first slide), with the field when there is a slideshow to record.
// * Restore: only a document with a photo layer changes the slideshow (`SceneSlideshowRestore`); its
//   field absent turns the slideshow off. Scenes of other visuals leave it as it is.
import Foundation
import SceneFormat

/// A photo layer's slideshow as read from a document (`value` nil: the field is absent).
struct SceneSlideshowRestore: Sendable, Equatable {
    var value: SceneSlideshow?
}

enum SceneSlideshowBridge {
    /// The photo asset for a captured scene (nil: nothing to show).
    static func photoAsset(photoID: UUID?, slideshow: SceneSlideshow?) -> SceneAsset? {
        let firstSlide: String? = slideshow?.storeIDs.first
        guard let storeID = photoID?.uuidString ?? firstSlide else { return nil }
        var asset = SceneAsset.photo(storeID: storeID)
        asset.photoSlideshow = slideshow
        return asset
    }

    /// The first photo layer's slideshow (nil: the document has no photo layer).
    static func restore(in document: SceneDocument) -> SceneSlideshowRestore? {
        guard let key = document.layers.first(where: { (l: SceneLayer) -> Bool in l.kind == "photo" })?.content.assetKey,
              let asset = document.assets[key], case .photo = asset.kind else { return nil }
        return SceneSlideshowRestore(value: asset.photoSlideshow)
    }
}
