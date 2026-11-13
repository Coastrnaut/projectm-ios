// TexturePoolCore.swift — the texture pool's bookkeeping (PERF-004-R1 to R6, R10; research
// PERF-004-D1 to D3, D5; specs/052-perf-004-texture-pool/contracts/texture-pool.md).
//
// Plain Swift, generic over the resource (an `MTLTexture` in the app, a fake object in tests) and the
// completion signal ("fence": the last `MTLCommandBuffer` that may use a returned resource). It builds
// and is tested everywhere, Linux included; `TexturePool` (Metal) wraps it with a lock.
//
// States: checked out → (checkIn) retired, waiting until its fence completes → idle → checked out
// again by an equal key. Retired entries (waiting or idle) are capped by bytes, least recently returned
// dropped first, and by age in pool frames; `purge()` drops them all. Dropping a waiting entry is safe
// (a committed command buffer keeps the resources it uses alive); only reuse waits for the fence.
// Nothing here allocates at a steady state: `checkOut` and `tick` scan and remove in place.

/// What makes two textures interchangeable (PERF-004-D1): every creation parameter, as raw values.
public struct TexturePoolKey: Hashable, Sendable {
    public var pixelFormat: UInt
    public var width: Int
    public var height: Int
    public var depth: Int
    public var arrayLength: Int
    public var usage: UInt
    public var storageMode: UInt
    public var mipmapLevelCount: Int
    public var sampleCount: Int
    public var textureType: UInt

    public init(pixelFormat: UInt, width: Int, height: Int, depth: Int = 1, arrayLength: Int = 1, usage: UInt,
                storageMode: UInt, mipmapLevelCount: Int = 1, sampleCount: Int = 1, textureType: UInt) {
        self.pixelFormat = pixelFormat
        self.width = width
        self.height = height
        self.depth = depth
        self.arrayLength = arrayLength
        self.usage = usage
        self.storageMode = storageMode
        self.mipmapLevelCount = mipmapLevelCount
        self.sampleCount = sampleCount
        self.textureType = textureType
    }
}

/// The caps on retired (returned, not in use) resources (PERF-004-R3, R4; research PERF-004-D3).
public struct TexturePoolLimits: Sendable, Equatable {
    /// Bytes of retired resources kept at most; past it the least recently returned are dropped. 0 keeps nothing.
    public var maxRetiredBytes: Int
    /// A retired resource unused for more than this many pool frames (`tick()` calls) is dropped.
    public var maxIdleFrames: Int

    public static let defaultMaxRetiredBytes = 128 << 20
    public static let defaultMaxIdleFrames = 300

    public init(maxRetiredBytes: Int = defaultMaxRetiredBytes, maxIdleFrames: Int = defaultMaxIdleFrames) {
        self.maxRetiredBytes = max(0, maxRetiredBytes)
        self.maxIdleFrames = max(0, maxIdleFrames)
    }

    /// min(128 MiB, `recommendedWorkingSetBytes` / 8); the fixed default when the working set is unknown (0).
    public static func `default`(recommendedWorkingSetBytes: UInt64) -> TexturePoolLimits {
        guard recommendedWorkingSetBytes > 0 else { return TexturePoolLimits() }
        let eighth = recommendedWorkingSetBytes / 8
        return TexturePoolLimits(maxRetiredBytes: eighth < UInt64(defaultMaxRetiredBytes) ? Int(eighth) : defaultMaxRetiredBytes)
    }
}

/// What the pool holds and did (PERF-004-R6). `live = checked out + retired`.
public struct TexturePoolCounters: Sendable, Equatable {
    public var checkedOutTextures = 0
    public var checkedOutBytes = 0
    /// Returned and not dropped: waiting for their fence or idle.
    public var retiredTextures = 0
    public var retiredBytes = 0
    /// Retired entries whose fence had not completed at the pool's last look (`tick`, `checkIn`, `checkOut`).
    public var waitingTextures = 0
    /// Check-outs served by a retired resource.
    public var hits = 0
    /// Check-outs that found none (the caller created a new resource).
    public var misses = 0
    /// Retired resources dropped by the byte cap or the age limit.
    public var evictions = 0
    /// Retired resources dropped by `purge()`.
    public var purged = 0
    /// Calls to `purge()`.
    public var purges = 0

    public init() {}

    /// Resources the pool knows that are alive: in use plus retired.
    public var liveTextures: Int { checkedOutTextures + retiredTextures }
    public var liveBytes: Int { checkedOutBytes + retiredBytes }
}

/// The pool's bookkeeping. Not thread-safe: one owner, or a lock around it (`TexturePool`).
public struct TexturePoolCore<Resource: AnyObject, Fence> {
    private struct Retired {
        let resource: Resource
        let key: TexturePoolKey
        let bytes: Int
        let retiredAt: UInt64
        /// nil once complete (or never encoded).
        var fence: Fence?
    }

    /// Holds the resource strongly, so its identifier cannot be reused by another object while the pool
    /// counts it (a texture dropped without being returned stays live, as the counters say).
    private struct CheckedOut {
        let resource: Resource
        let key: TexturePoolKey
        let bytes: Int
    }

    /// Oldest return first (index 0 is the least recently returned).
    private var retired: [Retired] = []
    private var checkedOut: [ObjectIdentifier: CheckedOut] = [:]
    private let isComplete: (Fence) -> Bool

    public private(set) var counters = TexturePoolCounters()
    /// Pool frames so far (`tick()` calls).
    public private(set) var frame: UInt64 = 0
    /// A lower cap applies at once.
    public var limits: TexturePoolLimits {
        didSet { enforceByteCap() }
    }

    /// `isComplete` tells whether the GPU finished the work a fence stands for; stored once.
    public init(limits: TexturePoolLimits = TexturePoolLimits(), isComplete: @escaping (Fence) -> Bool) {
        self.limits = limits
        self.isComplete = isComplete
        retired.reserveCapacity(32)
        checkedOut.reserveCapacity(32)
    }

    /// A retired resource of `key` whose fence completed (most recently returned first), now checked out;
    /// nil on a miss, counted (the caller creates one and calls `adopt`).
    public mutating func checkOut(_ key: TexturePoolKey) -> Resource? {
        var i = retired.count - 1
        while i >= 0 {
            if retired[i].key == key {
                if let fence = retired[i].fence {
                    if isComplete(fence) { retired[i].fence = nil } else { i -= 1; continue }
                }
                let entry = retired.remove(at: i)
                counters.retiredTextures -= 1
                counters.retiredBytes -= entry.bytes
                markCheckedOut(entry.resource, key: entry.key, bytes: entry.bytes)
                counters.hits += 1
                countWaiting()
                return entry.resource
            }
            i -= 1
        }
        counters.misses += 1
        return nil
    }

    /// Registers a resource the caller created after a miss as checked out.
    public mutating func adopt(_ resource: Resource, key: TexturePoolKey, bytes: Int) {
        guard checkedOut[ObjectIdentifier(resource)] == nil, !retired.contains(where: { (r: Retired) -> Bool in r.resource === resource }) else { return }
        markCheckedOut(resource, key: key, bytes: max(0, bytes))
    }

    /// Retires a checked-out resource; it can be handed out again once `fence` completes (nil: at once).
    /// Unknown or already retired resources are ignored (false). A resource larger than the cap is dropped.
    @discardableResult
    public mutating func checkIn(_ resource: Resource, fence: Fence?) -> Bool {
        guard let info = checkedOut.removeValue(forKey: ObjectIdentifier(resource)) else { return false }
        counters.checkedOutTextures -= 1
        counters.checkedOutBytes -= info.bytes
        if info.bytes > limits.maxRetiredBytes {
            counters.evictions += 1   // dropped here: our reference ends with this call
            return true
        }
        var complete = true
        if let fence { complete = isComplete(fence) }
        retired.append(Retired(resource: resource, key: info.key, bytes: info.bytes, retiredAt: frame, fence: complete ? nil : fence))
        counters.retiredTextures += 1
        counters.retiredBytes += info.bytes
        enforceByteCap()
        countWaiting()
        return true
    }

    /// One pool frame: drops retired entries unused for more than `maxIdleFrames` frames.
    public mutating func tick() {
        frame &+= 1
        var i = 0
        while i < retired.count {
            if frame - retired[i].retiredAt > UInt64(limits.maxIdleFrames) {
                drop(at: i)
                counters.evictions += 1
            } else {
                i += 1
            }
        }
        countWaiting()
    }

    /// Drops every retired entry (waiting and idle); checked-out resources are untouched (PERF-004-R5).
    public mutating func purge() {
        counters.purges += 1
        counters.purged += retired.count
        retired.removeAll(keepingCapacity: true)
        counters.retiredTextures = 0
        counters.retiredBytes = 0
        counters.waitingTextures = 0
    }

    /// True when `resource` is checked out of this pool (tests, diagnostics).
    public func isCheckedOut(_ resource: Resource) -> Bool { checkedOut[ObjectIdentifier(resource)] != nil }

    // MARK: - Private

    private mutating func markCheckedOut(_ resource: Resource, key: TexturePoolKey, bytes: Int) {
        checkedOut[ObjectIdentifier(resource)] = CheckedOut(resource: resource, key: key, bytes: bytes)
        counters.checkedOutTextures += 1
        counters.checkedOutBytes += bytes
    }

    private mutating func enforceByteCap() {
        while counters.retiredBytes > limits.maxRetiredBytes, !retired.isEmpty {
            drop(at: 0)
            counters.evictions += 1
        }
        countWaiting()
    }

    private mutating func drop(at index: Int) {
        let entry = retired.remove(at: index)
        counters.retiredTextures -= 1
        counters.retiredBytes -= entry.bytes
    }

    private mutating func countWaiting() {
        var waiting = 0
        for i in retired.indices {
            guard let fence = retired[i].fence else { continue }
            if isComplete(fence) { retired[i].fence = nil } else { waiting += 1 }
        }
        counters.waitingTextures = waiting
    }
}
