// LayerRenderCache.swift — render caching (CMP-013-R1 to R4, R12; ADR-0040;
// specs/113-cmp-013-render-caching/contracts/render-caching.md).
//
// Plain Swift (every host, Linux included): what a layer's picture depends on in a frame, the cache key
// built from it, one layer's cache entry and the composite (level 2) draw-input rule. The compositor
// (Metal) applies them: a layer whose key equals the key stored with its last good picture is not
// rendered again; a stack whose draw inputs are all unchanged keeps its composite. Unknown means render:
// a layer that does not adopt `LayerRenderCaching`, or declares time, audio, modulation or external
// input, renders every frame. Value types, no allocation.

/// What a layer's picture reads in one frame (CMP-013-R1).
public struct LayerRenderDependencies: Sendable, Equatable {
    /// Reads the frame context's presentation time, frame index or duration.
    public var time: Bool
    /// Reads the audio context.
    public var audio: Bool
    /// Has MOD-002 bindings or other modulation driving its render.
    public var modulation: Bool
    /// Reads external frames (camera, video).
    public var externalInput: Bool
    /// Changes whenever the layer's content changes (a new photo, a new text rendering).
    public var contentGeneration: UInt64
    /// Changes whenever a parameter the layer draws with changes (CMP-006 fit).
    public var parameterGeneration: UInt64

    public init(time: Bool = false, audio: Bool = false, modulation: Bool = false, externalInput: Bool = false,
                contentGeneration: UInt64 = 0, parameterGeneration: UInt64 = 0) {
        self.time = time
        self.audio = audio
        self.modulation = modulation
        self.externalInput = externalInput
        self.contentGeneration = contentGeneration
        self.parameterGeneration = parameterGeneration
    }

    /// A picture that depends on nothing per frame but its content and parameters.
    public static func still(content: UInt64, parameters: UInt64 = 0) -> LayerRenderDependencies {
        LayerRenderDependencies(contentGeneration: content, parameterGeneration: parameters)
    }

    /// Every per-frame dependency (never cached).
    public static let dynamic = LayerRenderDependencies(time: true, audio: true, modulation: true, externalInput: true)

    /// CMP-013-R2: cacheable only without any per-frame dependency.
    public var isCacheable: Bool { !time && !audio && !modulation && !externalInput }
}

/// The inputs a cached picture was drawn with (CMP-013-R3). Equal keys reuse the picture.
public struct LayerRenderCacheKey: Sendable, Equatable {
    public let contentGeneration: UInt64
    public let parameterGeneration: UInt64
    /// Size, pixel format, colour space, alpha and origin of the picture.
    public let picture: LayerPictureDescriptor
    public let contentScale: Double
    public let reduceFlashing: Bool
    /// The compositor's cache epoch (bumped by every global invalidation).
    public let epoch: UInt64

    /// nil (render) for an undeclared (`dependencies` nil) or non-cacheable layer.
    public init?(dependencies: LayerRenderDependencies?, picture: LayerPictureDescriptor, contentScale: Double,
                 reduceFlashing: Bool, epoch: UInt64) {
        guard let dependencies, dependencies.isCacheable else { return nil }
        contentGeneration = dependencies.contentGeneration
        parameterGeneration = dependencies.parameterGeneration
        self.picture = picture
        self.contentScale = contentScale
        self.reduceFlashing = reduceFlashing
        self.epoch = epoch
    }
}

/// One layer's cache entry (CMP-013-R4): the key of its last good picture, or nothing.
public struct LayerRenderCacheEntry: Sendable, Equatable {
    public private(set) var key: LayerRenderCacheKey?

    public init() {}

    /// True only for a non-nil key equal to the stored one while the layer still holds a good picture.
    public func canReuse(_ candidate: LayerRenderCacheKey?, hasGoodPicture: Bool) -> Bool {
        guard hasGoodPicture, let candidate, let key else { return false }
        return candidate == key
    }

    /// Forget the picture (a render may overwrite it; a failed, skipped or held frame; new pictures).
    public mutating func drop() { key = nil }

    /// A successful render drew the picture with `candidate` (nil keeps nothing).
    public mutating func rendered(_ candidate: LayerRenderCacheKey?) { key = candidate }
}

/// How one layer was drawn into the composite (CMP-013-R6, level 2).
public struct LayerDrawInput: Sendable, Equatable {
    /// The picture drawn from (−1: the layer was not drawn).
    public var picture: Int
    /// The shown opacity it was drawn with.
    public var opacity: Double
    /// Its picture was reused this frame (not rendered).
    public var reused: Bool

    public init(picture: Int, opacity: Double, reused: Bool) {
        self.picture = picture
        self.opacity = opacity
        self.reused = reused
    }

    /// The layer contributes exactly what it contributed to `previous`'s composite: not drawn in both, or
    /// drawn from the same reused picture with the same opacity.
    public func isUnchanged(from previous: LayerDrawInput?) -> Bool {
        guard let previous else { return false }
        if picture < 0 { return previous.picture < 0 }
        return reused && picture == previous.picture && opacity == previous.opacity
    }
}

/// A layer that declares its render dependencies (CMP-013-R1; contracts/render-caching.md). Driven by the
/// compositor's thread, like `LayerSource`.
public protocol LayerRenderCaching: AnyObject {
    /// Read once per frame before `render`. Must not allocate, lock with unbounded wait, log or do I/O. The
    /// generations reported must never be newer than what `render` would draw in the same frame.
    var renderDependencies: LayerRenderDependencies { get }
    /// Called instead of `render` when the compositor reused the layer's last good picture.
    func renderReused(frame: LayerFrameContext)
}

extension LayerRenderCaching {
    public func renderReused(frame: LayerFrameContext) {}
}
