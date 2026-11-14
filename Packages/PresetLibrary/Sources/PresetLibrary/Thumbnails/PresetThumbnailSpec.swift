// PresetThumbnailSpec.swift — roadmap PRE-001: what a preset thumbnail is (research PRE-001-D2,
// data-model "PresetThumbnailSpec"). A still frame of a fixed small size, drawn after a fixed number
// of frames of deterministic synthetic audio, so the same preset and renderer version always give
// the same picture. Changing any field, or how a renderer draws, means a new `rendererVersion`.
import Foundation

public struct PresetThumbnailSpec: Sendable, Equatable {
    public var width: Int
    public var height: Int
    /// Frames drawn before the picture is read back (0.75 s at 60 fps).
    public var frames: Int
    public var sampleRate: Int
    /// Stereo frames of audio fed before each drawn frame (1/60 s at 44.1 kHz).
    public var samplesPerFrame: Int
    public var seed: UInt64
    public var rendererVersion: Int

    public init(width: Int, height: Int, frames: Int, sampleRate: Int, samplesPerFrame: Int, seed: UInt64,
                rendererVersion: Int) {
        self.width = width; self.height = height; self.frames = frames
        self.sampleRate = sampleRate; self.samplesPerFrame = samplesPerFrame
        self.seed = seed; self.rendererVersion = rendererVersion
    }

    /// 128 × 72 pixels (16:9), 45 frames, seed "PRE1", renderer version 1.
    public static let standard = PresetThumbnailSpec(width: 128, height: 72, frames: 45, sampleRate: 44_100,
                                                     samplesPerFrame: 735, seed: 0x5052_4531, rendererVersion: 1)
}

/// The thumbnail's audio: a 110 Hz and a 440 Hz sine under a beat envelope that restarts every 15
/// frames, plus quiet noise from a seeded 64-bit linear congruential generator. Pure arithmetic, so
/// the same spec gives identical samples on every run on a platform (PRE-001-S6).
public enum SyntheticPCM {
    public static let beatFrames = 15

    /// One block of interleaved stereo samples (`samplesPerFrame * 2` values) per drawn frame.
    public static func frames(_ spec: PresetThumbnailSpec) -> [[Float]] {
        var state: UInt64 = spec.seed
        var blocks: [[Float]] = []
        blocks.reserveCapacity(spec.frames)
        let rate = Double(spec.sampleRate)
        let beatLength = Double(beatFrames * spec.samplesPerFrame)
        for frame in 0..<spec.frames {
            var block = [Float](repeating: 0, count: spec.samplesPerFrame * 2)
            for index in 0..<spec.samplesPerFrame {
                let n = frame * spec.samplesPerFrame + index
                let t = Double(n) / rate
                let sinceBeat = Double(n).truncatingRemainder(dividingBy: beatLength) / beatLength
                let envelope = 0.3 + 0.7 * (1 - sinceBeat) * (1 - sinceBeat)
                let bass: Double = 0.5 * sin(2 * Double.pi * 110 * t) * envelope
                let tone: Double = 0.2 * sin(2 * Double.pi * 440 * t)
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let noise: Double = (Double(state >> 40) / Double(1 << 24) - 0.5) * 0.1
                let left = Float(bass + tone + noise)
                let right = Float(bass - tone + noise)
                block[index * 2] = left
                block[index * 2 + 1] = right
            }
            blocks.append(block)
        }
        return blocks
    }
}
