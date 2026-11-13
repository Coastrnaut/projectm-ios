// UITestPhotoFixture.swift — DEBUG only (MED-001-R16; research MED-001-D11). System pickers cannot be
// automated, so `-uitestSeedPhoto <solid|alpha|corrupt>` makes a 64 × 48 PNG in the temporary folder
// and imports it through the same path as a picked file (PhotoStore: bounded read, sanitize, atomic
// write, identifier) before the first screen. `corrupt` (MED-014-R14) then cuts the stored copy
// short in place, as if it had been damaged on disk: the photo layer's load must fail with the
// "couldn't be loaded" notice while the app keeps running. Not compiled into Release builds.
#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum UITestPhotoFixture {
    static let argument = "-uitestSeedPhoto"

    static func seedIfRequested(_ photos: PhotoCoordinator) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count,
              let data = png(alpha: arguments[i + 1] == "alpha") else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-photo-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return }
        photos.importNow(at: url)
        try? FileManager.default.removeItem(at: url)
        if arguments[i + 1] == "corrupt", let stored = photos.photo?.url, let copy = try? Data(contentsOf: stored) {
            try? copy.prefix(copy.count / 2).write(to: stored)
        }
    }

    /// A 64 × 48 orange picture (half transparent with `alpha`).
    static func png(alpha: Bool) -> Data? {
        let width = 64, height = 48
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            bytes[i * 4] = 230; bytes[i * 4 + 1] = 120; bytes[i * 4 + 2] = 30; bytes[i * 4 + 3] = alpha ? 128 : 255
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
