// ExternalOutputResolutionTests.swift — OUT-003-T03 (OUT-003-S1): the resolved external output never
// exceeds the screen, the choice or the device budget, keeps the screen's shape within one pixel, and
// is native when nothing limits it. Representative cases (owner rule 7), not the full cross-product.
import PresentationLifecycle
import XCTest

final class ExternalOutputResolutionTests: XCTestCase {
    /// REC-014's caps (RecordingOutputCap.compact / .regular).
    private let compact = ExternalPixelBudget(maxSide: 2560, maxPixels: 2560 * 1440)
    private let regular = ExternalPixelBudget(maxSide: 4096, maxPixels: 3840 * 2160)

    private func resolve(_ mode: ExternalResolutionMode, percent: Int = 75, points: (Double, Double),
                         scale: Double, budget: ExternalPixelBudget) -> ResolvedExternalOutput {
        ExternalOutputResolution(mode: mode, percent: percent)
            .resolve(width: points.0, height: points.1, nativeScale: scale, budget: budget)
    }

    func testFixedModesFitTheirBoxOnALargerScreen() {
        // A 4K screen reported as 1920 × 1080 points at scale 2.
        let p1080 = resolve(.hd1080, points: (1920, 1080), scale: 2, budget: regular)
        XCTAssertEqual([p1080.pixelWidth, p1080.pixelHeight], [1920, 1080])
        XCTAssertEqual(p1080.scale, 1, accuracy: 1e-9)
        XCTAssertFalse(p1080.clamped)
        XCTAssertFalse(p1080.isNative)
        let p720 = resolve(.hd720, points: (1920, 1080), scale: 2, budget: regular)
        XCTAssertEqual([p720.pixelWidth, p720.pixelHeight], [1280, 720])
        XCTAssertEqual(p720.scale, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testNativeIsUnchangedWhenNothingLimitsIt() {
        let native = resolve(.native, points: (1920, 1080), scale: 1, budget: regular)
        XCTAssertEqual([native.pixelWidth, native.pixelHeight], [1920, 1080])
        XCTAssertTrue(native.isNative)
        XCTAssertFalse(native.clamped)
        XCTAssertEqual(native.scale, 1)
        let regular4K = resolve(.native, points: (1920, 1080), scale: 2, budget: regular)
        XCTAssertEqual([regular4K.pixelWidth, regular4K.pixelHeight], [3840, 2160], "4K fits a regular device's budget")
        XCTAssertTrue(regular4K.isNative)
    }

    func testNeverUpscalesASmallerScreen() {
        for mode in [ExternalResolutionMode.hd1080, .hd720, .native] {
            let small = resolve(mode, points: (1280, 720), scale: 1, budget: regular)
            XCTAssertEqual([small.pixelWidth, small.pixelHeight], [1280, 720], "\(mode)")
            XCTAssertTrue(small.isNative, "\(mode)")
        }
        let full = resolve(.custom, percent: 100, points: (1280, 720), scale: 1, budget: regular)
        XCTAssertTrue(full.isNative)
    }

    func testTheCompactBudgetClampsNative4K() {
        let clamped = resolve(.native, points: (1920, 1080), scale: 2, budget: compact)
        XCTAssertTrue(clamped.clamped)
        XCTAssertFalse(clamped.isNative)
        XCTAssertLessThanOrEqual(max(clamped.pixelWidth, clamped.pixelHeight), 2560)
        XCTAssertLessThanOrEqual(clamped.pixelWidth * clamped.pixelHeight, 2560 * 1440)
        XCTAssertEqual(Double(clamped.pixelWidth) / Double(clamped.pixelHeight), 16.0 / 9.0, accuracy: 2.0 / 1440)
        // The choice is below the budget: not clamped.
        let chosen = resolve(.hd1080, points: (1920, 1080), scale: 2, budget: compact)
        XCTAssertFalse(chosen.clamped)
        XCTAssertEqual([chosen.pixelWidth, chosen.pixelHeight], [1920, 1080])
    }

    func testCustomPercentageAndItsClamping() {
        let half = resolve(.custom, percent: 50, points: (1920, 1080), scale: 1, budget: regular)
        XCTAssertEqual([half.pixelWidth, half.pixelHeight], [960, 540])
        XCTAssertEqual(half.scale, 0.5, accuracy: 1e-9)
        XCTAssertEqual(ExternalOutputResolution(mode: .custom, percent: 10).percent, 50)
        XCTAssertEqual(ExternalOutputResolution(mode: .custom, percent: 400).percent, 100)
        var r = ExternalOutputResolution(mode: .custom, percent: 80)
        r.percent = 5
        XCTAssertEqual(r.percent, 50)
    }

    func testPortraitAnd4by3ScreensKeepTheirShapeInsideTheBox() {
        let portrait = resolve(.hd1080, points: (1080, 1920), scale: 2, budget: regular)
        XCTAssertEqual([portrait.pixelWidth, portrait.pixelHeight], [1080, 1920])
        let fourThree = resolve(.hd720, points: (2048, 1536), scale: 1, budget: regular)
        XCTAssertLessThanOrEqual(fourThree.pixelWidth, 1280)
        XCTAssertLessThanOrEqual(fourThree.pixelHeight, 720)
        XCTAssertEqual(fourThree.pixelHeight, 720, "the short side is the limit")
        XCTAssertEqual(Double(fourThree.pixelWidth) / Double(fourThree.pixelHeight), 4.0 / 3.0, accuracy: 1.0 / 720 * 2)
    }

    func testEveryRepresentativeResultStaysInsideItsLimits() {
        let screens: [((Double, Double), Double)] = [((1920, 1080), 2), ((1920, 1080), 1), ((1280, 720), 1), ((1366, 768), 1.5)]
        let choices: [ExternalOutputResolution] = [.native, .init(mode: .hd1080), .init(mode: .hd720), .init(mode: .custom, percent: 65)]
        for (points, scale) in screens {
            for choice in choices {
                for budget in [compact, regular] {
                    let r = choice.resolve(width: points.0, height: points.1, nativeScale: scale, budget: budget)
                    let nw = Int((points.0 * scale).rounded()), nh = Int((points.1 * scale).rounded())
                    let label = "\(points) @\(scale) \(choice.mode) \(budget.maxSide)"
                    XCTAssertLessThanOrEqual(r.pixelWidth, nw, label)
                    XCTAssertLessThanOrEqual(r.pixelHeight, nh, label)
                    XCTAssertLessThanOrEqual(max(r.pixelWidth, r.pixelHeight), budget.maxSide, label)
                    XCTAssertLessThanOrEqual(r.pixelWidth * r.pixelHeight, budget.maxPixels, label)
                    if let box = choice.mode.box {
                        XCTAssertLessThanOrEqual(Double(max(r.pixelWidth, r.pixelHeight)), box.long, label)
                        XCTAssertLessThanOrEqual(Double(min(r.pixelWidth, r.pixelHeight)), box.short, label)
                    }
                    // The shape within one pixel: the width predicted from the height and the screen's ratio.
                    XCTAssertEqual(Double(r.pixelWidth), Double(r.pixelHeight) * points.0 / points.1, accuracy: 1.0, label)
                }
            }
        }
    }

    func testInvalidInputGivesNoOverride() {
        let zero = ExternalOutputResolution(mode: .hd720).resolve(width: 0, height: 1080, nativeScale: 2, budget: regular)
        XCTAssertTrue(zero.isNative)
        XCTAssertEqual(zero.pixelWidth, 0)
        XCTAssertEqual(zero.scale, 2)
        let nan = ExternalOutputResolution(mode: .hd720).resolve(width: 100, height: 100, nativeScale: .nan, budget: regular)
        XCTAssertTrue(nan.isNative)
        XCTAssertEqual(nan.scale, 0)
    }

    func testStoredNamesAreStable() {
        XCTAssertEqual(ExternalResolutionMode.allCases.map(\.rawValue), ["native", "1080p", "720p", "custom"])
    }
}
