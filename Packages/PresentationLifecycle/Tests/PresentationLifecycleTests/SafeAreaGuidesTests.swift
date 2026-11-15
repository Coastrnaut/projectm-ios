// SafeAreaGuidesTests.swift — OUT-005-T03 (spec specs/258-out-005-safe-area-guides, S2; contract C1).
import XCTest
@testable import PresentationLifecycle

final class SafeAreaGuidesTests: XCTestCase {
    private func assertCentred(_ inner: SafeAreaGuideRect, in outer: SafeAreaGuideRect, fraction: Double,
                               _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(inner.midX, outer.midX, accuracy: 0.01, label, file: file, line: line)
        XCTAssertEqual(inner.midY, outer.midY, accuracy: 0.01, label, file: file, line: line)
        XCTAssertEqual(inner.width, outer.width * fraction, accuracy: 0.01, label, file: file, line: line)
        XCTAssertEqual(inner.height, outer.height * fraction, accuracy: 0.01, label, file: file, line: line)
    }

    func testDefaultsAreTheSMPTEValuesAndOffCross() {
        let choice = SafeAreaGuideChoice.default
        XCTAssertEqual(choice.actionPercent, 93)
        XCTAssertEqual(choice.titlePercent, 90)
        XCTAssertFalse(choice.showsCentreCross)
    }

    func testRectsAreCentredFractionsForSeveralShapes() throws {
        // (view width, view height, output aspect or nil for the whole view)
        let shapes: [(Double, Double, Double?)] = [
            (390, 844, nil),            // portrait phone, device output
            (390, 844, 16.0 / 9.0),     // portrait phone, 16:9 display
            (1024, 768, 4.0 / 3.0),     // 4:3 fills a 4:3 view
            (844, 390, 1.0),            // square display in landscape
        ]
        let choices: [SafeAreaGuideChoice] = [.default, SafeAreaGuideChoice(actionPercent: 90, titlePercent: 80)]
        for (width, height, aspect) in shapes {
            for choice in choices {
                let g = try XCTUnwrap(SafeAreaGuideGeometry.make(viewWidth: width, viewHeight: height, outputAspect: aspect, choice: choice))
                let label = "\(width)x\(height) aspect \(String(describing: aspect)) \(choice.actionPercent)/\(choice.titlePercent)"
                XCTAssertEqual(g.output.midX, width / 2, accuracy: 0.01, label)
                XCTAssertEqual(g.output.midY, height / 2, accuracy: 0.01, label)
                if let aspect { XCTAssertEqual(g.output.width / g.output.height, aspect, accuracy: 1e-9, label) }
                XCTAssertLessThanOrEqual(g.output.width, width + 1e-9, label)
                XCTAssertLessThanOrEqual(g.output.height, height + 1e-9, label)
                XCTAssertTrue(abs(g.output.width - width) < 1e-9 || abs(g.output.height - height) < 1e-9, "fitted: \(label)")
                assertCentred(g.actionSafe, in: g.output, fraction: Double(choice.actionPercent) / 100, label)
                assertCentred(g.titleSafe, in: g.output, fraction: Double(choice.titlePercent) / 100, label)
                XCTAssertNil(g.crossArm)
            }
        }
    }

    func testPortraitViewWith16By9OutputIsLetterboxed() throws {
        let g = try XCTUnwrap(SafeAreaGuideGeometry.make(viewWidth: 390, viewHeight: 844, outputAspect: 16.0 / 9.0, choice: .default))
        XCTAssertEqual(g.output.width, 390, accuracy: 1e-9)
        XCTAssertEqual(g.output.height, 390 * 9 / 16, accuracy: 1e-9)
        XCTAssertEqual(g.output.y, (844 - 390 * 9 / 16) / 2, accuracy: 1e-9)
        XCTAssertEqual(g.actionSafe.x, 390 * 0.035, accuracy: 1e-9, "93 %: 3.5 % margin each side")
    }

    func testClampingTitleInsideActionAndCross() throws {
        XCTAssertEqual(SafeAreaGuideChoice(actionPercent: 50, titlePercent: 10).actionPercent, 80)
        XCTAssertEqual(SafeAreaGuideChoice(actionPercent: 50, titlePercent: 10).titlePercent, 70)
        XCTAssertEqual(SafeAreaGuideChoice(actionPercent: 120, titlePercent: 140).actionPercent, 100)
        let wide = SafeAreaGuideChoice(actionPercent: 85, titlePercent: 95, showsCentreCross: true)
        XCTAssertEqual(wide.drawnTitlePercent, 85, "title-safe never outside action-safe")
        let g = try XCTUnwrap(SafeAreaGuideGeometry.make(viewWidth: 200, viewHeight: 100, outputAspect: nil, choice: wide))
        XCTAssertEqual(g.titleSafe, g.actionSafe)
        XCTAssertEqual(try XCTUnwrap(g.crossArm), 4, accuracy: 1e-9, "4 % of the shorter side")
        let full = try XCTUnwrap(SafeAreaGuideGeometry.make(viewWidth: 200, viewHeight: 100, outputAspect: nil,
                                                            choice: SafeAreaGuideChoice(actionPercent: 100, titlePercent: 100)))
        XCTAssertEqual(full.actionSafe, full.output, "100 %: on the frame's edge")
    }

    func testUnusableInputs() {
        XCTAssertNil(SafeAreaGuideGeometry.make(viewWidth: 0, viewHeight: 100, outputAspect: nil, choice: .default))
        XCTAssertNil(SafeAreaGuideGeometry.make(viewWidth: .nan, viewHeight: 100, outputAspect: nil, choice: .default))
        let whole = SafeAreaGuideGeometry.make(viewWidth: 100, viewHeight: 50, outputAspect: -1, choice: .default)
        XCTAssertEqual(whole?.output, SafeAreaGuideRect(x: 0, y: 0, width: 100, height: 50), "a bad aspect is the whole view")
        XCTAssertNil(SafeAreaGuideGeometry.externalAspect(width: 0, height: 1080, pixelAspect: 1))
        XCTAssertNil(SafeAreaGuideGeometry.externalAspect(width: 1920, height: 1080, pixelAspect: .infinity))
    }

    func testExternalAspectUsesThePixelAspect() throws {
        XCTAssertEqual(try XCTUnwrap(SafeAreaGuideGeometry.externalAspect(width: 1920, height: 1080, pixelAspect: 1)), 16.0 / 9.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(SafeAreaGuideGeometry.externalAspect(width: 720, height: 576, pixelAspect: 1.2)), 1.5, accuracy: 1e-12)
    }
}
