// CueRehearsalRenderer.swift — SHOW-006 the rehearsal picture of a native cue (specs/237-show-006-cue-rehearsal; R3,
// R4, R7; research SHOW-006-D1, D2).
//
// * REC-002's `SnapshotStillRenderer` draws the cue's style and values offscreen (same generator factory and FX-001
//   glow as the screen, Reduce flashing and the safety clamp, fixed synthetic audio) into its own private texture of
//   320 × 180 and reads it back. It never touches the screen, a live host, a drawable, the recorder or a setting.
// * The pixels become a `CGImage` the device-only panel shows. Off the main actor (a detached task).
import CoreGraphics
import FlashSafety
import Foundation
import FrameCapture
import VisualGenerators

/// Draws a rehearsal picture (a fake in tests).
protocol CueRehearsalRendering: Sendable {
    func render(style: NativeSpectrumStyle, values: SnapshotRenderValues, reduceFlashing: Bool,
                clamp: SafetyClamp) async throws -> CGImage
}

/// The app's renderer: REC-002's offscreen still at the rehearsal's bounded size.
final class SnapshotCueRehearsalRenderer: CueRehearsalRendering {
    /// SHOW-006-R7: the preview is at most 320 × 180 pixels.
    static let width = 320
    static let height = 180

    private let still: SnapshotStillRenderer

    init() throws {
        still = try SnapshotStillRenderer()
    }

    func render(style: NativeSpectrumStyle, values: SnapshotRenderValues, reduceFlashing: Bool,
                clamp: SafetyClamp) async throws -> CGImage {
        let still: SnapshotStillRenderer = self.still
        return try await Task.detached(priority: .userInitiated) { () throws -> CGImage in
            let pixels: CapturedPixels = try still.renderPixels(style: style, values: values, reduceFlashing: reduceFlashing,
                                                                clamp: clamp, width: Self.width, height: Self.height)
            return try Self.image(pixels)
        }.value
    }

    /// Opaque sRGB RGBA8 rows → a `CGImage`.
    nonisolated static func image(_ pixels: CapturedPixels) throws -> CGImage {
        let rgba: RGBA8Image = FrameColorConversion.rgba8(pixels, policy: .opaqueOverBlack)
        let data = Data(rgba.rgba) as CFData
        guard let provider = CGDataProvider(data: data),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: rgba.width, height: rgba.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: rgba.width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw SnapshotRenderError.resource("the rehearsal picture")
        }
        return image
    }
}
