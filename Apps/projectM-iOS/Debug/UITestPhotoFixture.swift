// UITestPhotoFixture.swift — DEBUG only (MED-001-R16; research MED-001-D11). System pickers cannot be
// automated, so `-uitestSeedPhoto <solid|alpha|corrupt|pattern>` makes a 64 × 48 PNG in the temporary folder
// and imports it through the same path as a picked file (PhotoStore: bounded read, sanitize, atomic
// write, identifier) before the first screen. `corrupt` (MED-014-R14) then cuts the stored copy
// short in place, as if it had been damaged on disk: the photo layer's load must fail with the
// "couldn't be loaded" notice while the app keeps running. MED-006-R15: `slideshow5` instead imports five
// solid-colour pictures (red, green, blue, yellow, magenta) through the slideshow's import and turns the
// slideshow on in Time mode at 2 s. Not compiled into Release builds.
#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum UITestPhotoFixture {
    static let argument = "-uitestSeedPhoto"

    static let slideshowColors: [(UInt8, UInt8, UInt8)] = [(230, 30, 30), (30, 200, 60), (40, 70, 230), (240, 220, 40), (220, 40, 220)]

    static func seedIfRequested(_ photos: PhotoCoordinator, slideshow: SlideshowCoordinator) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return }
        if arguments[i + 1] == "slideshow5" {
            seedSlideshow(slideshow)
            return
        }
        let kind = arguments[i + 1]
        guard let data = kind == "pattern" ? patternPNG() : png(alpha: kind == "alpha") else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-photo-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return }
        photos.importNow(at: url)
        try? FileManager.default.removeItem(at: url)
        if arguments[i + 1] == "corrupt", let stored = photos.photo?.url, let copy = try? Data(contentsOf: stored) {
            try? copy.prefix(copy.count / 2).write(to: stored)
        }
    }

    /// MED-006: five solid pictures through the slideshow's import path, on, Time 2 s.
    static func seedSlideshow(_ slideshow: SlideshowCoordinator) {
        var urls: [URL] = []
        for (n, color) in slideshowColors.enumerated() {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-slide-\(n)-\(UUID().uuidString).png")
            guard let data = png(alpha: false, color: color), (try? data.write(to: url)) != nil else { continue }
            urls.append(url)
        }
        slideshow.seedNow(at: urls, seconds: 2)
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    /// A 64 × 48 orange picture (half transparent with `alpha`), or another solid colour.
    /// QA-011 device acceptance: 256 × 192, eight vertical bars (red, yellow, green, cyan, blue, magenta, white, mid
    /// grey) crossed with an 8 px checkerboard at half brightness, so any part of the picture has edges, colour and
    /// a grey for effects to act on (blur, mosaic, hue keeping greys).
    static func patternPNG() -> Data? {
        let width = 256, height = 192
        let bars: [(UInt8, UInt8, UInt8)] = [(230, 40, 40), (230, 220, 40), (40, 200, 60), (40, 210, 220),
                                             (40, 70, 230), (220, 40, 220), (240, 240, 240), (128, 128, 128)]
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let bar = bars[x * bars.count / width]
                let dim: Bool = ((x / 8) + (y / 8)) % 2 == 1
                let i = (y * width + x) * 4
                bytes[i] = dim ? bar.0 / 2 : bar.0
                bytes[i + 1] = dim ? bar.1 / 2 : bar.1
                bytes[i + 2] = dim ? bar.2 / 2 : bar.2
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    static func png(alpha: Bool, color: (UInt8, UInt8, UInt8) = (230, 120, 30)) -> Data? {
        let width = 64, height = 48
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            bytes[i * 4] = color.0; bytes[i * 4 + 1] = color.1; bytes[i * 4 + 2] = color.2; bytes[i * 4 + 3] = alpha ? 128 : 255
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: (alpha ? CGImageAlphaInfo.last : .noneSkipLast).rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
#endif
