// SharedTexturePool.swift — one PERF-004 texture pool per Metal device for the app's compositor
// visuals (PERF-004-R5, R8; research PERF-004-D2 to D4; specs/052-perf-004-texture-pool).
//
// The Camera and Photo visuals build their compositors with `pool(for:)`, so a visual switch reuses
// the previous visual's composite and layer pictures instead of creating them again (each texture is
// handed out only after the last frame that used it completed). On the system memory warning every
// retired texture is freed; textures in use are untouched and the visual keeps playing. PERF-006
// builds broader memory-warning recovery on this.
import Compositor
import Metal
import UIKit

@MainActor
enum SharedTexturePool {
    private static var pools: [UInt64: TexturePool] = [:]
    private static var memoryWarningObserver: NSObjectProtocol?

    /// The app's pool for `device` (created on first use; one per `registryID`).
    static func pool(for device: MTLDevice) -> TexturePool {
        if let pool = pools[device.registryID] { return pool }
        let pool = TexturePool(device: device)
        pools[device.registryID] = pool
        observeMemoryWarnings()
        return pool
    }

    /// Frees every retired texture of every pool (the memory warning; tests).
    static func purgeAll() {
        for pool in pools.values { pool.purge() }
    }

    private static func observeMemoryWarnings() {
        guard memoryWarningObserver == nil else { return }
        memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                       object: nil, queue: .main) { (_: Notification) in
            MainActor.assumeIsolated { SharedTexturePool.purgeAll() }
        }
    }
}
