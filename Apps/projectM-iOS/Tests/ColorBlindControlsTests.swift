// ColorBlindControlsTests.swift — ACC-003-T08, T11 (specs/110-acc-003-color-blind-friendly-controls;
// ACC-003-R1 to R9, R15; S1, S2; contract status-cues.md C1, C2, C4).
//
// Grayscale method (research ACC-003-D4): each state's cue is rendered with `ImageRenderer` (scale 2) on
// a solid background (white for light, black for dark), every pixel is reduced to its relative luminance
// Y (sRGB decoded, Rec. 709 weights) and re-encoded to an 8-bit gray, so hue is gone. Two states are
// distinguishable when at least 1% of the pixels differ by at least 51/255 (20%). A negative control
// draws one symbol in a red and a green of equal luminance: it must measure below 1%, proving the
// measure ignores hue. No reference images are stored and no clock is read.
import CaptureUI
import Metal
import SwiftUI
import UIKit
import VisualEffects
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class ColorBlindControlsTests: XCTestCase {
    // MARK: - Grayscale measure

    /// 8-bit luminance gray of every pixel, row by row.
    struct GrayImage {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    static let minimumShare = 0.01
    static let minimumDelta = 51

    /// sRGB 8-bit → linear, as a table.
    private static let linear: [Double] = (0...255).map { (v: Int) -> Double in
        let c = Double(v) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func encode(_ y: Double) -> UInt8 {
        let c: Double = y <= 0.0031308 ? y * 12.92 : 1.055 * pow(y, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, (c * 255).rounded())))
    }

    static func gray(_ image: CGImage) -> GrayImage {
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        rgba.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var pixels = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let y: Double = 0.2126 * linear[Int(rgba[i * 4])] + 0.7152 * linear[Int(rgba[i * 4 + 1])]
                + 0.0722 * linear[Int(rgba[i * 4 + 2])]
            pixels[i] = encode(y)
        }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    /// The share of pixels whose gray values differ by at least `minimumDelta`.
    static func differingShare(_ a: GrayImage, _ b: GrayImage) -> Double {
        precondition(a.width == b.width && a.height == b.height, "same size")
        var differing = 0
        for i in 0..<a.pixels.count where abs(Int(a.pixels[i]) - Int(b.pixels[i])) >= minimumDelta {
            differing += 1
        }
        return Double(differing) / Double(a.pixels.count)
    }

    private func render(_ view: some View, scheme: ColorScheme) throws -> GrayImage {
        let background: Color = scheme == .dark ? .black : .white
        let framed = view
            .padding(.horizontal, 8)
            .frame(width: 300, height: 36, alignment: .leading)
            .background(background)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let image: CGImage = try XCTUnwrap(renderer.cgImage, "rendered")
        return Self.gray(image)
    }

    // MARK: - ACC-003-S1: the grayscale table

    func testCriticalStatusesStayDistinguishableInGrayscale() throws {
        var checked = 0
        for group in StatusCueCatalog.groups {
            for scheme in [ColorScheme.light, .dark] {
                let images: [GrayImage] = try group.states.map { (state: NamedStatusCue) -> GrayImage in
                    try render(StatusCueLabel(cue: state.cue), scheme: scheme)
                }
                var smallest = 1.0
                defer { print("ACC-003 grayscale \(group.id) \(scheme): smallest pair share \(String(format: "%.2f", smallest * 100))%") }
                for i in 0..<images.count {
                    for j in (i + 1)..<images.count {
                        let share: Double = Self.differingShare(images[i], images[j])
                        smallest = min(smallest, share)
                        XCTAssertGreaterThanOrEqual(share, Self.minimumShare,
                                                    "\(group.id) \(scheme): \(group.states[i].name) vs \(group.states[j].name) "
                                                        + "differ in only \(share * 100)% of pixels in grayscale")
                        checked += 1
                    }
                }
            }
        }
        // 6 groups: source 10 states (45 pairs), recording 3, camera 3, blackout 3, osc 1, tempo 6 → 61 × 2.
        XCTAssertEqual(checked, 122)
    }

    /// The measure ignores hue: one symbol in a red and a green of equal luminance is not distinguishable.
    func testNegativeControlEqualLuminanceColoursAreNotDistinguishable() throws {
        // Pure red: Y = 0.2126. Green with the same Y: linear 0.2126 / 0.7152 = 0.297 → sRGB 148/255.
        let red = Color(.sRGB, red: 1, green: 0, blue: 0)
        let green = Color(.sRGB, red: 0, green: 148.0 / 255, blue: 0)
        for scheme in [ColorScheme.light, .dark] {
            let a = try render(Image(systemName: "record.circle.fill").font(.title2).foregroundStyle(red), scheme: scheme)
            let b = try render(Image(systemName: "record.circle.fill").font(.title2).foregroundStyle(green), scheme: scheme)
            let control: Double = Self.differingShare(a, b)
            print("ACC-003 grayscale control \(scheme): \(String(format: "%.2f", control * 100))%")
            XCTAssertLessThan(control, Self.minimumShare, "\(scheme): hue alone must not count")
            // And the symbol is really drawn: against an empty picture it is distinguishable.
            let empty = try render(Color.clear.frame(width: 1, height: 1), scheme: scheme)
            XCTAssertGreaterThanOrEqual(Self.differingShare(a, empty), Self.minimumShare, "\(scheme): the control draws")
        }
    }

    // MARK: - ACC-003-R1 to R5: the catalog

    func testEverySymbolExistsAndIsUniqueWithinItsGroup() {
        for group in StatusCueCatalog.groups {
            let symbols: [String] = group.states.compactMap(\.cue.symbol)
            XCTAssertEqual(Set(symbols).count, symbols.count, "\(group.id): one outline per state")
            for symbol in symbols {
                XCTAssertNotNil(UIImage(systemName: symbol), "\(group.id): SF Symbol \(symbol) exists")
            }
            let cues: [StatusCue] = group.states.map(\.cue)
            XCTAssertEqual(Set(cues.map { "\($0.symbol ?? "-")|\($0.text)" }).count, cues.count, "\(group.id): states differ")
        }
    }

    func testWordsAreUnchanged() {
        XCTAssertEqual(StatusCueCatalog.source(.active).text, "Active audio")
        XCTAssertEqual(StatusCueCatalog.switching.text, UIStrings.switchingSource)
        XCTAssertEqual(StatusCueCatalog.recording(finishing: false, elapsed: "0:05").text, "REC 0:05")
        XCTAssertEqual(StatusCueCatalog.recording(finishing: true, elapsed: "0:05").text, "Finishing…")
        XCTAssertEqual(StatusCueCatalog.blackout(blackedOut: true).text, "Output blacked out")
        XCTAssertEqual(StatusCueCatalog.blackout(blackedOut: false).text, "Restoring output")
        XCTAssertEqual(StatusCueCatalog.osc(port: 9000).text, "OSC listening on port 9000")
    }

    func testCameraShapesAndDifferentiateWithoutColourWords() {
        let starting = StatusCueCatalog.camera(running: false, label: CameraIndicator.label, differentiateWithoutColor: false)
        let live = StatusCueCatalog.camera(running: true, label: CameraIndicator.label, differentiateWithoutColor: false)
        XCTAssertEqual(starting.text, live.text, "without Differentiate Without Colour the words are the same")
        XCTAssertNotEqual(starting.symbol, live.symbol, "so the shape tells them apart")
        XCTAssertEqual(StatusCueCatalog.camera(running: false, label: CameraIndicator.label, differentiateWithoutColor: true).text,
                       "Camera on · Starting")
        XCTAssertEqual(StatusCueCatalog.camera(running: true, label: CameraIndicator.frontLabel, differentiateWithoutColor: true).text,
                       "Front camera on · Live")
        XCTAssertTrue(CameraIndicator(state: .running).isRunning)
        XCTAssertFalse(CameraIndicator(state: .starting).isRunning)
    }

    // MARK: - ACC-003-R6 to R9: the palette

    private var entries: [(String, PaletteEntry)] {
        [("accent", InterfacePalette.accent), ("positive", InterfacePalette.positive),
         ("caution", InterfacePalette.caution), ("critical", InterfacePalette.critical)]
    }

    func testPaletteMeetsContrastInEveryAppearance() {
        for (name, entry) in entries {
            for background in InterfacePalette.lightBackgrounds {
                XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.light, background), InterfacePalette.standardMinimum,
                                            "\(name) light on \(String(background, radix: 16))")
            }
            for background in InterfacePalette.darkBackgrounds {
                XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.dark, background), InterfacePalette.standardMinimum,
                                            "\(name) dark on \(String(background, radix: 16))")
            }
            XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.lightIncreased, 0xFFFFFF), InterfacePalette.increasedPageMinimum, name)
            XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.lightIncreased, 0xF2F2F7), InterfacePalette.increasedGroupedMinimum, name)
            XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.darkIncreased, 0x000000), InterfacePalette.increasedPageMinimum, name)
            XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.darkIncreased, 0x1C1C1E), InterfacePalette.increasedGroupedMinimum, name)
        }
        // The old system accent failed: systemBlue on white is about 4.0:1 (ACC-004's filter).
        XCTAssertLessThan(InterfacePalette.contrastRatio(0x007AFF, 0xFFFFFF), InterfacePalette.standardMinimum)
    }

    private static func traits(dark: Bool, increased: Bool) -> UITraitCollection {
        UITraitCollection(mutations: { (traits: inout any UIMutableTraits) in
            traits.userInterfaceStyle = dark ? .dark : .light
            traits.accessibilityContrast = increased ? .high : .normal
        })
    }

    private static func hex(_ color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// The asset catalog's AccentColor (the app-wide tint) and the dynamic status colours resolve to the
    /// table's values under the four trait combinations.
    func testAssetAccentAndDynamicColoursFollowTheTraits() throws {
        let accent = try XCTUnwrap(UIColor(named: "AccentColor", in: Bundle.main, compatibleWith: nil), "AccentColor in the app's assets")
        for dark in [false, true] {
            for increased in [false, true] {
                let traits = Self.traits(dark: dark, increased: increased)
                XCTAssertEqual(Self.hex(accent.resolvedColor(with: traits)), InterfacePalette.accent.value(dark: dark, increased: increased),
                               "accent dark=\(dark) increased=\(increased)")
                for (name, entry) in entries {
                    XCTAssertEqual(Self.hex(InterfacePalette.uiColor(entry).resolvedColor(with: traits)),
                                   entry.value(dark: dark, increased: increased), "\(name) dark=\(dark) increased=\(increased)")
                }
            }
        }
    }

    func testBadgeStyleIsOpaqueOnlyWithIncreasedContrast() {
        XCTAssertEqual(StatusBadgeStyle.resolve(increasedContrast: false), .material)
        XCTAssertEqual(StatusBadgeStyle.resolve(increasedContrast: true), .opaqueBordered)
    }

    // MARK: - ACC-003-R13: the colour-blind-safe spectrum palette

    func testPaletteSettingIsOffByDefaultAndPersists() {
        let suite = "ColorBlindControlsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertFalse(settings.colorBlindSafePalette)
        XCTAssertEqual(settings.spectrumPalette, .spectrum, "off: the spectra look as before (S4)")
        settings.colorBlindSafePalette = true
        XCTAssertEqual(settings.spectrumPalette, .colorBlindSafe)
        XCTAssertTrue(AppSettings(defaults: defaults, systemReduceMotion: false).colorBlindSafePalette, "stored")
        XCTAssertTrue(AppSettings.allKeys.contains("settings.visual.colorBlindSafePalette"))
    }

    func testHostAppliesThePaletteToEveryStyle() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32, glow: BloomParameters())
        XCTAssertEqual(host.generatorPalette, .spectrum)
        host.palette = .colorBlindSafe
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "circular")
        try host.apply(style: .linear(.vertical, spacing: 0.2))
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "linear keeps it")
        try host.apply(style: .oscilloscope(line: .medium, windowMilliseconds: 20))
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "oscilloscope keeps it")
        host.palette = .spectrum
        XCTAssertEqual(host.generatorPalette, .spectrum)
    }

    // MARK: - ACC-003-R12: appearance and its DEBUG overrides

    func testAppearanceResolutionAndProbe() {
        let standard = StatusAppearance.resolve(contrast: .standard, differentiateWithoutColor: false)
        let increased = StatusAppearance.resolve(contrast: .increased, differentiateWithoutColor: true)
        if StatusAppearance.differentiateWithoutColorOverride == nil {   // the unit-test host passes no override
            XCTAssertEqual(standard.probeValue, "contrast:standard dwc:off")
            XCTAssertEqual(increased.probeValue, "contrast:increased dwc:on")
        }
        XCTAssertEqual(StatusAppearance.override("-x", in: ["app", "-x", "YES"]), true)
        XCTAssertEqual(StatusAppearance.override("-x", in: ["app", "-x", "NO"]), false)
        XCTAssertNil(StatusAppearance.override("-x", in: ["app", "-x"]))
        XCTAssertNil(StatusAppearance.override("-x", in: ["app"]))
    }
}
