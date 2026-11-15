// OutputDiagnosticsTests.swift — OUT-011-T03 (contract C1): the snapshot from fake screen values formats correctly,
// missing or nonsensical values read "Not available", and the disconnected snapshot carries no value.
import XCTest
@testable import PresentationLifecycle

final class OutputDiagnosticsTests: XCTestCase {
    private let full = OutputReadings(nativeWidth: 3840, nativeHeight: 2160, nativeScale: 2, pointWidth: 1920, pointHeight: 1080,
                                      scale: 2, maximumFramesPerSecond: 60, gamut: .displayP3,
                                      potentialEDRHeadroom: 4, currentEDRHeadroom: 1.25, mirrored: false, overscan: .off,
                                      drawableWidth: 3840, drawableHeight: 2160, pixelAspect: 1, outputMode: "Same scene")

    private func values(_ d: OutputDiagnostics) -> [String: String] {
        Dictionary(uniqueKeysWithValues: d.rows.map { (row: OutputDiagnosticsRow) -> (String, String) in (row.id, row.value) })
    }

    func testFullReadingsFormatEveryRow() {
        let d = OutputDiagnostics.make(full)
        XCTAssertEqual(d.rows.map(\.title), ["Native resolution", "Size", "Refresh rate", "Color gamut", "EDR headroom",
                                             "Mirroring", "Drawable", "Overscan", "Pixel aspect", "Output"])
        let v = values(d)
        XCTAssertEqual(v["nativeResolution"], "3840 × 2160 px")
        XCTAssertEqual(v["size"], "1920 × 1080 pt @2x")
        XCTAssertEqual(v["refreshRate"], "60 Hz")
        XCTAssertEqual(v["gamut"], "Display P3")
        XCTAssertEqual(v["edr"], "4.0× potential, 1.3× current")
        XCTAssertEqual(v["mirroring"], "Extended")
        XCTAssertEqual(v["drawable"], "3840 × 2160 px")
        XCTAssertEqual(v["overscan"], "None")
        XCTAssertEqual(v["pixelAspect"], "1.00")
        XCTAssertEqual(v["outputMode"], "Same scene")
        XCTAssertEqual(d.summary, "connected native=3840x2160 pt=1920x1080@2 fps=60 drawable=3840x2160")
        XCTAssertTrue(d.text.hasPrefix("Native resolution: 3840 × 2160 px\nSize: 1920 × 1080 pt @2x\n"))
    }

    func testMissingValuesReadNotAvailable() {
        let d = OutputDiagnostics.make(OutputReadings())
        XCTAssertTrue(d.isConnected)
        XCTAssertEqual(d.rows.count, 10)
        for row in d.rows { XCTAssertEqual(row.value, OutputDiagnostics.notAvailable, row.id) }
        XCTAssertEqual(d.summary, "connected native=na pt=na@na fps=na drawable=na")
    }

    func testZeroAndNonFiniteReadingsAreNotGuessed() {
        var r = full
        r.maximumFramesPerSecond = 0
        r.nativeWidth = 0
        r.scale = .nan
        r.potentialEDRHeadroom = .infinity
        r.currentEDRHeadroom = 0
        r.pixelAspect = -1
        r.drawableHeight = nil
        let v = values(.make(r))
        XCTAssertEqual(v["refreshRate"], "Not available")
        XCTAssertEqual(v["nativeResolution"], "Not available")
        XCTAssertEqual(v["size"], "1920 × 1080 pt")
        XCTAssertEqual(v["edr"], "Not available")
        XCTAssertEqual(v["pixelAspect"], "Not available")
        XCTAssertEqual(v["drawable"], "Not available")
        var mixed = full
        mixed.potentialEDRHeadroom = 2
        mixed.currentEDRHeadroom = nil
        mixed.gamut = .sRGB
        mixed.mirrored = true
        mixed.overscan = .insetBounds
        mixed.scale = 1.5
        let m = values(.make(mixed))
        XCTAssertEqual(m["edr"], "2.0× potential, Not available current")
        XCTAssertEqual(m["gamut"], "sRGB")
        XCTAssertEqual(m["mirroring"], "Mirrored")
        XCTAssertEqual(m["overscan"], "Inset bounds")
        XCTAssertEqual(m["size"], "1920 × 1080 pt @1.5x")
    }

    func testDisconnectedCarriesNoValues() {
        let d = OutputDiagnostics.disconnected
        XCTAssertFalse(d.isConnected)
        XCTAssertEqual(d.rows, [OutputDiagnosticsRow(id: "status", title: "Status", value: "No external display connected")])
        XCTAssertEqual(d.text, "Status: No external display connected")
        XCTAssertEqual(d.summary, "disconnected")
    }

    func testDecimalIsLocaleIndependent() {
        XCTAssertEqual(OutputDiagnostics.decimal(1.333, places: 2, trim: false), "1.33")
        XCTAssertEqual(OutputDiagnostics.decimal(2, places: 2, trim: true), "2")
        XCTAssertEqual(OutputDiagnostics.decimal(0.9, places: 2, trim: false), "0.90")
        XCTAssertEqual(OutputDiagnostics.decimal(1919.96, places: 1, trim: true), "1920")
    }
}
