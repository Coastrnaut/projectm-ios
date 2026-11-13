# Contract: Texture pool (PERF-004)

Module `Compositor`. Plain-Swift parts build everywhere; the Metal parts are behind
`#if canImport(Metal) && !COMPOSITOR_NO_METAL`.

## Plain Swift

```swift
public struct TexturePoolKey: Hashable, Sendable { /* data-model.md */ }
public struct TexturePoolLimits: Sendable, Equatable {
    public var maxRetiredBytes: Int
    public var maxIdleFrames: Int
    public static let defaultMaxRetiredBytes = 128 << 20
    public static let defaultMaxIdleFrames = 300
    public init(maxRetiredBytes: Int = defaultMaxRetiredBytes, maxIdleFrames: Int = defaultMaxIdleFrames)
    /// min(128 MiB, workingSet / 8) (workingSet ≤ 0: the fixed default).
    public static func `default`(recommendedWorkingSetBytes: UInt64) -> TexturePoolLimits
}
public struct TexturePoolCounters: Sendable, Equatable { /* data-model.md */ }

/// Bookkeeping only; not thread-safe (the Metal pool locks it). `isComplete` is stored once.
public struct TexturePoolCore<Resource: AnyObject, Fence> {
    public init(limits: TexturePoolLimits, isComplete: @escaping (Fence) -> Bool)
    public var limits: TexturePoolLimits { get set }        // a lower cap applies at the next checkIn/tick
    public private(set) var counters: TexturePoolCounters
    public private(set) var frame: UInt64
    /// A retired, completed resource of `key` (most recently returned first), now checked out; nil on a miss
    /// (counts the miss; the caller creates one and calls `adopt`).
    public mutating func checkOut(_ key: TexturePoolKey) -> Resource?
    /// Registers a resource the caller created after a miss as checked out.
    public mutating func adopt(_ resource: Resource, key: TexturePoolKey, bytes: Int)
    /// Retires a checked-out resource; it is reusable once `fence` completes (nil: at once).
    /// Unknown or already-retired resources are ignored (returns false). Enforces the byte cap.
    @discardableResult public mutating func checkIn(_ resource: Resource, fence: Fence?) -> Bool
    /// One pool frame: drops entries retired more than `maxIdleFrames` frames ago; refreshes `waitingTextures`.
    public mutating func tick()
    /// Drops every retired entry (idle and waiting). Checked-out resources are untouched.
    public mutating func purge()
}
```

## Metal

```swift
public final class TexturePool: @unchecked Sendable {
    public let device: MTLDevice
    /// Limits default to `TexturePoolLimits.default(recommendedWorkingSetBytes: device.recommendedMaxWorkingSetSize)`.
    public init(device: MTLDevice, limits: TexturePoolLimits? = nil)
    public var limits: TexturePoolLimits { get set }
    public var counters: TexturePoolCounters { get }
    /// A texture for `descriptor` (reused or new; signposted when new); nil when Metal cannot create it.
    public func makeTexture(descriptor: MTLTextureDescriptor) -> MTLTexture?
    /// Returns textures; reusable after `fence` (the last command buffer that may use them) completes.
    public func recycle(_ textures: [MTLTexture], after fence: MTLCommandBuffer?)
    public func tick()
    public func purge()
    public static func key(for descriptor: MTLTextureDescriptor) -> TexturePoolKey
}
```

Rules: callers return every texture they took (the compositor does on remove, resize and deinit); a
texture is never used after it was returned; a texture from the pool may hold old content, so its
user clears it before it is shown (layers already must: CMP-001 contract).

## Compositor

```swift
public init(device: MTLDevice, layers: [any LayerSource], texturePool: TexturePool? = nil) throws(CompositorError)
public convenience init(device: MTLDevice, texturePool: TexturePool? = nil) throws(CompositorError)
public let texturePool: TexturePool   // the given one, or a private pool
```

`pictureAllocations` keeps its meaning for CMP tests: pictures (and composites) the compositor took,
whether reused or new. New textures are `texturePool.counters.misses`.

## App

`SharedTexturePool.pool(for: device)` (main actor): one pool per `MTLDevice.registryID`, purged on
`UIApplication.didReceiveMemoryWarningNotification`. Camera and Photo hosts build their compositors
with it.
