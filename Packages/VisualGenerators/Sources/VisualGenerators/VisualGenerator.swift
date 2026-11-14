// VisualGenerator.swift — the native visual generator contract (VIS-001-R1, R19; ADR-0009;
// specs/019-vis-001-circular-spectrum/contracts/visual-generator.md).
//
// A generator encodes one frame into a texture and a command buffer that its caller owns: today a
// `CAMetalLayer` drawable in the app, later a CMP-001 layer. It knows nothing about projectM,
// capture, the app or its settings; its input is a band vector (ANL-002 values normalized to 0…1)
// and a frame context.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
#endif

/// Per-frame context. The time base is monotonic (never wall-clock).
public struct VisualFrameContext: Sendable, Equatable {
    /// Monotonic nanoseconds of the frame (e.g. the display link's target time).
    public var timeNanoseconds: UInt64
    /// Seconds since the previous frame; drives the Reduce-flashing limits.
    public var frameDuration: Double
    /// The app's Reduce flashing setting (FR-072).
    public var reduceFlashing: Bool

    public init(timeNanoseconds: UInt64, frameDuration: Double, reduceFlashing: Bool) {
        self.timeNanoseconds = timeNanoseconds
        self.frameDuration = frameDuration
        self.reduceFlashing = reduceFlashing
    }
}

public enum VisualGeneratorError: Error, Equatable, Sendable {
    /// No Metal device exists.
    case noDevice
    /// The generator does not render to this pixel format (raw value of `MTLPixelFormat`).
    case unsupportedPixelFormat(UInt)
    /// The shaders or the pipeline could not be built; the message is the system's.
    case pipelineUnavailable(String)
}

#if canImport(Metal) && !VISUAL_NO_METAL
/// A native visual that renders into a caller-provided texture. Driven by one thread (not Sendable).
public protocol TextureGenerator: AnyObject {
    /// The only pixel format `encode` accepts.
    var pixelFormat: MTLPixelFormat { get }
    /// Encodes one frame covering all of `target` (cleared to the background first) into
    /// `commandBuffer`, which the caller commits. Returns false, encoding nothing, when the frame
    /// was skipped: the target's pixel format differs, or no vertex buffer is free yet.
    /// `bands` is the visual's input vector: normalized bands for the spectra, the mono sample
    /// history (oldest first) for the oscilloscope (VIS-003).
    func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool
}
#endif
