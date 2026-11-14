// UIX-011-T03 (contract P4): a user palette as drawn — gradient interpolation in linear light, equal bands for
// swatches, recomputed layout colours when the palette changes. CPU only.
@testable import VisualGenerators
import XCTest

final class CustomPaletteTests: XCTestCase {
    private let red = LinearColor(red: 1, green: 0, blue: 0)
    private let blue = LinearColor(red: 0, green: 0, blue: 1)

    func testGradientInterpolatesTheStops() {
        let palette = VisualPalette.custom(PaletteRamp(stops: [red, blue], blended: true))
        XCTAssertEqual(palette.color(bar: 0, of: 5), red)
        XCTAssertEqual(palette.color(bar: 4, of: 5), blue)
        let middle = palette.color(bar: 2, of: 5)
        XCTAssertEqual(middle.red, 0.5, accuracy: 1e-6)
        XCTAssertEqual(middle.blue, 0.5, accuracy: 1e-6)
    }

    func testSwatchesAreEqualBands() {
        let palette = VisualPalette.custom(PaletteRamp(stops: [red, blue], blended: false))
        let colors: [LinearColor] = (0..<6).map { (k: Int) -> LinearColor in palette.color(bar: k, of: 6) }
        XCTAssertEqual(colors, [red, red, red, blue, blue, blue])
        XCTAssertEqual(VisualPalette.custom(PaletteRamp(stops: [], blended: true)).color(bar: 0, of: 3).green, 1, "never empty")
    }

    func testBuiltInsAreUnchangedAndCustomPalettesCompareByContent() {
        XCTAssertEqual(VisualPalette.allCases, [.spectrum, .ice, .mono, .colorBlindSafe])
        let a = VisualPalette.custom(PaletteRamp(stops: [red, blue], blended: true))
        XCTAssertEqual(a, .custom(PaletteRamp(stops: [red, blue], blended: true)))
        XCTAssertNotEqual(a, .custom(PaletteRamp(stops: [red, red], blended: true)), "an edit is a new palette value")
    }

    func testTheCircularLayoutRedrawsWithAnEditedPalette() {
        var configuration = CircularSpectrumConfiguration()
        configuration.palette = .custom(PaletteRamp(stops: [red, red], blended: true))
        let layout = CircularSpectrumLayout(configuration: configuration)
        let bands: [Float] = Array(repeating: 0.5, count: layout.barCount)
        layout.layout(bands, width: 100, height: 100)
        XCTAssertEqual(layout.bar(0).color, red)
        layout.configuration.palette = .custom(PaletteRamp(stops: [blue, blue], blended: true))
        layout.layout(bands, width: 100, height: 100)
        XCTAssertEqual(layout.bar(0).color, blue, "an edited palette is drawn from the next layout")
    }
}
