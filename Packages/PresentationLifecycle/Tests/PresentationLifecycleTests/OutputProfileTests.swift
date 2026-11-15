// OutputProfileTests.swift — OUT-014-T03 (contract C1): the profile document's round trip, version checks, strict
// all-or-nothing validation and the display-class match. A few representative cases per rule (owner rule 7).
import Foundation
import PresentationLifecycle
import XCTest

final class OutputProfileTests: XCTestCase {
    private func pin() throws -> CornerPin {
        try XCTUnwrap(CornerPin(topLeft: CornerPinPoint(x: 0.08, y: 0.04), topRight: CornerPinPoint(x: 0.95, y: 0),
                                bottomRight: CornerPinPoint(x: 1, y: 0.97), bottomLeft: CornerPinPoint(x: 0.0123456789, y: 0.9)))
    }

    private let display = OutputDisplayClass(nativeWidth: 1920, nativeHeight: 1080, pixelAspect: 1, refreshRate: 60, gamut: .sRGB)

    private func custom() throws -> OutputProfile {
        OutputProfile(fit: .fill, shape: .device, pixelAspect: .narrow,
                      resolution: ExternalOutputResolution(mode: .custom, percent: 65), outputMode: .clean,
                      cornerPin: try pin(), calibration: OutputProfile.Calibration(gamma: 1.37, red: 0.8, green: 1.0000001, blue: 1.2),
                      display: display)
    }

    /// The JSON of a valid document, as a mutable dictionary.
    private func json(_ profile: OutputProfile) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: OutputProfileDocument.encode(profile)) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func refusal(_ data: Data) -> OutputProfileImportError? {
        do {
            _ = try OutputProfileDocument.decode(data)
            return nil
        } catch {
            return error
        }
    }

    private func edited(_ edit: (inout [String: Any], inout [String: Any]) -> Void) throws -> Data {
        var top: [String: Any] = try json(try custom())
        var settings = try XCTUnwrap(top["settings"] as? [String: Any])
        edit(&top, &settings)
        top["settings"] = settings
        return try data(top)
    }

    // MARK: - Round trip (OUT-014-R10, S1)

    func testRoundTripReproducesEveryValueExactly() throws {
        let original: OutputProfile = try custom()
        let decoded: OutputProfile = try OutputProfileDocument.decode(OutputProfileDocument.encode(original))
        XCTAssertEqual(decoded, original)
        for (a, b) in zip(decoded.cornerPin.corners, original.cornerPin.corners) {
            XCTAssertEqual(a.x.bitPattern, b.x.bitPattern)
            XCTAssertEqual(a.y.bitPattern, b.y.bitPattern)
        }
        XCTAssertEqual(decoded.calibration.green.bitPattern, original.calibration.green.bitPattern)
        XCTAssertEqual(decoded.calibration.gamma.bitPattern, original.calibration.gamma.bitPattern)

        let plain = OutputProfile()   // defaults, no display
        XCTAssertEqual(try OutputProfileDocument.decode(OutputProfileDocument.encode(plain)), plain)
        XCTAssertNil(try json(plain)["display"], "no display: no description")
    }

    func testTheDocumentHoldsOnlyTheKnownFields() throws {
        let top: [String: Any] = try json(try custom())
        XCTAssertEqual(Set(top.keys), ["format", "version", "settings", "display"])
        XCTAssertEqual(top["format"] as? String, "org.projectmios.output-profile")
        XCTAssertEqual(top["version"] as? Int, 1)
        let settings = try XCTUnwrap(top["settings"] as? [String: Any])
        XCTAssertEqual(Set(settings.keys), ["fit", "shape", "pixelAspect", "resolution", "resolutionPercent", "outputMode",
                                            "cornerPin", "calibration"])
        let text = String(decoding: OutputProfileDocument.encode(try custom()), as: UTF8.self)
        XCTAssertTrue(text.contains("\"resolution\" : \"custom\""), text)
        XCTAssertLessThan(text.utf8.count, 2_048)
    }

    // MARK: - Version

    func testVersionIsChecked() throws {
        XCTAssertEqual(refusal(try edited { (top: inout [String: Any], _: inout [String: Any]) in top["version"] = 2 }), .newerVersion(2))
        XCTAssertEqual(refusal(try edited { (top: inout [String: Any], _: inout [String: Any]) in top["version"] = 0 }), .notAProfile)
        XCTAssertEqual(refusal(try edited { (top: inout [String: Any], _: inout [String: Any]) in top["version"] = "1" }), .notAProfile)
        XCTAssertEqual(refusal(try edited { (top: inout [String: Any], _: inout [String: Any]) in top["format"] = "org.projectmios.midi-profile" }),
                       .notAProfile)
    }

    // MARK: - Invalid files are refused (OUT-014-R5, R6, S2)

    func testInvalidFilesAreRefused() throws {
        // A bow tie: top-right and bottom-right swapped (self-intersecting).
        let bowTie: [[String: Double]] = [["x": 0, "y": 0], ["x": 1, "y": 1], ["x": 1, "y": 0], ["x": 0, "y": 1]]
        XCTAssertEqual(refusal(try edited { (_: inout [String: Any], s: inout [String: Any]) in s["cornerPin"] = bowTie }),
                       .invalidValue("settings.cornerPin"))
        XCTAssertEqual(refusal(try edited { (_: inout [String: Any], s: inout [String: Any]) in
            s["calibration"] = ["gamma": 3.0, "red": 1, "green": 1, "blue": 1]
        }), .invalidValue("settings.calibration.gamma"), "out of range is refused, not clamped")
        XCTAssertEqual(refusal(try edited { (_: inout [String: Any], s: inout [String: Any]) in
            s["calibration"] = ["gamma": 1.0, "red": 1, "green": 0.2, "blue": 1]
        }), .invalidValue("settings.calibration.green"))
        XCTAssertEqual(refusal(try edited { (_: inout [String: Any], s: inout [String: Any]) in s["resolutionPercent"] = 120 }),
                       .invalidValue("settings.resolutionPercent"))
        XCTAssertEqual(refusal(try edited { (_: inout [String: Any], s: inout [String: Any]) in s["resolutionPercent"] = 62.5 }),
                       .invalidValue("settings.resolutionPercent"))
        XCTAssertEqual(refusal(try edited { (_: inout [String: Any], s: inout [String: Any]) in s["fit"] = "zoom" }),
                       .invalidValue("settings.fit"))
        XCTAssertEqual(refusal(try edited { (_: inout [String: Any], s: inout [String: Any]) in s["deviceName"] = "x" }),
                       .unknownField("settings.deviceName"))
        XCTAssertEqual(refusal(try edited { (top: inout [String: Any], _: inout [String: Any]) in top["extra"] = 1 }),
                       .unknownField("extra"))
        XCTAssertEqual(refusal(try edited { (_: inout [String: Any], s: inout [String: Any]) in s["outputMode"] = nil }),
                       .missingField("settings.outputMode"))
        XCTAssertEqual(refusal(try edited { (top: inout [String: Any], _: inout [String: Any]) in
            top["display"] = ["nativeWidth": 1920, "nativeHeight": 1080, "pixelAspect": 9.0]
        }), .invalidValue("display"))

        let whole: Data = OutputProfileDocument.encode(try custom())
        XCTAssertEqual(refusal(whole.prefix(whole.count / 2)), .notAProfile, "truncated")
        XCTAssertEqual(refusal(Data()), .empty)
        var big = Data("{\"format\":\"org.projectmios.output-profile\",\"pad\":\"".utf8)
        big.append(Data(repeating: 0x61, count: OutputProfileDocument.maxBytes))
        big.append(Data("\"}".utf8))
        XCTAssertEqual(refusal(big), .tooLarge)
        XCTAssertEqual(refusal(Data([0x89, 0x50, 0x4E, 0x47])), .notAProfile)
        XCTAssertFalse(OutputProfileImportError.invalidValue("settings.cornerPin").message.isEmpty)
    }

    // MARK: - Display class (OUT-014-R8, R9)

    func testDisplayClassMatching() {
        let same = OutputDisplayClass(nativeWidth: 1920, nativeHeight: 1080, pixelAspect: 1.002, refreshRate: 50, gamut: .sRGB)
        XCTAssertEqual(OutputDisplayClass.match(profile: display, connected: same), .same, "refresh is not compared")
        let small = OutputDisplayClass(nativeWidth: 1280, nativeHeight: 720, pixelAspect: 1, refreshRate: 60, gamut: .displayP3)
        XCTAssertEqual(OutputDisplayClass.match(profile: display, connected: small), .different([.resolution, .gamut]))
        let wide = OutputDisplayClass(nativeWidth: 1920, nativeHeight: 1080, pixelAspect: 1.2, refreshRate: 60, gamut: nil)
        XCTAssertEqual(OutputDisplayClass.match(profile: display, connected: wide), .different([.pixelAspect]), "unknown gamut not compared")
        XCTAssertEqual(OutputDisplayClass.match(profile: nil, connected: display), .unknown)
        XCTAssertEqual(OutputDisplayClass.match(profile: display, connected: nil), .unknown)
        XCTAssertEqual(display.summary, "1920 × 1080 px, pixel aspect 1.00, 60 Hz, sRGB")
    }

    func testDisplayClassFromReadings() {
        let readings = OutputReadings(nativeWidth: 1920, nativeHeight: 1080, maximumFramesPerSecond: 60, gamut: .displayP3,
                                      pixelAspect: 1.2)
        let made = OutputDisplayClass(readings: readings, screenPixelAspect: nil)
        XCTAssertEqual(made, OutputDisplayClass(nativeWidth: 1920, nativeHeight: 1080, pixelAspect: 1, refreshRate: 60, gamut: .displayP3),
                       "the screen's own pixel aspect, never the user's override")
        XCTAssertNil(OutputDisplayClass(readings: OutputReadings(), screenPixelAspect: 1))
    }
}
