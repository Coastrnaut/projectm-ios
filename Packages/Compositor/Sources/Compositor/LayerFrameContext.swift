// LayerFrameContext.swift — the explicit clock every layer receives (CMP-001-R3; research
// CMP-001-D3; contracts/layer-source.md "Context").
//
// The compositor's caller supplies a monotonic presentation time per frame (the display link's
// target time in the app, injected times in tests); `LayerFrameClock` turns it into the context.
// Rules: frame 0 has duration 0; the duration is the time difference clamped to 0…0.1 s (FX-019's
// clamp, so a stall never jumps animations or opens a flash window early); a time earlier than the
// previous one is replaced by the previous one (time never runs backwards); a non-finite or
// non-positive scale reads 1. Value types, no allocation.

public struct LayerFrameContext: Sendable, Equatable {
    /// Monotonic nanoseconds at which the frame will be shown; never decreases.
    public var presentationTimeNanoseconds: UInt64
    /// 0, 1, 2… per composited frame.
    public var frameIndex: UInt64
    /// Seconds since the previous frame, 0…`LayerFrameClock.maxFrameDuration`; 0 on frame 0.
    public var frameDuration: Double
    /// The output's size in pixels (every layer picture has this size).
    public var outputWidth: Int
    public var outputHeight: Int
    /// Pixels per point of the output (1 when unknown).
    public var contentScale: Double
    /// The app's Reduce flashing setting (FR-072).
    public var reduceFlashing: Bool

    public init(presentationTimeNanoseconds: UInt64, frameIndex: UInt64, frameDuration: Double, outputWidth: Int,
                outputHeight: Int, contentScale: Double, reduceFlashing: Bool) {
        self.presentationTimeNanoseconds = presentationTimeNanoseconds
        self.frameIndex = frameIndex
        self.frameDuration = frameDuration
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.contentScale = contentScale
        self.reduceFlashing = reduceFlashing
    }
}

public struct LayerFrameClock: Sendable {
    /// The longest frame duration a layer sees (FX-019's frame-time clamp).
    public static let maxFrameDuration = 0.1

    private var previous: UInt64?
    private var nextIndex: UInt64 = 0

    public init() {}

    /// The context of the next frame.
    public mutating func next(presentationTimeNanoseconds: UInt64, outputWidth: Int, outputHeight: Int,
                              contentScale: Double, reduceFlashing: Bool) -> LayerFrameContext {
        var time = presentationTimeNanoseconds
        var duration = 0.0
        if let previous {
            if time < previous { time = previous }
            duration = min(Double(time - previous) / 1e9, Self.maxFrameDuration)
        }
        let scale = contentScale.isFinite && contentScale > 0 ? contentScale : 1
        let context = LayerFrameContext(presentationTimeNanoseconds: time, frameIndex: nextIndex, frameDuration: duration,
                                        outputWidth: outputWidth, outputHeight: outputHeight, contentScale: scale,
                                        reduceFlashing: reduceFlashing)
        previous = time
        nextIndex &+= 1
        return context
    }

    /// The next frame is frame 0 again, with no previous time.
    public mutating func reset() {
        previous = nil
        nextIndex = 0
    }
}
