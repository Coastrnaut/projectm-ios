// SceneVideoLoopBridge.swift — the stored video's loop region ↔ a scene's video asset `loop`
// (MED-003-R8; research MED-003-D6), and its playback speed ↔ the asset's `speedPercent` (MED-004-R7).
// Pure functions; scenes, undo states and show cues share them.
import Foundation
import SceneFormat
import VideoLayer

enum SceneVideoLoopBridge {
    static func scene(_ region: VideoLoopRegion?) -> SceneVideoLoop? {
        region.map { (r: VideoLoopRegion) -> SceneVideoLoop in
            SceneVideoLoop(inMilliseconds: r.inMilliseconds, outMilliseconds: r.outMilliseconds)
        }
    }

    static func region(_ loop: SceneVideoLoop?) -> VideoLoopRegion? {
        loop.map { (l: SceneVideoLoop) -> VideoLoopRegion in
            VideoLoopRegion(inMilliseconds: l.inMilliseconds, outMilliseconds: l.outMilliseconds)
        }
    }

    /// The first video layer's stored-video ID, loop and speed (MED-004; nil: 1×) (nil: no video layer
    /// or no stored video).
    static func video(in document: SceneDocument) -> (storeID: String, loop: SceneVideoLoop?, speedPercent: Int?)? {
        guard let key = document.layers.first(where: { (l: SceneLayer) -> Bool in l.kind == "video" })?.content.assetKey,
              let asset = document.assets[key], case let .video(storeID) = asset.kind else { return nil }
        return (storeID, asset.videoLoop, asset.videoSpeedPercent)
    }

    /// The video asset for a captured scene, with its loop and speed (MED-004, nil at 1×) when saved.
    static func asset(storeID: UUID, loop: SceneVideoLoop?, speedPercent: Int? = nil) -> SceneAsset {
        var asset = SceneAsset.video(storeID: storeID.uuidString)
        asset.videoLoop = loop
        asset.videoSpeedPercent = speedPercent
        return asset
    }
}
