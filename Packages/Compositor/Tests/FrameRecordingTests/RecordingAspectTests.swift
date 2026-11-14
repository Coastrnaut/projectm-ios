// RecordingAspectTests.swift — REC-014-T05, T10: the row's acceptance in plain Swift ("Export dimensions match
// preset and never exceed device memory cap"). A sweep of every aspect × profile × representative drawable ×
// device class checks the planned output against an independent brute-force reference and the invariants (even,
// exact ratio, within the cap, never above the centred crop); custom sizes, validation, the profile fallback and
// the reduced-size notice. No GPU; builds and runs on Linux.
@testable import FrameRecording
import XCTest

/// Capabilities with an injected output cap (the rest as `StubCapabilities`).
private struct CappedCapabilities: RecordingEncoderCapabilities {
    var cap: RecordingOutputCap
    var hevc = true
    var maxFramesPerSecond = 60
    func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool { codec == .hevc ? hevc : true }
    var outputCap: RecordingOutputCap { cap }
}

final class RecordingAspectTests: XCTestCase {
    static let drawables: [(Int, Int)] = [(1179, 2556), (2048, 2732), (2732, 2048), (2064, 2752), (320, 240)]
    static let presets: [RecordingAspect] = [.portrait, .square, .landscape]
    static let caps: [RecordingOutputCap] = [.compact, .regular]

    /// Brute force: the largest m with (u·m, v·m) even, ≤ the side limit, ≤ the crop, ≤ the pixel budget.
    private static func reference(_ ratio: (width: Int, height: Int), drawable: (Int, Int), longSide: Int,
                                  cap: RecordingOutputCap) -> (Int, Int)? {
        let w = drawable.0 / 2 * 2, h = drawable.1 / 2 * 2
        let scale = min(Double(w) / Double(ratio.width), Double(h) / Double(ratio.height))   // crop = ratio × scale
        let side = min(longSide / 2 * 2, cap.maxSide)
        for m in stride(from: 5000, through: 1, by: -1) {
            let ow = ratio.width * m, oh = ratio.height * m
            guard ow % 2 == 0, oh % 2 == 0, max(ow, oh) <= side, ow * oh <= cap.maxPixels,
                  Double(m) <= scale + 1e-9 else { continue }
            return (ow, oh)
        }
        return nil
    }

    private func geometry(_ aspect: RecordingAspect, _ profile: RecordingQualityProfile, _ drawable: (Int, Int),
                          cap: RecordingOutputCap) -> RecordingGeometry? {
        var settings = profile.settings
        settings.aspect = aspect
        settings.outputCap = cap
        return RecordingGeometry(drawableWidth: drawable.0, drawableHeight: drawable.1, settings: settings)
    }

    private func assertInvariants(_ g: RecordingGeometry, cap: RecordingOutputCap, _ label: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(g.outputWidth % 2, 0, label, file: file, line: line)
        XCTAssertEqual(g.outputHeight % 2, 0, label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(min(g.outputWidth, g.outputHeight), 2, label, file: file, line: line)
        XCTAssertTrue(cap.contains(width: g.outputWidth, height: g.outputHeight), label, file: file, line: line)
        // Never upscaled: the output fits inside the source in both dimensions (the centred crop for a preset).
        XCTAssertLessThanOrEqual(g.outputWidth, g.sourceWidth, label, file: file, line: line)
        XCTAssertLessThanOrEqual(g.outputHeight, g.sourceHeight, label, file: file, line: line)
    }

    // MARK: - REC-014-S1: the sweep

    func testPresetsMatchTheReferenceForEveryProfileDrawableAndCap() throws {
        var checked = 0
        for aspect in Self.presets {
            let ratio = try XCTUnwrap(aspect.ratio)
            for profile in RecordingQualityProfile.allCases {
                for drawable in Self.drawables {
                    for cap in Self.caps {
                        let label = "\(aspect) \(profile) \(drawable) cap \(cap.maxSide)"
                        let expected = Self.reference(ratio, drawable: drawable, longSide: profile.settings.maxLongSide, cap: cap)
                        let g = geometry(aspect, profile, drawable, cap: cap)
                        XCTAssertEqual(g.map { [$0.outputWidth, $0.outputHeight] }, expected.map { [$0.0, $0.1] }, label)
                        guard let g else { continue }
                        XCTAssertEqual(g.outputWidth * ratio.height, g.outputHeight * ratio.width, "exact ratio " + label)
                        XCTAssertTrue(g.cropsToFill, label)
                        XCTAssertNil(g.reducedCustomSize, label)
                        assertInvariants(g, cap: cap, label)
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 3 * 4 * 5 * 2)
    }

    /// The spec's scenarios as exact numbers.
    func testSpecScenarios() throws {
        let phone = (1179, 2556), ipad = (2048, 2732)
        let square = try XCTUnwrap(geometry(.square, .standard, phone, cap: .regular))
        XCTAssertEqual([square.outputWidth, square.outputHeight], [1178, 1178])
        let portrait = try XCTUnwrap(geometry(.portrait, .standard, ipad, cap: .regular))
        XCTAssertEqual([portrait.outputWidth, portrait.outputHeight], [1080, 1920])
        let landscape = try XCTUnwrap(geometry(.landscape, .standard, phone, cap: .regular))
        XCTAssertEqual([landscape.outputWidth, landscape.outputHeight], [1152, 648])
        let draft = try XCTUnwrap(geometry(.landscape, .draft, (2732, 2048), cap: .regular))
        XCTAssertEqual([draft.outputWidth, draft.outputHeight], [1280, 720])
        let high = try XCTUnwrap(geometry(.portrait, .high, ipad, cap: .regular))
        XCTAssertEqual([high.outputWidth, high.outputHeight], [1440, 2560])
        XCTAssertNil(geometry(.landscape, .standard, (30, 16), cap: .regular), "smaller than 32×18: no picture")
    }

    /// REC-014-S3: Match screen is REC-005's geometry wherever the screen fits the cap, and capped otherwise.
    func testMatchScreenIsUnchangedAndCapped() throws {
        for profile in RecordingQualityProfile.allCases {
            for drawable in Self.drawables {
                let old = try XCTUnwrap(RecordingGeometry(drawableWidth: drawable.0, drawableHeight: drawable.1,
                                                          maxLongSide: profile.settings.maxLongSide))
                let new = try XCTUnwrap(geometry(.matchScreen, profile, drawable, cap: .regular))
                XCTAssertEqual(old, new, "\(profile) \(drawable)")
                XCTAssertFalse(new.cropsToFill)
                assertInvariants(new, cap: .regular, "\(profile) \(drawable)")
                let compact = try XCTUnwrap(geometry(.matchScreen, profile, drawable, cap: .compact))
                assertInvariants(compact, cap: .compact, "compact \(profile) \(drawable)")
            }
        }
        // A screen above the cap (Max on a 6K drawable): within 4096 px and 8 294 400 pixels, aspect kept.
        let big = try XCTUnwrap(geometry(.matchScreen, .max, (6016, 3384), cap: .regular))
        assertInvariants(big, cap: .regular, "6K")
        XCTAssertEqual(Double(big.outputWidth) / Double(big.outputHeight), 6016.0 / 3384.0, accuracy: 0.01)
        let compact = try XCTUnwrap(geometry(.matchScreen, .max, (2064, 2752), cap: .compact))
        XCTAssertEqual([compact.outputWidth, compact.outputHeight], [1662, 2216])
    }

    // MARK: - REC-014-T10: custom sizes

    func testCustomSizeValidation() {
        XCTAssertEqual(RecordingCustomSize(width: 1081, height: 1351), RecordingCustomSize(width: 1080, height: 1350))
        XCTAssertEqual(RecordingCustomSize(width: 50, height: 9000), RecordingCustomSize(width: 128, height: 4096))
        XCTAssertEqual(RecordingCustomSize(width: -3, height: 4097).width, 128)
        XCTAssertEqual(RecordingCustomSize(width: -3, height: 4097).height, 4096)
        XCTAssertEqual(RecordingCustomSize.defaultSize, RecordingCustomSize(width: 1080, height: 1350))
        XCTAssertEqual(RecordingAspect(kind: .custom, customSize: RecordingCustomSize(width: 640, height: 480)).ratio?.width, 4)
        XCTAssertEqual(RecordingAspect.Kind(rawValue: "square"), .square)
        XCTAssertNil(RecordingAspect.Kind(rawValue: "wide"))
    }

    func testCustomSizesFitExactlyOrAreReducedWithinTheCap() throws {
        let ipad = (2048, 2732)
        let fits = try XCTUnwrap(geometry(.custom(RecordingCustomSize(width: 1080, height: 1350)), .standard, ipad, cap: .regular))
        XCTAssertEqual([fits.outputWidth, fits.outputHeight], [1080, 1350])
        XCTAssertNil(fits.reducedCustomSize)

        // Larger than the crop (phone width 1178): 4:5 reduced to the largest even multiple within the crop.
        let asked = RecordingCustomSize(width: 2000, height: 2500)
        let crop = try XCTUnwrap(geometry(.custom(asked), .max, (1179, 2556), cap: .regular))
        XCTAssertEqual([crop.outputWidth, crop.outputHeight], [1176, 1470])
        XCTAssertEqual(crop.reducedCustomSize, asked)

        // 4096×4096 on the compact class: ≤ 2560 px, ≤ 3 686 400 pixels, square kept.
        for drawable in [(2732, 2048), (4096, 4096)] {
            let big = try XCTUnwrap(geometry(.custom(RecordingCustomSize(width: 4096, height: 4096)), .max, drawable, cap: .compact))
            assertInvariants(big, cap: .compact, "compact \(drawable)")
            XCTAssertEqual(big.outputWidth, big.outputHeight)
            XCTAssertNotNil(big.reducedCustomSize)
        }
        let ipadCompact = try XCTUnwrap(geometry(.custom(RecordingCustomSize(width: 4096, height: 4096)), .max, (4096, 4096), cap: .compact))
        XCTAssertEqual([ipadCompact.outputWidth, ipadCompact.outputHeight], [1920, 1920])

        // A ratio with no small even multiple (959:540): uniform scale, sides floored to even.
        let odd = try XCTUnwrap(geometry(.custom(RecordingCustomSize(width: 1918, height: 1080)), .draft, (2732, 2048), cap: .regular))
        XCTAssertEqual([odd.outputWidth, odd.outputHeight], [1280, 720])
        XCTAssertEqual(Double(odd.outputWidth) / Double(odd.outputHeight), 1918.0 / 1080.0, accuracy: 2.0 / 720.0)
        assertInvariants(odd, cap: .regular, "959:540")
    }

    // MARK: - Catalog, fallback and notice (contracts C2, C4)

    func testCatalogUsesTheAspectAndTheCapabilitiesCap() throws {
        let caps = CappedCapabilities(cap: .compact)
        let plan = try XCTUnwrap(RecordingQualityCatalog.availability(of: .max, drawableWidth: 2732, drawableHeight: 2048,
                                                                      aspect: .square, capabilities: caps).plan)
        XCTAssertEqual([plan.geometry.outputWidth, plan.geometry.outputHeight], [1920, 1920])
        XCTAssertEqual(plan.settings.aspect, .square)
        XCTAssertEqual(plan.settings.outputCap, .compact)
        XCTAssertEqual(plan.summary, "1920×1920 · HEVC · 40 Mb/s · 60 fps")
        // Default parameters keep REC-005: Match screen with the regular cap.
        let screen = try XCTUnwrap(RecordingQualityCatalog.availability(of: .standard, drawableWidth: 1179, drawableHeight: 2556,
                                                                        capabilities: StubCapabilities()).plan)
        XCTAssertEqual([screen.geometry.outputWidth, screen.geometry.outputHeight], [884, 1920])
        XCTAssertEqual(screen.settings, RecordingSettings.standard)
    }

    /// REC-014-R12: a profile fallback keeps the aspect.
    func testProfileFallbackKeepsTheAspect() throws {
        let caps = CappedCapabilities(cap: .regular, hevc: false)
        let resolution = RecordingFrameRateCatalog.resolve(profile: .high, choice: .profileDefault, drawableWidth: 1179,
                                                           drawableHeight: 2556, aspect: .square, capabilities: caps)
        let plan = try XCTUnwrap(resolution.plan)
        XCTAssertEqual(plan.profile, .standard)
        XCTAssertEqual([plan.geometry.outputWidth, plan.geometry.outputHeight], [1178, 1178])
        XCTAssertEqual(plan.codec, .h264)
        XCTAssertEqual(resolution.notice, "Recording at Standard: Needs HEVC, which this device cannot encode.")
    }

    func testReducedCustomSizeIsAnnounced() throws {
        let caps = CappedCapabilities(cap: .compact)
        let resolution = RecordingFrameRateCatalog.resolve(profile: .max, choice: .profileDefault, drawableWidth: 4096,
                                                           drawableHeight: 4096,
                                                           aspect: .custom(RecordingCustomSize(width: 4096, height: 4096)),
                                                           capabilities: caps)
        XCTAssertEqual(resolution.notice, "Recording at 1920×1920: Custom size reduced to fit this device.")
        let fits = RecordingFrameRateCatalog.resolve(profile: .standard, choice: .profileDefault, drawableWidth: 2048,
                                                     drawableHeight: 2732,
                                                     aspect: .custom(RecordingCustomSize(width: 1080, height: 1350)),
                                                     capabilities: caps)
        XCTAssertNil(fits.notice)
        XCTAssertTrue(RecordingAspectCatalog.reducedNotice(width: 2, height: 2).hasPrefix(RecordingQualityCatalog.fallbackPrefix))
    }

    func testDeviceCapClasses() {
        XCTAssertEqual(RecordingOutputCap.device(physicalMemory: 3 << 30), .compact)
        XCTAssertEqual(RecordingOutputCap.device(physicalMemory: 6 << 30), .regular)
        XCTAssertEqual(RecordingOutputCap.device(physicalMemory: 8 << 30, maxTextureSide: 2048).maxSide, 2048)
        XCTAssertEqual(RecordingOutputCap.compact.maxPixels, 3_686_400)
        XCTAssertEqual(RecordingOutputCap.regular.maxPixels, 8_294_400)
    }
}
