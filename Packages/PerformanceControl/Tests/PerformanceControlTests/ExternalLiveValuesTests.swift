// OSC-003-T08: MIDI and OSC live values share one path; the newest change wins per parameter (research OSC-003-D3).
import ParameterGraph
@testable import PerformanceControl
import XCTest

final class ExternalLiveValuesTests: XCTestCase {
    private let a: ParameterID = "effect.bloom.intensity"
    private let b: ParameterID = "effect.bloom.radius"

    func testNewestChangeWinsAndTheOtherSourceTakesOverWhenOneStops() {
        var live = ExternalLiveValues()
        live.update(.midi, [a: 0.2, b: 0.01])
        XCTAssertEqual(live.merged, [a: 0.2, b: 0.01])
        live.update(.osc, [a: 0.8])
        XCTAssertEqual(live.merged, [a: 0.8, b: 0.01], "OSC changed the intensity last")
        live.update(.midi, [a: 0.2, b: 0.02])
        XCTAssertEqual(live.merged, [a: 0.8, b: 0.02], "MIDI's unchanged intensity does not take it back")
        live.update(.midi, [a: 0.3, b: 0.02])
        XCTAssertEqual(live.merged[a], 0.3, "a new MIDI value does")
        live.update(.midi, [:])
        XCTAssertEqual(live.merged, [a: 0.8], "MIDI stopped: OSC's value is used")
        live.update(.osc, [:])
        XCTAssertEqual(live.merged, [:])
        XCTAssertEqual(live, ExternalLiveValues(), "nothing is kept")
    }
}
