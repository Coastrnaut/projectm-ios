// EffectChain.swift — runs effects in order between a source and the final output (FX-001-R2, R14;
// ADR-0010 decision 3; contracts/post-process-effect.md).
//
// * No active effect: the source draws straight into the output — no extra texture, no extra pass,
//   VIS-001's picture bit for bit (FX-001-S7).
// * Otherwise the source draws into image A; effects ping-pong A ↔ B; the last writes the output.
// A and B (`.private`, the chain's pixel format, render target + shader read) are created by
// `prepare` only when the size changes (B only for two or more effects). Per frame nothing is
// created; `source` is a non-escaping closure. Not Sendable: one thread drives a chain.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import VisualGenerators

public final class EffectChain {
    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// In order of application.
    public let effects: [any PostProcessEffect]
    /// Counts creations of A/B (tests, diagnostics).
    public private(set) var resourceGeneration = 0

    private var imageA: MTLTexture?
    private var imageB: MTLTexture?
    private var width = 0
    private var height = 0

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat, effects: [any PostProcessEffect]) throws(VisualGeneratorError) {
        for effect in effects where effect.pixelFormat != pixelFormat {
            throw .unsupportedPixelFormat(effect.pixelFormat.rawValue)
        }
        self.device = device
        self.pixelFormat = pixelFormat
        self.effects = effects
    }

    /// Effects that change the picture.
    public var activeEffectCount: Int {
        var n = 0
        for effect in effects where !effect.isPassThrough { n += 1 }
        return n
    }

    /// Sizes the chain and every effect for an output of width × height; cheap when unchanged.
    public func prepare(width: Int, height: Int) throws(VisualGeneratorError) {
        let w = max(width, 1), h = max(height, 1)
        if w != self.width || h != self.height || imageA == nil {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            guard let a = device.makeTexture(descriptor: d) else { throw .pipelineUnavailable("effect chain image \(w)×\(h)") }
            a.label = "Effect chain A"
            var b: MTLTexture?
            if effects.count >= 2 {
                guard let t = device.makeTexture(descriptor: d) else { throw .pipelineUnavailable("effect chain image \(w)×\(h)") }
                t.label = "Effect chain B"
                b = t
            }
            imageA = a
            imageB = b
            self.width = w
            self.height = h
            resourceGeneration += 1
        }
        for effect in effects { try effect.prepare(width: w, height: h) }
    }

    /// Encodes one frame. `source` draws the frame into the texture it is given and returns false to
    /// skip the frame. Returns false when nothing complete was encoded (the caller should not
    /// present).
    public func encode(output: MTLTexture, commandBuffer: MTLCommandBuffer, source: (MTLTexture) -> Bool) -> Bool {
        var remaining = activeEffectCount
        if remaining == 0 { return source(output) }
        guard let a = imageA, output.width == width, output.height == height, output.pixelFormat == pixelFormat else { return false }
        guard source(a) else { return false }
        var current = a
        for effect in effects where !effect.isPassThrough {
            remaining -= 1
            let target: MTLTexture
            if remaining == 0 {
                target = output
            } else {
                guard let b = imageB else { return false }
                target = current === a ? b : a
            }
            guard effect.encode(input: current, output: target, commandBuffer: commandBuffer) else { return false }
            current = target
        }
        return true
    }
}
#endif
