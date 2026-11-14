// SharedTexturePool.swift — one PERF-004 texture pool per Metal device for the app's compositor
// visuals (PERF-004-R5, R8; research PERF-004-D2 to D4; specs/052-perf-004-texture-pool).
//
// The Camera, Photo and Video visuals build their compositors with `pool(for:)`, so a visual switch
// reuses the previous visual's composite and layer pictures instead of creating them again (each
// texture is handed out only after the last frame that used it completed).
//
// PERF-006: the pools are a cache step of MemoryPressureCoordinator (the app's one observer of the
// system memory warning). On a warning every retired texture is freed, including ones still waiting
// for their last command buffer: that buffer keeps its own reference, so Metal frees the memory only
// when the GPU is done (PERF-006-R13). Textures in use are untouched and the visual keeps playing.
import Compositor
import Metal
import PresentationLifecycle
import UIKit

@MainActor
enum SharedTexturePool {
    private static var pools: [UInt64: TexturePool] = [:]
    private static var step: PoolMemoryStep?
    #if DEBUG
    /// MemoryPressureUITests: keep retired pictures until the injected warning (research PERF-006-D7).
    private static var relaxedIdleEviction = false
    #endif

    /// The app's pool for `device` (created on first use; one per `registryID`).
    static func pool(for device: MTLDevice) -> TexturePool {
        if let pool = pools[device.registryID] { return pool }
        let pool = TexturePool(device: device)
        #if DEBUG
        if relaxedIdleEviction { pool.limits.maxIdleFrames = Int(Int32.max) }
        #endif
        pools[device.registryID] = pool
        registerMemoryStep()
        return pool
    }

    /// Frees every retired texture of every pool (memory pressure; tests).
    static func purgeAll() {
        for pool in pools.values { pool.purge() }
    }

    /// Retired (idle or waiting) bytes and textures across the pools.
    static var retiredBytes: Int { pools.values.reduce(0) { $0 + $1.counters.retiredBytes } }
    static var retiredTextures: Int { pools.values.reduce(0) { $0 + $1.counters.retiredTextures } }
    /// PERF-012: every pool's counters, for the performance report.
    static var allCounters: [TexturePoolCounters] { pools.values.map { (pool: TexturePool) -> TexturePoolCounters in pool.counters } }

    #if DEBUG
    /// Under `-uitestMemoryPressure`: idle pictures are not aged out, so a rotation's retired pictures
    /// are still pooled when the test injects the warning (the byte cap still applies).
    static func relaxIdleEvictionForUITests() {
        relaxedIdleEviction = true
        for pool in pools.values { pool.limits.maxIdleFrames = Int(Int32.max) }
    }
    #endif

    private static func registerMemoryStep() {
        guard step == nil else { return }
        let created = PoolMemoryStep()
        step = created
        MemoryPressureCoordinator.shared.register(created)
    }

    /// The pools' cache step: measured bytes (the retired bytes held before the purge).
    @MainActor
    private final class PoolMemoryStep: MemoryPressureResponder {
        let memoryPressureName = "shared texture pool"
        let memoryPressureTier = MemoryPressureTier.cache
        var reclaimableBytes: Int { SharedTexturePool.retiredBytes }

        func releaseForMemoryPressure(_ level: MemoryPressureLevel) -> MemoryPressureRelease {
            let bytes = SharedTexturePool.retiredBytes, textures = SharedTexturePool.retiredTextures
            SharedTexturePool.purgeAll()
            return MemoryPressureRelease(bytes: bytes, items: textures)
        }
    }
}
