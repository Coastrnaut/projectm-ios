// ScenePreviewCapture.swift — roadmap SCN-006: the picture a scene preview is made of (contract P3;
// research SCN-006-D3).
//
// * `ScenePreviewCapture.live(source:)`: the shown visual's next presented frame through REC-001's
//   `FrameCaptureSource` (after its flash limiting, so Reduce flashing and the flash guard are already
//   applied), at most `timeout` (1 s); converted with REC-001's `FrameColorConversion`, centre-cropped
//   to 16:9 and scaled to 192 × 108, encoded PNG with PRE-001's `PNGThumbnailEncoder`, off the main
//   actor. nil when no frame arrives or it cannot be encoded.
// * DEBUG `-uitestScenePreviewFixture`: an instant fixed picture, so UI tests do not depend on the
//   renderer (the real grab is REC-001's, tested there).
import CoreGraphics
import Foundation
import FrameCapture
import PresetLibrary

enum ScenePreviewCapture {
    static let timeout: Duration = .seconds(1)

    /// The live output's next frame as a preview PNG.
    @MainActor
    static func live(source: @escaping @MainActor () -> (any FrameCaptureSource)?) -> ScenePreviewModel.Capture {
        { @MainActor () async -> Data? in
            guard let source = source() else { return nil }
            guard let pixels = await nextFrame(source) else { return nil }
            return await Task.detached(priority: .utility) { () -> Data? in png(from: pixels) }.value
        }
    }

    /// One frame from `source`, or nil after the timeout (the request is then cancelled).
    @MainActor
    private static func nextFrame(_ source: any FrameCaptureSource) async -> CapturedPixels? {
        final class Once {
            var continuation: CheckedContinuation<CapturedPixels?, Never>?
            func finish(_ pixels: CapturedPixels?) {
                continuation?.resume(returning: pixels)
                continuation = nil
            }
        }
        let once = Once()
        return await withCheckedContinuation { (continuation: CheckedContinuation<CapturedPixels?, Never>) in
            once.continuation = continuation
            source.captureFrame { (pixels: CapturedPixels?) in once.finish(pixels) }
            Task { @MainActor () -> Void in
                try? await Task.sleep(for: timeout)
                guard once.continuation != nil else { return }
                source.cancelCapture()
                once.finish(nil)
            }
        }
    }

    /// The frame, opaque over black, centre-cropped to 16:9 and scaled to the preview size, as PNG.
    nonisolated static func png(from pixels: CapturedPixels) -> Data? {
        let image: RGBA8Image = FrameColorConversion.rgba8(pixels, policy: .opaqueOverBlack)
        return png(rgba: image.rgba, width: image.width, height: image.height)
    }

    /// Top-down RGBA8 rows → the preview PNG (192 × 108).
    nonisolated static func png(rgba: [UInt8], width: Int, height: Int) -> Data? {
        let outW: Int = ScenePreviewStore.width
        let outH: Int = ScenePreviewStore.height
        guard width > 0, height > 0, rgba.count == width * height * 4,
              let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        let space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let source = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                   space: space, bitmapInfo: info, provider: provider, decode: nil,
                                   shouldInterpolate: true, intent: .defaultIntent),
              let cropped = source.cropping(to: centreCrop(width: width, height: height)) else { return nil }
        var out = Data(count: outW * outH * 4)
        let drawn: Bool = out.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: outW, height: outH, bitsPerComponent: 8,
                                          bytesPerRow: outW * 4, space: space, bitmapInfo: info.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))
            return true
        }
        guard drawn else { return nil }
        return PNGThumbnailEncoder.png(rgba: out, width: outW, height: outH)
    }

    /// The largest centred 16:9 rectangle in a frame (portrait frames lose top and bottom).
    nonisolated static func centreCrop(width: Int, height: Int) -> CGRect {
        let target: Double = Double(ScenePreviewStore.width) / Double(ScenePreviewStore.height)
        let w: Double = Double(width)
        let h: Double = Double(height)
        if w / h > target {
            let cropW: Double = (h * target).rounded()
            return CGRect(x: ((w - cropW) / 2).rounded(), y: 0, width: cropW, height: h)
        }
        let cropH: Double = max(1, (w / target).rounded())
        return CGRect(x: 0, y: ((h - cropH) / 2).rounded(), width: w, height: cropH)
    }

    #if DEBUG
    static let fixtureArgument = "-uitestScenePreviewFixture"
    static var fixtureEnabled: Bool { ProcessInfo.processInfo.arguments.contains(fixtureArgument) }

    /// A fixed two-tone picture, at once.
    static func fixture() -> ScenePreviewModel.Capture {
        { @MainActor () async -> Data? in
            var rgba = [UInt8](repeating: 255, count: 32 * 18 * 4)
            for i in stride(from: 0, to: rgba.count, by: 4) {
                let x: Int = (i / 4) % 32
                rgba[i] = x < 16 ? 40 : 220
                rgba[i + 1] = 90
                rgba[i + 2] = x < 16 ? 220 : 40
            }
            return png(rgba: rgba, width: 32, height: 18)
        }
    }
    #endif
}
