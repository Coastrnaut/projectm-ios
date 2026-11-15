// AnimatedPicture.swift — the decoded frames of one stored animation for the photo layer (MED-008-R6, R8, R9;
// specs/257-med-008-animated-images, contracts/animated-image.md A2, A3; research MED-008-D5 to D7).
//
// * Made on the layer's load queue from the stored bytes: the ImageIO source (caching off), the facts, both timelines
//   (Reduce flashing off and on, built once so the render path never allocates), the decoded size that fits the byte
//   budget (`AnimatedFrameBudget.decodedSize`), and frame 0, decoded with it (`frame0`, the layer's "ready" picture).
// * Frames are decoded on demand on one serial queue: `request(i)` enqueues a frame that is neither resident nor in
//   flight. A decode reserves four accounted frame sizes in the cache first (evicting the least recently used frame,
//   never frame 0 or the frame on screen), then commits one. Textures are single-level `rgba8Unorm_srgb` holding
//   premultiplied texels (`PremultipliedSRGB`), so a decode needs no GPU work.
// * The render thread only ever tries the lock (`withLockIfAvailable`): `texture(at:)` returns the resident frame and
//   pins it as the frame on screen; `request` skips when the lock is busy (the next frame asks again).
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Foundation
import ImageIO
import Metal
import os

final class AnimatedPicture: @unchecked Sendable {
    struct State {
        var cache: AnimatedFrameCache<MTLTexture>
        var inFlight: Set<Int> = []
        var decodes = 0
    }

    let facts: AnimatedImageFacts
    let width: Int
    let height: Int
    let frameBytes: Int
    let frame0: MTLTexture
    let standardTimeline: AnimationTimeline
    let reducedFlashingTimeline: AnimationTimeline
    private let source: CGImageSource
    private let device: MTLDevice
    private let queue = DispatchQueue(label: "MED-008 frame decode", qos: .userInitiated)
    private let lock: OSAllocatedUnfairLock<State>

    var frameCount: Int { facts.frameCount }

    /// The animation in `data`, or nil when it is not animated. Throws when its first frame cannot be decoded.
    static func make(_ data: Data, device: MTLDevice, budget: Int, limits: ImageImportLimits) throws(ImageImportError) -> AnimatedPicture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let facts = AnimatedImageProbe.facts(source) else { return nil }
        try ImageStructureCheck.check(data, limits: limits)   // MED-014: PNG chunks and CRCs before decoding
        guard !facts.width.multipliedReportingOverflow(by: facts.height).overflow,
              facts.width * facts.height <= limits.maxPixelCount else { throw .tooManyPixels }
        let side: Int = min(limits.maxStoredLongestSide, AnimatedImportLimits.standard.maxStoredLongestSide)
        let size: (width: Int, height: Int) = AnimatedFrameBudget.decodedSize(width: facts.width, height: facts.height,
                                                                              budget: budget, maxSide: side)
        let frameBytes: Int = AnimatedFrameBudget.accountedFrameBytes(width: size.width, height: size.height)
        var cache = AnimatedFrameCache<MTLTexture>(budgetBytes: budget)
        let reserve: Int = frameBytes * AnimatedFrameBudget.reserveFrames
        guard cache.reserve(reserve),
              let first = Self.decodeTexture(source, index: 0, width: size.width, height: size.height, device: device) else {
            throw .damaged
        }
        cache.commit(0, payload: first, bytes: frameBytes, reserved: reserve)
        return AnimatedPicture(source: source, facts: facts, size: size, frameBytes: frameBytes, frame0: first,
                               cache: cache, device: device)
    }

    private init(source: CGImageSource, facts: AnimatedImageFacts, size: (width: Int, height: Int), frameBytes: Int,
                 frame0: MTLTexture, cache: AnimatedFrameCache<MTLTexture>, device: MTLDevice) {
        self.source = source
        self.facts = facts
        width = size.width
        height = size.height
        self.frameBytes = frameBytes
        self.frame0 = frame0
        self.device = device
        standardTimeline = AnimationTimeline(rawDelays: facts.rawDelays, reduceFlashing: false)
        reducedFlashingTimeline = AnimationTimeline(rawDelays: facts.rawDelays, reduceFlashing: true)
        lock = OSAllocatedUnfairLock(uncheckedState: State(cache: cache, decodes: 1))
    }

    func timeline(reduceFlashing: Bool) -> AnimationTimeline {
        reduceFlashing ? reducedFlashingTimeline : standardTimeline
    }

    /// Render thread: the resident texture of `index` (pinned as the frame on screen), nil when it is not resident or
    /// the lock is busy.
    func texture(at index: Int) -> MTLTexture? {
        if index == 0 { return frame0 }
        let found: MTLTexture?? = lock.withLockIfAvailableUnchecked { (s: inout State) -> MTLTexture? in
            guard let texture = s.cache.payload(at: index) else { return nil }
            s.cache.pinned = index
            return texture
        }
        return found ?? nil
    }

    /// Asks for `index` to be decoded unless it is resident or in flight (skipped when the lock is busy).
    func request(_ index: Int) {
        guard index > 0, index < frameCount else { return }
        let start: Bool? = lock.withLockIfAvailableUnchecked { (s: inout State) -> Bool in
            guard !s.cache.contains(index), !s.inFlight.contains(index) else { return false }
            s.inFlight.insert(index)
            return true
        }
        guard start == true else { return }
        queue.async { [self] in decode(index) }
    }

    /// Tests: returns when every requested decode has finished.
    func waitUntilIdle() { queue.sync {} }

    var statistics: AnimatedFrameCacheStatistics {
        lock.withLockUnchecked { (s: inout State) -> AnimatedFrameCacheStatistics in
            AnimatedFrameCacheStatistics(budgetBytes: s.cache.budgetBytes, residentBytes: s.cache.residentBytes,
                                         peakBytes: s.cache.peakBytes, residentFrames: s.cache.residentFrames,
                                         decodes: s.decodes, frameCount: frameCount, frameWidth: width, frameHeight: height)
        }
    }

    /// Decode queue: reserve, decode, commit (or cancel).
    private func decode(_ index: Int) {
        let reserve: Int = frameBytes * AnimatedFrameBudget.reserveFrames
        let reserved: Bool = lock.withLockUnchecked { (s: inout State) -> Bool in
            let ok: Bool = s.cache.reserve(reserve)
            if !ok { s.inFlight.remove(index) }
            return ok
        }
        guard reserved else { return }
        let texture: MTLTexture? = Self.decodeTexture(source, index: index, width: width, height: height, device: device)
        lock.withLockUnchecked { (s: inout State) -> Void in
            s.inFlight.remove(index)
            if let texture {
                s.cache.commit(index, payload: texture, bytes: frameBytes, reserved: reserve)
                s.decodes += 1
            } else {
                s.cache.cancel(reserved: reserve)
            }
        }
    }

    /// One frame as a single-level texture of premultiplied texels.
    static func decodeTexture(_ source: CGImageSource, index: Int, width: Int, height: Int, device: MTLDevice) -> MTLTexture? {
        guard let image = AnimatedImageFrames.decode(source, index: index, maxSide: max(width, height)),
              image.width <= width + 1, image.height <= height + 1 else { return nil }
        return ImageLayerSource.makeTexture(image, device: device, mipmapped: false)
    }
}
#endif
