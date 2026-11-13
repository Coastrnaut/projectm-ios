// TexturePool.swift — the Metal texture pool (PERF-004-R1 to R9, R11; research PERF-004-D2, D4, D6;
// specs/052-perf-004-texture-pool/contracts/texture-pool.md).
//
// `TexturePoolCore` keyed by the full texture description, behind one `NSLock` so visuals on any
// thread may share a pool (the app keeps one per device). Fences are `MTLCommandBuffer`s: a returned
// texture is handed out again only once the last command buffer its owner encoded with reports
// `.completed` or `.error` (polled; no completion handler, so nothing is allocated per frame). A new
// texture is created outside the lock and marked with a signpost interval for Instruments.
//
// Users clear a texture before showing it: a reused texture holds an earlier frame's pixels (layers
// already clear their picture, CMP-001 contract). Callers must keep their command buffers' default
// retained references (`makeCommandBuffer()`), so dropping a waiting texture is always safe.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Foundation
import Metal
import os

public final class TexturePool: @unchecked Sendable {
    public let device: MTLDevice
    private let lock = NSLock()
    private var core: TexturePoolCore<any MTLTexture, any MTLCommandBuffer>
    private static let signposter = OSSignposter(subsystem: "org.projectmios.compositor", category: "TexturePool")

    /// `limits` nil: `TexturePoolLimits.default(recommendedWorkingSetBytes: device.recommendedMaxWorkingSetSize)`.
    public init(device: MTLDevice, limits: TexturePoolLimits? = nil) {
        self.device = device
        let chosen = limits ?? TexturePoolLimits.default(recommendedWorkingSetBytes: device.recommendedMaxWorkingSetSize)
        core = TexturePoolCore(limits: chosen) { (fence: any MTLCommandBuffer) -> Bool in
            let status = fence.status
            return status == .completed || status == .error
        }
    }

    public var limits: TexturePoolLimits {
        get { lock.withLock { core.limits } }
        set { lock.withLock { core.limits = newValue } }
    }

    public var counters: TexturePoolCounters { lock.withLock { core.counters } }

    /// Pool frames so far.
    public var frame: UInt64 { lock.withLock { core.frame } }

    /// A texture for `descriptor`: a retired one whose GPU work completed, or a new one (signposted).
    /// nil when Metal cannot create it.
    public func makeTexture(descriptor: MTLTextureDescriptor) -> MTLTexture? {
        let key = Self.key(for: descriptor)
        if let reused = lock.withLock({ () -> (any MTLTexture)? in core.checkOut(key) }) { return reused }
        let signpost = Self.signposter.beginInterval("PERF-004 texture allocation", id: Self.signposter.makeSignpostID())
        let created = device.makeTexture(descriptor: descriptor)
        Self.signposter.endInterval("PERF-004 texture allocation", signpost)
        guard let created else { return nil }
        lock.withLock { core.adopt(created, key: key, bytes: created.allocatedSize) }
        return created
    }

    /// Returns textures taken from this pool. They are reusable once `fence` (the last command buffer that
    /// may use them) completes; nil: at once. Textures from elsewhere are ignored.
    public func recycle(_ textures: [MTLTexture], after fence: MTLCommandBuffer?) {
        guard !textures.isEmpty else { return }
        lock.withLock {
            for texture in textures { core.checkIn(texture, fence: fence) }
        }
    }

    /// Returns one texture (see `recycle(_:after:)`). False when it was not checked out of this pool.
    @discardableResult
    public func recycle(_ texture: MTLTexture, after fence: MTLCommandBuffer?) -> Bool {
        lock.withLock { core.checkIn(texture, fence: fence) }
    }

    /// One pool frame (the compositor calls it once per composite): ages and evicts idle textures.
    public func tick() {
        lock.withLock { core.tick() }
    }

    /// Frees every retired texture (memory warning; PERF-004-R5). Textures in use are untouched.
    public func purge() {
        lock.withLock { core.purge() }
        Self.signposter.emitEvent("PERF-004 texture pool purge")
    }

    /// True when `texture` is checked out of this pool (tests, diagnostics).
    public func isCheckedOut(_ texture: MTLTexture) -> Bool { lock.withLock { core.isCheckedOut(texture) } }

    public static func key(for d: MTLTextureDescriptor) -> TexturePoolKey {
        TexturePoolKey(pixelFormat: d.pixelFormat.rawValue, width: d.width, height: d.height, depth: d.depth,
                       arrayLength: d.arrayLength, usage: d.usage.rawValue, storageMode: d.storageMode.rawValue,
                       mipmapLevelCount: d.mipmapLevelCount, sampleCount: d.sampleCount, textureType: d.textureType.rawValue)
    }
}
#endif
