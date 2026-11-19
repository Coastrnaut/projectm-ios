// GuidedFirstScenePaletteTests.swift — UIX-001 (QA-011 prompt flow, 2026-11-19): the tutorial's secondary text
// ("Step 1 of 5", each visual's description) "nearly passed" the contrast audit on D2 and D3 in the system secondary
// grey. Its own colour must reach WCAG 4.5:1 on the page and grouped backgrounds, light and dark, and the
// Increase Contrast minimums (ACC-003-R6, R7), while the grey it replaced stays below 4.5:1 (negative control).
import XCTest
@testable import projectM_iOS

@MainActor
final class GuidedFirstScenePaletteTests: XCTestCase {
    private let entry = GuidedFirstScenePalette.secondaryEntry

    func testSecondaryTextMeetsWCAGOnEveryBackground() {
        for background in InterfacePalette.lightBackgrounds {
            XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.light, background), InterfacePalette.standardMinimum,
                                        String(format: "light on %06X", background))
            XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.lightIncreased, background),
                                        InterfacePalette.increasedGroupedMinimum, String(format: "light, increased, on %06X", background))
        }
        for background in InterfacePalette.darkBackgrounds {
            XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.dark, background), InterfacePalette.standardMinimum,
                                        String(format: "dark on %06X", background))
            XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.darkIncreased, background),
                                        InterfacePalette.increasedGroupedMinimum, String(format: "dark, increased, on %06X", background))
        }
        XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.lightIncreased, 0xFFFFFF), InterfacePalette.increasedPageMinimum)
        XCTAssertGreaterThanOrEqual(InterfacePalette.contrastRatio(entry.darkIncreased, 0x000000), InterfacePalette.increasedPageMinimum)
    }

    /// The system secondary label (#3C3C43 at 60%) over white composites to about #8A8A8E: below 4.5:1.
    func testTheReplacedSystemGreyFails() {
        XCTAssertLessThan(InterfacePalette.contrastRatio(0x8A8A8E, 0xFFFFFF), InterfacePalette.standardMinimum)
    }
}
