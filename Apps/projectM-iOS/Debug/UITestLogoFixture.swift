// UITestLogoFixture.swift — DEBUG only (MED-010-R14). System pickers cannot be automated, so
// `-uitestSeedLogo` makes a 64 × 64 PNG with an alpha gradient in the temporary folder and imports it
// through the same path as a picked logo (LogoStore: bounded read, logo limits, PNG sanitizer, FILE-008
// reference, identifier) before the first screen. `LogoProbe` exposes the frames that showed the logo.
// Not compiled into Release builds.
#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum UITestLogoFixture {
    static let argument = "-uitestSeedLogo"

    static func seedIfRequested(_ logo: LogoCoordinator) {
        guard ProcessInfo.processInfo.arguments.contains(argument), let data = png() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-logo-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return }
        logo.importNow(at: url)
        try? FileManager.default.removeItem(at: url)
    }

    /// 64 × 64 white with alpha rising from 0 (left) to 255 (right), transparent in the bottom 16 rows.
    static func png() -> Data? {
        let size = 64
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<(size - 16) {
            for x in 0..<size {
                let i: Int = (y * size + x) * 4
                let alpha: Int = (x * 255 + 31) / 63
                bytes[i] = 255; bytes[i + 1] = 255; bytes[i + 2] = 255; bytes[i + 3] = UInt8(alpha)
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// The visualizer's DEBUG media probes: the slideshow's (while Photo is shown) and the logo's.
struct MediaProbes: View {
    let coordinator: AppCoordinator

    var body: some View {
        if showsSlideshow { SlideshowProbe(slideshow: slideshow) }
        LogoProbe(logo: logo)
    }

    private var slideshow: SlideshowCoordinator { coordinator.slideshow }
    private var logo: LogoCoordinator { coordinator.logo }
    private var showsSlideshow: Bool {
        guard case .some = coordinator.photoVisual else { return false }
        return true
    }
}

/// "drawn=<frames> logo=<yes|no>": frames in which a live logo layer showed the logo.
struct LogoProbe: View {
    let logo: LogoCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let stored: String = logo.logo == nil ? "no" : "yes"
            let text: String = "drawn=" + String(logo.framesShown) + " logo=" + stored
            Text(text)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("logoProbe")
                .accessibilityValue(text)
        }
    }
}
#endif
