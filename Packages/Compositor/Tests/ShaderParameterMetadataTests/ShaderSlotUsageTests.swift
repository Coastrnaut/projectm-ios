// SHD-003-T07 (US1; SHD-003-R4, S2): the slot scanner finds how a fragment function reads its slots, and the
// check refuses undeclared reads and kind mismatches. CPU only; runs on Linux.
import ShaderParameterMetadata
import XCTest

final class ShaderSlotUsageTests: XCTestCase {
    private let source = """
    static float helper(constant U &u) { return u.slots[7].x; }
    fragment float4 sample_fn(MatOut in [[stage_in]], constant U &u [[buffer(0)]]) {
        float a = u.slots[0].x * 2.0;
        if (u.slots[2].x > 0.5) { a += 1.0; }
        float3 c = u.slots[4].rgb * a + mu.slots[6].x;
        float4 w = u.slots[3];
        return float4(c, u.slots[1].x);
    }
    fragment float4 other(MatOut in [[stage_in]]) { return float4(0.0); }
    """

    func testScanFindsReadsAndSwizzles() throws {
        let usage = try XCTUnwrap(ShaderSlotUsage.scan(source: source, function: "sample_fn"))
        XCTAssertEqual(usage.reads.keys.sorted(), [0, 1, 2, 3, 4], "helper's slot 7 and mu.slots[6] are not this function's reads")
        XCTAssertEqual(usage.reads[0], ShaderSlotUsage.Read(component: true, vector: false))
        XCTAssertEqual(usage.reads[4], ShaderSlotUsage.Read(component: false, vector: true))
        XCTAssertEqual(usage.reads[3], ShaderSlotUsage.Read(component: false, vector: true), "a whole float4 is a vector read")
        XCTAssertEqual(ShaderSlotUsage.scan(source: source, function: "other")?.reads, [:])
        XCTAssertNil(ShaderSlotUsage.scan(source: source, function: "missing_fn"))
    }

    private func metadata(_ kinds: [String]) throws -> ValidatedShaderMetadata {
        let items: [String] = kinds.enumerated().map { (entry: (offset: Int, element: String)) -> String in
            let i = entry.offset
            switch entry.element {
            case "color": return "{\"id\": \"p\(i)\", \"label\": \"P\", \"kind\": \"color\", \"slot\": \(i), \"default\": [0, 0, 0, 1]}"
            case "bool": return "{\"id\": \"p\(i)\", \"label\": \"P\", \"kind\": \"bool\", \"slot\": \(i), \"default\": false}"
            default: return "{\"id\": \"p\(i)\", \"label\": \"P\", \"kind\": \"float\", \"slot\": \(i), \"min\": 0, \"max\": 1, \"step\": 0.1, \"default\": 0}"
            }
        }
        let json = "{\"schema\": 1, \"variant\": \"v\", \"name\": \"V\", \"summary\": \"S\", \"parameters\": [\(items.joined(separator: ","))]}"
        return try ShaderMetadataReader.validate(json: json, document: "test.v")
    }

    func testCheckAcceptsMatchingMetadataAndUnreadSlots() throws {
        // Slot 5 is declared but never read (a CPU-side parameter): allowed.
        let m = try metadata(["float", "float", "bool", "color", "color", "float"])
        XCTAssertNoThrow(try m.check(source: source, function: "sample_fn"))
    }

    func testCheckRefusesMismatches() throws {
        let colorAsNumber = try metadata(["float", "float", "bool", "color", "float"])
        XCTAssertThrowsError(try colorAsNumber.check(source: source, function: "sample_fn")) { (error: Error) in
            XCTAssertEqual(error as? ShaderMetadataError,
                           .slotTypeMismatch(document: "test.v", parameterID: "p4", slot: 4, kind: "float", read: "a vector"))
            XCTAssertTrue("\(error)".contains("p4") && "\(error)".contains("slot"))
        }
        let numberAsColor = try metadata(["color", "float", "bool", "color", "color"])
        XCTAssertThrowsError(try numberAsColor.check(source: source, function: "sample_fn")) { (error: Error) in
            XCTAssertEqual(error as? ShaderMetadataError,
                           .slotTypeMismatch(document: "test.v", parameterID: "p0", slot: 0, kind: "color", read: "one component"))
        }
        let tooFew = try metadata(["float", "float", "bool"])
        XCTAssertThrowsError(try tooFew.check(source: source, function: "sample_fn")) { (error: Error) in
            XCTAssertEqual(error as? ShaderMetadataError, .undeclaredSlotRead(document: "test.v", function: "sample_fn", slot: 3))
        }
        XCTAssertThrowsError(try tooFew.check(source: source, function: "nope")) { (error: Error) in
            XCTAssertEqual(error as? ShaderMetadataError, .missingFunction(document: "test.v", function: "nope"))
        }
    }
}
