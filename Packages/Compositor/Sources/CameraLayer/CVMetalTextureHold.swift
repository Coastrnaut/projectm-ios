// CVMetalTextureHold.swift — keeps a Core Video Metal texture and the cache it came from alive
// together (camera and video pictures).
//
// Releasing a `CVMetalTexture` reports its backing back to the `CVMetalTextureCache` that made it
// (`CVMetalTextureCache::bufferBackingNotInUse`), but the texture does not keep that cache alive for
// the whole release. When the cache's owner (a video reader on its decode thread, or the camera
// provider replacing its cache) dropped the cache while the render thread released the last picture,
// the cache was finalized during that report and the render thread crashed with SIGSEGV in
// `CFArrayAppendValue` (CAM-013 merge gate, 2026-11-14; reproduced by
// `VideoLayerTests.testPictureReleaseRacesItsReadersRelease`). A hold retains the cache and
// releases the texture first, so a cache can only be finalized after its last picture's release
// has finished, on whichever thread that is.
#if canImport(CoreVideo) && canImport(Metal) && !COMPOSITOR_NO_METAL
import CoreVideo

/// Owns one `CVMetalTexture` and retains its cache until the texture's release has finished.
/// Immutable after init; released on any thread.
public final class CVMetalTextureHold: @unchecked Sendable {
    private var texture: CVMetalTexture?
    private let cache: CVMetalTextureCache

    public init(texture: CVMetalTexture, cache: CVMetalTextureCache) {
        self.texture = texture
        self.cache = cache
    }

    deinit {
        texture = nil   // releases the texture while `cache` is still retained; the cache goes after
    }
}
#endif
