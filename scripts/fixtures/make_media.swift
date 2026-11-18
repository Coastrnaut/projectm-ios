// make_media.swift — QA-011 media fixtures that need Apple's image and video encoders (ImageIO, AVFoundation).
// Called by scripts/make_media_fixtures.py; deterministic content (patterns and a fixed-seed noise), no licence.
//
//   swift scripts/fixtures/make_media.swift <output folder> <name> [<name> …]
//
// Names: photo-gps.heic, panorama-60mp.png, panorama-60mp.heic, photo-45mb.jpg, photo-small.jpg,
// photo-transparent.png, animated-200.gif, video-h264-1080p.mp4, video-hevc-4k60.mov, video-hevc-360p-10min.mov,
// video-hdr-hlg.mov. Prints "make_media: <name> <bytes>" per file; exit 1 when one fails.
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: Pictures

/// RGBA pixels: eight colour bars crossed with a 32 px checkerboard, plus fixed-seed noise when `noise` > 0.
func pattern(width: Int, height: Int, noise: Int = 0, alpha: Bool = false) -> CGImage? {
    let bars: [(UInt8, UInt8, UInt8)] = [(230, 40, 40), (230, 220, 40), (40, 200, 60), (40, 210, 220),
                                         (40, 60, 230), (220, 40, 220), (240, 240, 240), (128, 128, 128)]
    var data = [UInt8](repeating: 0, count: width * height * 4)
    var seed: UInt32 = 0x2545F491
    for y in 0..<height {
        for x in 0..<width {
            let bar = bars[min(7, x * 8 / max(1, width))]
            let check = ((x / 32) + (y / 32)) % 2 == 0
            var r = Int(bar.0), g = Int(bar.1), b = Int(bar.2)
            if !check { r /= 2; g /= 2; b /= 2 }
            if noise > 0 {
                seed = seed &* 1_103_515_245 &+ 12_345
                let n = Int((seed >> 16) % UInt32(2 * noise + 1)) - noise
                r = max(0, min(255, r + n)); g = max(0, min(255, g - n)); b = max(0, min(255, b + n / 2))
            }
            let i = (y * width + x) * 4
            let a = alpha ? UInt8(255 * x / max(1, width - 1)) : 255
            // Premultiplied alpha.
            data[i] = UInt8(r * Int(a) / 255); data[i + 1] = UInt8(g * Int(a) / 255)
            data[i + 2] = UInt8(b * Int(a) / 255); data[i + 3] = a
        }
    }
    let provider = CGDataProvider(data: Data(data) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

func write(_ images: [CGImage], to url: URL, type: UTType, properties: [CFString: Any] = [:],
           frameProperties: [CFString: Any] = [:]) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil)
    else { return false }
    CGImageDestinationSetProperties(destination, properties as CFDictionary)
    for image in images { CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary) }
    return CGImageDestinationFinalize(destination)
}

func photoWithGPS(_ url: URL) -> Bool {
    guard let image = pattern(width: 1024, height: 768) else { return false }
    // Somewhere fixed (Greenwich), so a test can assert the location is stripped on import.
    let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 51.4779, kCGImagePropertyGPSLatitudeRef: "N",
                                kCGImagePropertyGPSLongitude: 0.0015, kCGImagePropertyGPSLongitudeRef: "W",
                                kCGImagePropertyGPSAltitude: 46.0]
    let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: "2026:11:18 12:00:00"]
    return write([image], to: url, type: .heic, frameProperties: [kCGImagePropertyGPSDictionary: gps,
                                                                   kCGImagePropertyExifDictionary: exif])
}

/// The smallest JPEG of fixed-seed noise that is at least 45 MB (quality 1).
func largeJPEG(_ url: URL) -> Bool {
    // About 3 bytes per pixel at quality 1 for this noise (6000 x 4500 made 80 MB): start near 45 MB, grow by 10 %.
    var width = 4500, height = 3400
    for _ in 0..<8 {
        guard let image = pattern(width: width, height: height, noise: 60) else { return false }
        guard write([image], to: url, type: .jpeg, frameProperties: [kCGImageDestinationLossyCompressionQuality: 1.0])
        else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size >= 45_000_000 { return true }
        width = width * 105 / 100; height = height * 105 / 100
    }
    return false
}

func animatedGIF(_ url: URL, frames: Int = 200) -> Bool {
    var images: [CGImage] = []
    for n in 0..<frames {
        // A bar moving across a 160 × 120 frame, so every frame differs.
        var data = [UInt8](repeating: 20, count: 160 * 120 * 4)
        let x0 = (n * 4) % 160
        for y in 0..<120 { for x in x0..<min(160, x0 + 12) { let i = (y * 160 + x) * 4; data[i] = 240; data[i + 1] = 200; data[i + 2] = 40 } }
        for i in stride(from: 3, to: data.count, by: 4) { data[i] = 255 }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        guard let image = CGImage(width: 160, height: 120, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 640,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return false }
        images.append(image)
    }
    let gif: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
    let frame: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.04]]
    return write(images, to: url, type: .gif, properties: gif, frameProperties: frame)
}

// MARK: Video

/// Writes `seconds` of a moving bar over grey with AVAssetWriter. `hdr`: HEVC Main10, HLG transfer, BT.2020.
func video(_ url: URL, codec: AVVideoCodecType, fileType: AVFileType, width: Int, height: Int, fps: Int,
           seconds: Int, bitRate: Int, hdr: Bool = false) -> Bool {
    try? FileManager.default.removeItem(at: url)
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: fileType) else { return false }
    var compression: [String: Any] = [AVVideoAverageBitRateKey: bitRate, AVVideoExpectedSourceFrameRateKey: fps,
                                      AVVideoMaxKeyFrameIntervalKey: fps * 2]
    var settings: [String: Any] = [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height]
    if hdr {
        compression[AVVideoProfileLevelKey] = "HEVC_Main10_AutoLevel"   // kVTProfileLevel_HEVC_Main10_AutoLevel
        settings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                                               AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                                               AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
    }
    settings[AVVideoCompressionPropertiesKey] = compression
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let format = hdr ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: format, kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height, kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ])
    guard writer.canAdd(input) else { return false }
    writer.add(input)
    guard writer.startWriting() else { return false }
    writer.startSession(atSourceTime: .zero)
    let total = fps * seconds
    for n in 0..<total {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        guard let pool = adaptor.pixelBufferPool else { return false }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return false }
        CVPixelBufferLockBaseAddress(buffer, [])
        let barX = (n * width / max(1, fps * 4)) % width, barWidth = max(8, width / 20)
        if hdr { fillYUV10(buffer, width: width, height: height, barX: barX, barWidth: barWidth) } else {
            fillBGRA(buffer, width: width, height: height, barX: barX, barWidth: barWidth, frame: n)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        if !adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(n), timescale: CMTimeScale(fps))) {
            return false
        }
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    return writer.status == .completed
}

func fillBGRA(_ buffer: CVPixelBuffer, width: Int, height: Int, barX: Int, barWidth: Int, frame: Int) {
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let p = base.assumingMemoryBound(to: UInt8.self)
    let grey = UInt8(60 + (frame % 60))
    var row = [UInt8](repeating: grey, count: stride)
    for x in 0..<width { row[x * 4 + 3] = 255 }
    for x in barX..<min(width, barX + barWidth) { row[x * 4] = 40; row[x * 4 + 1] = 200; row[x * 4 + 2] = 240 }
    for y in 0..<height { row.withUnsafeBufferPointer { (src: UnsafeBufferPointer<UInt8>) -> Void in (p + y * stride).update(from: src.baseAddress!, count: stride) } }
}

/// 10-bit video range (values in the high bits of 16-bit words): mid grey with a bright bar (HLG peak white).
func fillYUV10(_ buffer: CVPixelBuffer, width: Int, height: Int, barX: Int, barWidth: Int) {
    for plane in 0..<2 {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { continue }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
        let rows = CVPixelBufferGetHeightOfPlane(buffer, plane)
        let words = stride / 2
        var row = [UInt16](repeating: 0, count: words)
        if plane == 0 {
            for x in 0..<width { row[x] = UInt16((x >= barX && x < barX + barWidth) ? 940 : 420) << 6 }
        } else {
            for x in 0..<(width / 2) { row[x * 2] = 512 << 6; row[x * 2 + 1] = 512 << 6 }
        }
        let p = base.assumingMemoryBound(to: UInt16.self)
        for y in 0..<rows { row.withUnsafeBufferPointer { (src: UnsafeBufferPointer<UInt16>) -> Void in (p + y * words).update(from: src.baseAddress!, count: words) } }
    }
}

// MARK: Main

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: make_media.swift <output folder> <name> [<name> …]")
    exit(2)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var failed = false
for name in arguments.dropFirst(2) {
    let url = folder.appendingPathComponent(name)
    let ok: Bool
    switch name {
    case "photo-gps.heic": ok = photoWithGPS(url)
    case "panorama-60mp.png": ok = pattern(width: 15_000, height: 4_000).map { write([$0], to: url, type: .png) } ?? false
    case "panorama-60mp.heic": ok = pattern(width: 15_000, height: 4_000).map { write([$0], to: url, type: .heic) } ?? false
    case "photo-45mb.jpg": ok = largeJPEG(url)
    case "photo-small.jpg": ok = pattern(width: 320, height: 240).map { write([$0], to: url, type: .jpeg) } ?? false
    case "photo-transparent.png": ok = pattern(width: 512, height: 384, alpha: true).map { write([$0], to: url, type: .png) } ?? false
    case "animated-200.gif": ok = animatedGIF(url)
    case "video-h264-1080p.mp4":
        ok = video(url, codec: .h264, fileType: .mp4, width: 1920, height: 1080, fps: 30, seconds: 10, bitRate: 8_000_000)
    case "video-hevc-4k60.mov":
        ok = video(url, codec: .hevc, fileType: .mov, width: 3840, height: 2160, fps: 60, seconds: 10, bitRate: 30_000_000)
    case "video-hevc-360p-10min.mov":
        ok = video(url, codec: .hevc, fileType: .mov, width: 640, height: 360, fps: 30, seconds: 600, bitRate: 600_000)
    case "video-hdr-hlg.mov":
        ok = video(url, codec: .hevc, fileType: .mov, width: 1920, height: 1080, fps: 30, seconds: 5, bitRate: 10_000_000, hdr: true)
    default:
        print("make_media: unknown name \(name)")
        ok = false
    }
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("make_media: \(name) \(ok ? "\(size)" : "FAILED")")
    if !ok { failed = true }
}
exit(failed ? 1 : 0)
