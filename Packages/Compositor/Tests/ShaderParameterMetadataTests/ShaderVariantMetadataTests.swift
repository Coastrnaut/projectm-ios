// SHD-004-T03 (US1; SHD-004-R1, S1): a document's optional `variants` list is read and validated; each class
// of mistake has its own error naming the variant and the key. CPU only; runs on Linux.
import ShaderParameterMetadata
import XCTest

final class ShaderVariantMetadataTests: XCTestCase {
    private func document(variants: String?) -> String {
        let list: String = variants.map { (v: String) -> String in ", \"variants\": " + v } ?? ""
        return """
        {"schema": 1, "variant": "sample", "name": "Sample", "summary": "One parameter."\(list),
         "parameters": [{"id": "speed", "label": "Speed", "kind": "float", "slot": 0, "min": 0, "max": 1, "step": 0.01, "default": 0.25}]}
        """
    }

    private func validate(_ variants: String?) throws(ShaderMetadataError) -> ValidatedShaderMetadata {
        try ShaderMetadataReader.validate(json: document(variants: variants), document: "test.sample")
    }

    private func assertRejected(_ variants: String, _ expected: ShaderMetadataError, mentions: [String],
                                file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try validate(variants)
            XCTFail("accepted; expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
            for text in mentions { XCTAssertTrue(error.description.contains(text), "\(error.description) names \(text)", file: file, line: line) }
        }
    }

    func testWithoutAListThereIsOneStandardVariant() throws {
        let m: ValidatedShaderMetadata = try validate(nil)
        XCTAssertEqual(m.variants, [ShaderVariantSpec(id: "sample", label: "Standard")])
        XCTAssertEqual(m.defaultVariant.id, "sample")
    }

    func testAValidListIsReadInOrder() throws {
        let m: ValidatedShaderMetadata = try validate("""
        [{"id": "sample", "label": "Standard"}, {"id": "sampleDetailed", "label": "Detailed", "requires": "apple9"},
         {"id": "sampleLite", "label": "Low cost"}]
        """)
        XCTAssertEqual(m.variants.map(\.id), ["sample", "sampleDetailed", "sampleLite"])
        XCTAssertEqual(m.variantSpec("sampleDetailed")?.requires, .apple9)
        XCTAssertNil(m.variantSpec("sampleLite")?.requires)
        XCTAssertNil(m.variantSpec("other"))
        XCTAssertEqual(ShaderGPUFamily.apple9.displayName, "Apple GPU family 9")
    }

    func testEachClassOfMistakeHasItsOwnError() {
        let d = "test.sample"
        assertRejected(#"[{"id": "sample", "label": "Standard"}]"#, .variantCount(document: d, count: 1), mentions: ["variants"])
        assertRejected(#"[{"id": "sample", "label": "A"}, {"id": "sample", "label": "B"}]"#,
                       .duplicateVariantID(document: d, variantID: "sample"), mentions: ["sample"])
        assertRejected(#"[{"id": "sampleLite", "label": "A"}, {"id": "sample", "label": "B"}]"#,
                       .defaultVariantMismatch(document: d, variantID: "sampleLite", expected: "sample"), mentions: ["variants[0]"])
        assertRejected(#"[{"id": "sample", "label": "A"}, {"id": "other", "label": "B"}]"#,
                       .variantPrefix(document: d, path: "variants[1]", variantID: "other", prefix: "sample"), mentions: ["variants[1]", "id"])
        assertRejected(#"[{"id": "sample", "label": "A"}, {"id": "sampleX", "label": "B", "requires": "metal3"}]"#,
                       .unknownGPUFamily(document: d, path: "variants[1]", family: "metal3"), mentions: ["requires", "metal3"])
        assertRejected(#"[{"id": "sample", "label": "A", "requires": "apple8"}, {"id": "sampleX", "label": "B"}]"#,
                       .defaultVariantRequirement(document: d, variantID: "sample"), mentions: ["requires"])
        assertRejected(#"[{"id": "sample", "label": "A"}, {"id": "sampleX", "label": "B", "shader": "x"}]"#,
                       .unknownKey(document: d, path: "variants[1]", key: "shader"), mentions: ["shader"])
        assertRejected(#"[{"id": "sample", "label": "A"}, {"id": "sampleX", "label": ""}]"#,
                       .invalidLabel(document: d, path: "variants[1]", key: "label"), mentions: ["label"])
        assertRejected(#"[{"id": "sample", "label": "A"}, {"id": "sample-x", "label": "B"}]"#,
                       .invalidID(document: d, path: "variants[1]", key: "id", value: "sample-x"), mentions: ["id"])
    }
}
