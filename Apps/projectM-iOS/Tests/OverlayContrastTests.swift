// OverlayContrastTests.swift — ACC-008-T03, T05, T09-T11 (specs/119-acc-008-high-contrast-overlay;
// ACC-008-R1, R2, R5-R9; S1-S3; contract overlay-surface.md C2, C3).
//
// Measurement method (research ACC-008-D1):
// 1. Each audited element is represented by its backing (the production `overlaySurface`, with the blur
//    material left out: `ImageRenderer` has no backdrop, so the scrim alone is measured, a lower bound) and
//    each of its text styles (font, foreground, button style), rendered with `ImageRenderer` at scale 2 over
//    a fixture frame: pure white, pure black, a saturated gradient and a noisy 2 pt pattern.
// 2. The same view is rendered again with the text at opacity 0 (same layout; button fills stay).
// 3. Each pixel becomes WCAG relative luminance (sRGB decoded, Rec. 709 weights).
// 4. Glyph core pixels: where the two renderings differ by at least 90% of the style's strong difference
//    (95th percentile of the differences above 4/255), so anti-aliased edges are left out.
// 5. Each core pixel's ratio (max + 0.05) / (min + 0.05) between the pixel with text and the same pixel
//    without it, which is exactly its local background, also over the noisy frame.
// 6. The style's measured contrast is the 5th percentile of those ratios; it must reach 4.5 (normal text) or
//    3.0 (large text, symbols). A grey label and the previous backings must fail (negative controls).
// No reference images are stored and no clock is read.
import SwiftUI
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class OverlayContrastTests: XCTestCase {
    // MARK: - Fixture frames

    enum Frame: String, CaseIterable {
        case white, black, gradient, noise
    }

    static let canvas = CGSize(width: 340, height: 64)

    /// Black, white and saturated colours in 2 pt cells (a fixed linear congruential generator).
    static let noiseImage: CGImage = {
        let width = Int(canvas.width / 2)
        let height = Int(canvas.height / 2)
        let colours: [(UInt8, UInt8, UInt8)] = [(255, 255, 255), (0, 0, 0), (255, 255, 0), (0, 255, 255),
                                                (255, 0, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255)]
        var state: UInt32 = 0x2545_F491
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            state = state &* 1_664_525 &+ 1_013_904_223
            let colour = colours[Int(state >> 29)]
            bytes[i * 4] = colour.0
            bytes[i * 4 + 1] = colour.1
            bytes[i * 4 + 2] = colour.2
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return context.makeImage()!
    }()

    @ViewBuilder static func frameView(_ frame: Frame) -> some View {
        switch frame {
        case .white: Color.white
        case .black: Color.black
        case .gradient:
            LinearGradient(colors: [Color(.sRGB, red: 1, green: 1, blue: 0), Color(.sRGB, red: 0, green: 1, blue: 1),
                                    Color(.sRGB, red: 1, green: 0, blue: 1), Color(.sRGB, red: 1, green: 1, blue: 1)],
                           startPoint: .leading, endPoint: .trailing)
        case .noise:
            Image(decorative: noiseImage, scale: 1).resizable().interpolation(.none)
        }
    }

    // MARK: - Specimens

    enum Foreground {
        case primary, secondary, color(Color)

        var style: AnyShapeStyle {
            switch self {
            case .primary: AnyShapeStyle(.primary)
            case .secondary: AnyShapeStyle(.secondary)
            case .color(let colour): AnyShapeStyle(colour)
            }
        }
    }

    /// One text style as the element draws it.
    enum Kind {
        case text(Font, Foreground)
        case symbol(String, Font, Foreground)
        case cue(StatusCue, Font)
        case plainButton(Font)
        case destructiveButton(Font)
        case bordered(Font)
        case prominentCritical(Font)
        case prominent(Font)
        case onFill(Font, Color)
    }

    struct Style {
        let name: String
        let words: String
        let kind: Kind
        var target: Double = OverlayContrast.normalTextMinimum
    }

    struct Element {
        let name: String
        let styles: [Style]
        var backing: Backing = .surface
    }

    enum Backing {
        /// The production surface without its material.
        case surface
        /// A black scrim of the given opacity in the given scheme (previous backings, sweep, kept elements).
        case scrim(Double, ColorScheme)
    }

    struct StyleView: View {
        let style: Style
        let showsText: Bool

        var body: some View {
            let opacity: Double = showsText ? 1 : 0
            switch style.kind {
            case .text(let font, let foreground):
                Text(style.words).font(font).foregroundStyle(foreground.style).opacity(opacity)
            case .symbol(let name, let font, let foreground):
                Image(systemName: name).font(font).foregroundStyle(foreground.style).opacity(opacity)
            case .cue(let cue, let font):
                StatusCueLabel(cue: cue, font: font).opacity(opacity)
            case .plainButton(let font):
                Button {} label: { Text(style.words).opacity(opacity) }.font(font)
            case .destructiveButton(let font):
                // As CaptureResultPanels draws Discard (ACC-008-R5).
                Button(role: .destructive) {} label: { Text(style.words).opacity(opacity) }
                    .font(font)
                    .foregroundStyle(OverlayContrast.criticalText)
            case .bordered(let font):
                Button {} label: { Text(style.words).opacity(opacity) }.font(font).buttonStyle(.bordered).controlSize(.small)
            case .prominentCritical(let font):
                // As CameraIndicatorBadge draws Stop (ACC-008-R5).
                Button {} label: { Text(style.words).opacity(opacity) }
                    .font(font).buttonStyle(.borderedProminent).tint(OverlayContrast.criticalFill).controlSize(.small)
            case .prominent(let font):
                Button {} label: { Text(style.words).opacity(opacity) }.font(font).buttonStyle(.borderedProminent).overlayProminentTint()
            case .onFill(let font, let fill):
                Text(style.words).font(font).opacity(opacity).padding(6).background(fill, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    struct Specimen: View {
        let style: Style
        let backing: Backing
        let showsText: Bool

        var body: some View {
            let content = StyleView(style: style, showsText: showsText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            switch backing {
            case .surface:
                content.overlaySurface(RoundedRectangle(cornerRadius: 12), includesMaterial: false)
            case .scrim(let opacity, let scheme):
                content
                    .tint(scheme == .dark ? OverlayContrast.tint : Color.accentColor)
                    .background(Color.black.opacity(opacity), in: RoundedRectangle(cornerRadius: 12))
                    .environment(\.colorScheme, scheme)
            }
        }
    }

    // MARK: - The audit's elements (spec baseline table; contract C1)

    static let footnote: Font = .footnote
    static let tintPlainStyles: [Style] = [
        Style(name: "words", words: "Your microphone was paused", kind: .text(.footnote, .primary)),
        Style(name: "secondary", words: "Choose another visual instead", kind: .text(.footnote, .secondary)),
        Style(name: "dismiss", words: "Dismiss", kind: .plainButton(.footnote.bold())),
        Style(name: "symbol", words: "", kind: .symbol("moon.zzz", .body, .primary), target: OverlayContrast.largeTextMinimum),
    ]

    static let elements: [Element] = [
        Element(name: "controls", styles: [
            Style(name: "title", words: "Preset name: Fumbling Foo", kind: .text(.subheadline.weight(.semibold), .primary)),
            Style(name: "times", words: "0:42  -3:15", kind: .text(.caption.monospacedDigit(), .secondary)),
            Style(name: "tempo", words: "≈ 120 BPM · Searching", kind: .text(.caption, .secondary)),
            Style(name: "cue", words: "Cue 2 of 5 · Intro", kind: .text(.footnote, .primary)),
            Style(name: "tintButton", words: "Presets", kind: .plainButton(.footnote)),
            Style(name: "bordered", words: "Tap", kind: .bordered(.footnote)),
            Style(name: "repeatSymbol", words: "", kind: .symbol("repeat", .body, .color(.accentColor)), target: OverlayContrast.largeTextMinimum),
            Style(name: "statusSymbol", words: "", kind: .symbol("waveform", .body, .color(InterfacePalette.color(.positive))),
                  target: OverlayContrast.largeTextMinimum),
        ]),
        Element(name: "sourceIndicator", styles: [
            Style(name: "cue", words: "", kind: .cue(StatusCueCatalog.source(.active), .footnote.weight(.semibold))),
            Style(name: "cueWaiting", words: "", kind: .cue(StatusCueCatalog.source(.noAudioReceived), .footnote.weight(.semibold))),
        ]),
        Element(name: "cameraBadge", styles: [
            Style(name: "cue", words: "", kind: .cue(StatusCueCatalog.camera(running: true, label: "Camera on", differentiateWithoutColor: true),
                                                  .footnote.weight(.semibold))),
            Style(name: "stop", words: "Stop camera", kind: .prominentCritical(.footnote.bold())),
        ]),
        Element(name: "oscBadge", styles: [
            Style(name: "words", words: "OSC listening on port 9000", kind: .text(.footnote.weight(.semibold), .primary)),
            Style(name: "stop", words: "Stop", kind: .plainButton(.footnote.bold())),
        ]),
        Element(name: "blackoutBadge", styles: [
            Style(name: "cue", words: "", kind: .cue(StatusCueCatalog.blackout(blackedOut: true), .footnote.bold())),
            Style(name: "restore", words: "Restore", kind: .prominent(.footnote)),
        ]),
        Element(name: "recordingBadge", styles: [
            Style(name: "cue", words: "", kind: .cue(StatusCueCatalog.recording(finishing: false, elapsed: "0:05"), .footnote.monospacedDigit().bold())),
        ]),
        Element(name: "statusCaption", styles: [
            Style(name: "words", words: "Output restored", kind: .text(.footnote.weight(.semibold), .primary)),
        ]),
        Element(name: "routeExplanation", styles: [
            Style(name: "words", words: "Headphones disconnected", kind: .text(.footnote, .primary)),
        ]),
        Element(name: "showNotice", styles: [
            Style(name: "words", words: "Scene Intro is missing", kind: .text(.footnote, .primary)),
        ]),
        Element(name: "notices", styles: tintPlainStyles),
        Element(name: "captureResult", styles: [
            Style(name: "title", words: "Frame ready", kind: .text(.footnote.bold(), .primary)),
            Style(name: "save", words: "Save…", kind: .plainButton(.footnote)),
            Style(name: "discard", words: "Discard", kind: .destructiveButton(.footnote)),
        ]),
        Element(name: "recoveryOffer", styles: [
            Style(name: "title", words: "The app closed unexpectedly", kind: .text(.headline, .primary)),
            Style(name: "message", words: "Reopen the last scene?", kind: .text(.footnote, .primary)),
            Style(name: "reopen", words: "Reopen last scene", kind: .prominent(.footnote.bold())),
            Style(name: "fresh", words: "Start fresh", kind: .bordered(.footnote.bold())),
        ]),
        Element(name: "statusBanner", styles: [
            Style(name: "headline", words: "Microphone · Interrupted", kind: .text(.headline, .primary)),
            Style(name: "detail", words: "Another app took the audio", kind: .text(.subheadline, .primary)),
            Style(name: "hold", words: "Playback continues when it ends", kind: .text(.footnote, .secondary)),
            Style(name: "action", words: "Resume", kind: .bordered(.body)),
            Style(name: "activeSymbol", words: "", kind: .symbol("waveform", .headline, .color(.green)), target: OverlayContrast.largeTextMinimum),
        ]),
        Element(name: "sceneSwitcher", styles: [
            Style(name: "row", words: "Intro scene", kind: .text(.body, .primary)),
            Style(name: "detail", words: "Edited 2 minutes ago", kind: .text(.caption, .secondary)),
            Style(name: "hint", words: "Type to search scenes", kind: .text(.footnote, .secondary)),
            Style(name: "highlighted", words: "Intro scene", kind: .onFill(.body, Color.accentColor.opacity(0.28))),
        ]),
        Element(name: "emergencyBlackout", styles: [
            Style(name: "symbol", words: "", kind: .symbol("eye.slash", .system(size: 17, weight: .semibold), .primary),
                  target: OverlayContrast.largeTextMinimum),
        ]),
        // ACC-008-R7: kept as they are; they pass on their own backings.
        Element(name: "performanceOverlay", styles: [
            Style(name: "metrics", words: "frame 16.7 ms (max 21.0)", kind: .text(.system(.caption, design: .monospaced), .color(.white))),
        ], backing: .scrim(0.6, .dark)),
        Element(name: "pausedLabel", styles: [
            Style(name: "paused", words: "Paused", kind: .text(.largeTitle.bold(), .color(.white)), target: OverlayContrast.largeTextMinimum),
        ], backing: .scrim(0.5, .dark)),
    ]

    // MARK: - Measurement

    struct Measurement {
        let corePixels: Int
        let p5: Double
        let median: Double
    }

    /// sRGB 8-bit → linear.
    private static let linear: [Double] = (0...255).map { (v: Int) -> Double in
        let c = Double(v) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Relative luminance of every pixel of the rendering.
    func luminance(_ view: some View) throws -> [Double] {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image: CGImage = try XCTUnwrap(renderer.cgImage, "rendered")
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
        var result = [Double](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            result[i] = 0.2126 * Self.linear[Int(rgba[i * 4])] + 0.7152 * Self.linear[Int(rgba[i * 4 + 1])]
                + 0.0722 * Self.linear[Int(rgba[i * 4 + 2])]
        }
        return result
    }

    static func encoded(_ y: Double) -> Double {
        y <= 0.0031308 ? y * 12.92 : 1.055 * pow(y, 1 / 2.4) - 0.055
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[index]
    }

    /// Core pixels differ by at least this share of the strong (full-coverage) difference (research D1).
    static let coreShare = 0.9

    /// Steps 4-6 of the method, from the two renderings' luminances.
    static func measure(withText: [Double], withoutText: [Double]) -> Measurement {
        precondition(withText.count == withoutText.count, "same size")
        let differences: [Double] = zip(withText, withoutText).map { (a: Double, b: Double) -> Double in abs(encoded(a) - encoded(b)) }
        let strong: Double = percentile(differences.filter { $0 > 4.0 / 255 }.sorted(), 0.95)
        guard strong > 0 else { return Measurement(corePixels: 0, p5: 1, median: 1) }
        var ratios: [Double] = []
        for i in 0..<differences.count where differences[i] >= Self.coreShare * strong {
            let high: Double = max(withText[i], withoutText[i])
            let low: Double = min(withText[i], withoutText[i])
            ratios.append((high + 0.05) / (low + 0.05))
        }
        ratios.sort()
        return Measurement(corePixels: ratios.count, p5: percentile(ratios, 0.05), median: percentile(ratios, 0.5))
    }

    private func canvas(_ style: Style, backing: Backing, frame: Frame, showsText: Bool, increased: Bool) -> some View {
        ZStack {
            Self.frameView(frame)
            Specimen(style: style, backing: backing, showsText: showsText).fixedSize()
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .environment(\.statusAppearance, StatusAppearance(increasedContrast: increased, differentiateWithoutColor: false))
    }

    func measure(_ style: Style, backing: Backing, frame: Frame, increased: Bool = false) throws -> Measurement {
        let with: [Double] = try luminance(canvas(style, backing: backing, frame: frame, showsText: true, increased: increased))
        let without: [Double] = try luminance(canvas(style, backing: backing, frame: frame, showsText: false, increased: increased))
        return Self.measure(withText: with, withoutText: without)
    }

    private func report(_ element: String, _ style: Style, _ frame: String, _ m: Measurement) -> String {
        "ACC-008 contrast \(element) \(style.name) \(frame): p5 \(String(format: "%.2f", m.p5)) median "
            + "\(String(format: "%.2f", m.median)) target \(String(format: "%.1f", style.target)) core \(m.corePixels)"
    }

    /// Asserts every style of `elements` over `frames`; returns the number of rows checked.
    @discardableResult
    private func assertTable(_ elements: [Element], frames: [Frame], increased: Bool = false) throws -> Int {
        var rows = 0
        for element in elements {
            for style in element.styles {
                for frame in frames {
                    let m: Measurement = try measure(style, backing: element.backing, frame: frame, increased: increased)
                    let label: String = report(element.name, style, frame.rawValue + (increased ? "+IC" : ""), m)
                    print(label)
                    XCTAssertGreaterThanOrEqual(m.corePixels, 20, "\(label): the text is drawn")
                    XCTAssertGreaterThanOrEqual(m.p5, style.target, label)
                    rows += 1
                }
            }
        }
        return rows
    }

    // MARK: - ACC-008-S1: the snapshot table

    func testControlsMeetTheTargetOverEveryFrame() throws {   // US1
        let rows: Int = try assertTable(Self.elements.filter { $0.name == "controls" }, frames: Frame.allCases)
        XCTAssertEqual(rows, 8 * 4)
    }

    func testBadgesAndCaptionsMeetTheTargetOverEveryFrame() throws {   // US2
        let names: Set<String> = ["sourceIndicator", "cameraBadge", "oscBadge", "blackoutBadge", "recordingBadge", "statusCaption",
                                  "routeExplanation", "showNotice", "emergencyBlackout"]
        let rows: Int = try assertTable(Self.elements.filter { names.contains($0.name) }, frames: Frame.allCases)
        XCTAssertEqual(rows, 13 * 4)
    }

    func testNoticesPanelsAndCardsMeetTheTargetOverEveryFrame() throws {   // US2
        let names: Set<String> = ["notices", "captureResult", "recoveryOffer", "statusBanner", "sceneSwitcher",
                                  "performanceOverlay", "pausedLabel"]
        let rows: Int = try assertTable(Self.elements.filter { names.contains($0.name) }, frames: Frame.allCases)
        XCTAssertEqual(rows, 22 * 4)
    }

    /// ACC-008-R6: with Increase Contrast the backing is opaque; every surface style still passes over white.
    func testIncreaseContrastBackingIsOpaqueAndPasses() throws {
        XCTAssertEqual(OverlayContrast.scrim(increasedContrast: true), 1.0)
        let surfaced: [Element] = Self.elements.filter { if case .surface = $0.backing { true } else { false } }
        let rows: Int = try assertTable(surfaced, frames: [.white], increased: true)
        XCTAssertEqual(rows, 41)
        // Opaque: the frame no longer shows through (white and black frames give the same backing).
        let probe = Style(name: "probe", words: "Output restored", kind: .text(.footnote, .primary))
        let onWhite: [Double] = try luminance(canvas(probe, backing: .surface, frame: .white, showsText: false, increased: true))
        let onBlack: [Double] = try luminance(canvas(probe, backing: .surface, frame: .black, showsText: false, increased: true))
        let centre: Int = (onWhite.count / 2) + Int(Self.canvas.width)   // the middle row, middle column at scale 2
        XCTAssertEqual(onWhite[centre], onBlack[centre], accuracy: 0.001)
    }

    // MARK: - ACC-008-D2: the scrim is the lightest passing level

    /// The weakest styles pass at `scrimOpacity` and at least one fails 0.02 lighter, over white: the constant is the
    /// lightest passing level (0.83 on the iOS 27.2 simulator, 2026-11-14) plus one 0.01 step of headroom for
    /// rendering differences between OS versions (research D2).
    func testScrimIsTheLightestPassingLevel() throws {
        let surfaced: [(String, Style)] = Self.elements.filter { if case .surface = $0.backing { true } else { false } }
            .flatMap { (element: Element) -> [(String, Style)] in element.styles.map { (element.name, $0) } }
        var margins: [(String, Style, Double)] = []
        for (name, style) in surfaced {
            let m: Measurement = try measure(style, backing: .scrim(OverlayContrast.scrimOpacity, .dark), frame: .white)
            margins.append((name, style, m.p5 / style.target))
        }
        margins.sort { $0.2 < $1.2 }
        let weakest = margins.prefix(3)
        for (name, style, margin) in weakest {
            print("ACC-008 weakest \(name) \(style.name): \(String(format: "%.3f", margin)) of target")
            XCTAssertGreaterThanOrEqual(margin, 1, "\(name) \(style.name) passes at \(OverlayContrast.scrimOpacity)")
        }
        let lighter: Double = OverlayContrast.scrimOpacity - 0.02
        var failures = 0
        for (name, style, _) in weakest {
            let m: Measurement = try measure(style, backing: .scrim(lighter, .dark), frame: .white)
            print("ACC-008 at \(String(format: "%.2f", lighter)) \(name) \(style.name): p5 \(String(format: "%.2f", m.p5))")
            if m.p5 < style.target { failures += 1 }
        }
        XCTAssertGreaterThan(failures, 0, "a scrim of \(lighter) would still pass: lower scrimOpacity")
    }

    // MARK: - ACC-008-R9, S2: negative controls and the previous backings

    func testNegativeControlLowContrastLabelFails() throws {
        let grey = Style(name: "grey777", words: "Low contrast label", kind: .text(.footnote, .color(Color(.sRGB, red: 0x77 / 255.0,
                                                                                                           green: 0x77 / 255.0,
                                                                                                           blue: 0x77 / 255.0))))
        for frame in Frame.allCases {
            let m: Measurement = try measure(grey, backing: .surface, frame: frame)
            print(report("negativeControl", grey, frame.rawValue, m))
            XCTAssertGreaterThanOrEqual(m.corePixels, 20, "the control is drawn")
            XCTAssertLessThan(m.p5, OverlayContrast.normalTextMinimum, "\(frame): a grey label must fail the check")
        }
    }

    /// The audit's "before" column: ACC-004's 45% backing and the material-only badges (material counted as
    /// transparent) miss 4.5:1.
    func testPreviousBackingsMissTheTarget() throws {
        let primary = Style(name: "primary", words: "Preset name: Fumbling Foo", kind: .text(.footnote, .primary))
        let secondary = Style(name: "secondary", words: "0:42  -3:15", kind: .text(.caption, .secondary))
        let cases: [(String, Backing, Frame, Style)] = [
            ("controls45", .scrim(0.45, .dark), .white, primary),
            ("controls45", .scrim(0.45, .dark), .white, secondary),
            ("materialOnlyDark", .scrim(0, .dark), .white, primary),
            ("materialOnlyLight", .scrim(0, .light), .black, primary),
        ]
        for (name, backing, frame, style) in cases {
            let m: Measurement = try measure(style, backing: backing, frame: frame)
            print(report("before-" + name, style, frame.rawValue, m))
            XCTAssertLessThan(m.p5, OverlayContrast.normalTextMinimum, "\(name) \(style.name) over \(frame)")
        }
    }

    // MARK: - ACC-008-T11: the constants (computed, no rendering)

    func testScrimLevelsAndTintRatios() {
        XCTAssertEqual(OverlayContrast.scrim(increasedContrast: false), OverlayContrast.scrimOpacity)
        XCTAssertEqual(OverlayContrast.scrim(increasedContrast: true), 1.0)
        XCTAssertEqual(OverlayContrast.scrimOverWhite(1), 0x000000)
        XCTAssertEqual(OverlayContrast.scrimOverWhite(0), 0xFFFFFF)
        let backing: UInt32 = OverlayContrast.scrimOverWhite(OverlayContrast.scrimOpacity)
        XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(0xFFFFFF, backing), 7, "white text on the scrim over white")
        XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(OverlayContrast.tintHex, backing), OverlayContrast.normalTextMinimum,
                                    "overlay tint on the scrim over white")
        XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(0xFFFFFF, OverlayContrast.prominentTintHex), OverlayContrast.normalTextMinimum,
                                    "white on the prominent fill")
        XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(0xFFFFFF, InterfacePalette.critical.light), OverlayContrast.normalTextMinimum,
                                    "white on the critical fill")
        // Why the overlay needs its own tints (research D4): the default dark accent fails both ways.
        XCTAssertLessThan(InterfacePalette.contrastRatio(0x0A84FF, backing), OverlayContrast.normalTextMinimum)
        XCTAssertLessThan(InterfacePalette.contrastRatio(0xFFFFFF, 0x0A84FF), OverlayContrast.normalTextMinimum)
                XCTAssertEqual(OverlayContrast.prominentTintHex, InterfacePalette.accent.light)
        #if DEBUG
        XCTAssertEqual(OverlaySurfaceProbe.value(increasedContrast: false), "scrim:0.84")
        XCTAssertEqual(OverlaySurfaceProbe.value(increasedContrast: true), "scrim:1.00")
        #endif
    }

    /// The measure itself: a uniform pair gives exactly the WCAG ratio, and identical renderings give no core.
    func testMeasureMatchesTheWCAGFormula() {
        let background = [Double](repeating: 0.2, count: 400)
        var text = background
        for i in 100..<200 { text[i] = 1.0 }
        let m: Measurement = Self.measure(withText: text, withoutText: background)
        XCTAssertEqual(m.corePixels, 100)
        XCTAssertEqual(m.p5, 1.05 / 0.25, accuracy: 0.0001)
        XCTAssertEqual(Self.measure(withText: background, withoutText: background).corePixels, 0)
    }
}
