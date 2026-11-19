// UITestLogoFixture.swift — DEBUG only (MED-010-R14). System pickers cannot be automated, so
// `-uitestSeedLogo` makes a 64 × 64 PNG with an alpha gradient in the temporary folder and imports it
// through the same path as a picked logo (LogoStore: bounded read, logo limits, PNG sanitizer, FILE-008
// reference, identifier) before the first screen. `LogoProbe` exposes the frames that showed the logo.
// QA-011 MED-010-T25 (pass 4, 2026-11-19): `-uitestSeedLogo white-disc` imports the Mac-made 512 × 512 anti-aliased
// white disc from the app's Documents (logo-white-disc.png, install_test_fixtures.py --media; a copy, the fixture stays)
// or, when it is missing, a drawn one of that shape, so the corner and fringe checks need no picker.
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
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: argument) else { return }
        let whiteDisc: Bool = i + 1 < arguments.count && arguments[i + 1] == "white-disc"
        guard let data = whiteDisc ? documentsFixture("logo-white-disc.png") ?? whiteDiscPNG() : png() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-logo-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return }
        logo.importNow(at: url)
        try? FileManager.default.removeItem(at: url)
    }

    /// Documents/`name`'s bytes (nil when missing).
    static func documentsFixture(_ name: String) -> Data? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return try? Data(contentsOf: documents.appendingPathComponent(name))
    }

    /// A 512 × 512 white disc on transparency with an anti-aliased edge (straight alpha, as the Mac fixture).
    static func whiteDiscPNG() -> Data? {
        let size = 512
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let centre: Double = Double(size) / 2, radius: Double = Double(size) / 2 - 8
        for y in 0..<size {
            for x in 0..<size {
                let dx: Double = Double(x) + 0.5 - centre, dy: Double = Double(y) + 0.5 - centre
                let coverage: Double = min(max(radius + 0.5 - (dx * dx + dy * dy).squareRoot(), 0), 1)
                let i: Int = (y * size + x) * 4
                bytes[i] = 255; bytes[i + 1] = 255; bytes[i + 2] = 255; bytes[i + 3] = UInt8((coverage * 255).rounded())
            }
        }
        return encode(bytes, size: size)
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
        return encode(bytes, size: size)
    }

    /// A square straight-alpha RGBA bitmap as PNG.
    private static func encode(_ bytes: [UInt8], size: Int) -> Data? {
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

/// The visualizer's DEBUG media probes: the slideshow's (while Photo is shown), the logo's and the clock's (MED-011).
struct MediaProbes: View {
    let coordinator: AppCoordinator

    var body: some View {
        if showsSlideshow { SlideshowProbe(slideshow: slideshow) }
        overlayProbes
    }

    /// The logo's and the clock's probes (MED-010, MED-011), split out for the type-check budget.
    @ViewBuilder private var overlayProbes: some View {
        LogoProbe(logo: logo)
        ClockProbe(clock: clock)
        CountdownProbe(countdown: coordinator.countdown)   // MED-012
        MediaDeviceProbes(coordinator: coordinator)   // QA-011 Batch 5: videoFrameRate, photoStoredMetadata
    }

    private var slideshow: SlideshowCoordinator { coordinator.slideshow }
    private var logo: LogoCoordinator { coordinator.logo }
    private var clock: ClockOverlayCoordinator { coordinator.clock }
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
