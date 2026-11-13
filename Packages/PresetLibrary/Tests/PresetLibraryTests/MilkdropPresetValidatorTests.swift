// PRE-012-T04: static validation of an imported preset (PRE-012-R7-R13, S1, S7). Every limit is
// tested at N (accepted) and N+1 (quarantined with exactly that reason).
import XCTest
@testable import PresetLibrary

final class MilkdropPresetValidatorTests: XCTestCase {
    private typealias F = UserPresetFixtures
    private typealias L = PresetImportLimits

    private func validate(_ text: String, textures: Set<String> = []) -> PresetValidation {
        MilkdropPresetValidator.validate(Array(text.utf8), knownTextures: textures)
    }

    private func assertRejected(_ text: String, _ kind: PresetQuarantineReason.Kind, file: StaticString = #filePath, line: UInt = #line) {
        let result = validate(text)
        XCTAssertEqual(result.rejection?.kind, kind, "got \(String(describing: result.rejection))", file: file, line: line)
    }

    private func assertAccepted(_ text: String, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(validate(text).rejection, message, file: file, line: line)
    }

    private func warningDetails(_ result: PresetValidation, _ kind: PresetImportWarning.Kind) -> [String] {
        result.warnings.filter { $0.kind == kind }.map(\.detail)
    }

    // MARK: - Accepted

    func testTheValidFixtureIsAcceptedWithoutWarnings() {
        let result = validate(F.valid)
        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.licenseLines, [])
    }

    func testLineEndingsByteOrderMarkAndLatin1AreAccepted() {
        assertAccepted(F.preset(newline: "\r\n"))
        assertAccepted(F.preset(newline: "\r"))
        XCTAssertNil(MilkdropPresetValidator.validate([0xEF, 0xBB, 0xBF] + F.validBytes, knownTextures: []).rejection)
        var latin1 = F.validBytes
        latin1 += Array("per_frame_3=q1 = 1; // caf".utf8) + [0xE9, 0x0A]   // "café" in Latin-1
        let result = MilkdropPresetValidator.validate(latin1, knownTextures: [])
        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.warnings.map(\.kind), [.notUTF8])
        XCTAssertNil(MilkdropPresetValidator.validate(F.validBytes + [0x09, 0x0A], knownTextures: []).rejection, "a tab is text")
    }

    // MARK: - Text checks (R8)

    func testBinaryContentIsQuarantined() {
        var bytes = F.validBytes
        bytes.insert(0, at: 40)
        XCTAssertEqual(MilkdropPresetValidator.validate(bytes, knownTextures: []).rejection?.kind, .binaryContent)
        bytes = F.validBytes
        bytes.insert(1, at: 40)
        XCTAssertEqual(MilkdropPresetValidator.validate(bytes, knownTextures: []).rejection?.kind, .binaryContent)
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01]
        XCTAssertEqual(MilkdropPresetValidator.validate(jpeg, knownTextures: []).rejection?.kind, .binaryContent)
        XCTAssertEqual(MilkdropPresetValidator.validate([], knownTextures: []).rejection?.kind, .missingHeader, "empty input never traps")
    }

    func testLineLength() {
        func comment(_ total: Int) -> String { "//" + String(repeating: "x", count: total - 2) }
        assertAccepted(F.preset(extra: [comment(L.maxLineBytes)]))
        assertRejected(F.preset(extra: [comment(L.maxLineBytes + 1)]), .lineTooLong)
        assertRejected(F.preset(extra: [comment(1_000_000)]), .lineTooLong)
        XCTAssertTrue(validate(F.preset(extra: [comment(L.maxLineBytes + 1)])).rejection?.message.contains("8,192") ?? false)
    }

    func testLineCount() {
        let filler = [String](repeating: "// filler", count: L.maxLines - 20)
        let base = F.preset(extra: filler)
        let count = base.split(separator: "\n", omittingEmptySubsequences: false).count - 1
        let padded = F.preset(extra: filler + [String](repeating: "// filler", count: L.maxLines - count))
        assertAccepted(padded)
        assertRejected(F.preset(extra: filler + [String](repeating: "// filler", count: L.maxLines - count + 1)), .tooManyLines)
    }

    // MARK: - Structure (R9)

    func testHeader() {
        assertRejected(F.preset(header: ""), .missingHeader)
        assertRejected(F.preset(header: "[preset01]"), .missingHeader)
        assertRejected("fRating=3\n[preset00]\nzoom=1\n", .missingHeader)
        assertAccepted("  [Preset00]  \nzoom=1\n")
        assertRejected("[preset00]\n", .noSettings)
        assertRejected("MILKDROP_PRESET_VERSION=201\n[preset00]\n// nothing\n", .noSettings)
    }

    // MARK: - Code blocks (R10)

    func testBlockSize() {
        // 7,987-byte lines of short statements; 17 lines are 135,796 bytes in one block.
        let line = String(repeating: "q1 = q1 + 1; ", count: 614) + "q2=1;"
        assertRejected(F.preset(perFrame: [String](repeating: line, count: 17)), .blockTooLarge)
        assertAccepted(F.preset(perFrame: [String](repeating: line, count: 16)))
    }

    func testStatementLength() {
        func statement(_ bytes: Int) -> String { "q1=" + String(repeating: "1", count: bytes - 3) }
        // The statement is what stands between two semicolons, comments removed.
        // White space (here the line break) is not counted.
        assertAccepted(F.preset(perFrame: [statement(4_000), statement(L.maxStatementBytes - 4_000) + ";"]))
        assertRejected(F.preset(perFrame: [statement(4_000), statement(L.maxStatementBytes - 4_000 + 1) + ";"]), .statementTooLong)
        assertAccepted(F.preset(perFrame: [statement(4_000) + " // " + String(repeating: "c", count: 4_000),
                                           statement(4_000) + ";"]))
        let shaderLine = "ret = " + String(repeating: "1", count: 4_200)
        assertRejected(F.preset(comp: ["shader_body", "{", shaderLine, shaderLine + ";", "}"]), .statementTooLong)
    }

    func testNestingDepth() {
        func nested(_ depth: Int) -> String {
            "q1 = " + String(repeating: "(", count: depth) + "1" + String(repeating: ")", count: depth) + ";"
        }
        assertAccepted(F.preset(perFrame: [nested(L.maxNestingDepth)]))
        assertRejected(F.preset(perFrame: [nested(L.maxNestingDepth + 1)]), .nestingTooDeep)
        // 50,000 nested parentheses spread over lines that are each within the line limit.
        let open = [String](repeating: String(repeating: "(", count: 5_000), count: 10)
        let close = [String](repeating: String(repeating: ")", count: 5_000), count: 10)
        assertRejected(F.preset(perFrame: ["q1 ="] + open + ["1"] + close + [";"]), .nestingTooDeep)
        let mixed = "ret = " + String(repeating: "float3(", count: 33) + String(repeating: "[", count: 32)
        assertRejected(F.preset(comp: ["shader_body", "{", mixed, "}"]), .nestingTooDeep)
    }

    /// Complexity: punctuation that can add a level to an expression tree (operators, opening
    /// brackets, member access). Shaders: 256 including preprocessor lines; equations: 512.
    func testStatementComplexity() {
        func shader(_ statement: String, defines: [String] = []) -> String {
            F.preset(comp: defines + ["shader_body", "{", "ret = tex2D(sampler_main, uv).xyz;", statement, "}"])
        }
        // "ret = " is 1, each "(float3)" is 1.
        let casts = L.maxShaderStatementComplexity - 1
        assertAccepted(shader("ret = " + String(repeating: "(float3)", count: casts) + "ret;"))
        assertRejected(shader("ret = " + String(repeating: "(float3)", count: casts + 1) + "ret;"), .statementTooComplex)
        assertRejected(shader("ret = " + String(repeating: "-+", count: 128) + "ret;"), .statementTooComplex)
        assertRejected(shader("ret = ret" + String(repeating: ".xyz", count: 256) + ";"), .statementTooComplex)
        assertAccepted(shader("ret = ret*0.5" + String(repeating: " + 0.25", count: 254) + ";"), "numbers' dots do not count")
        // A macro's body can end up inside any statement, so preprocessor lines add to every statement.
        let define = "#define BIG (" + String(repeating: "ret+", count: 200) + "ret)"      // 1 + 1 + 200 = 202
        assertAccepted(shader("ret = BIG" + String(repeating: "+BIG", count: 52) + ";", defines: [define]))     // 202 + 1 + 52 = 255... plus "#"
        assertRejected(shader("ret = BIG" + String(repeating: "+BIG", count: 54) + ";", defines: [define]), .statementTooComplex)
        assertRejected(shader("ret = ret;", defines: [define, define]), .statementTooComplex)
        // Many simple statements are fine: the limit is per statement.
        assertAccepted(shader([String](repeating: "ret = ret*0.99+0.001;", count: 300).joined(separator: " ")))

        let terms = L.maxEquationStatementComplexity - 1
        assertAccepted(F.preset(perFrame: ["q1 = " + String(repeating: "q2+", count: terms) + "q2;"]))
        assertRejected(F.preset(perFrame: ["q1 = " + String(repeating: "q2+", count: terms + 1) + "q2;"]), .statementTooComplex)
        assertRejected(F.preset(extra: ["shape_1_per_frame1=x = " + String(repeating: "-!", count: 256) + "x;"]), .statementTooComplex)
        XCTAssertTrue(validate(shader("ret = " + String(repeating: "(float3)", count: 300) + "ret;")).rejection?.message.contains("256") ?? false)
    }

    func testShaderControlFlow() {
        func shader(_ lines: [String]) -> String {
            F.preset(comp: ["shader_body", "{", "ret = tex2D(sampler_main, uv).xyz;", "float t = uv.x;"] + lines + ["}"])
        }
        // "if" + 31 × "else if" = 63 keywords; one more "else" = 64.
        let chain = ["if(t>2) ret*=0.9;"] + [String](repeating: "else if(t>2) ret*=0.9;", count: 31)
        assertAccepted(shader(chain + ["else ret*=0.8;"]))
        assertRejected(shader(chain + ["else if(t>3) ret*=0.8;"]), .tooMuchControlFlow)
        assertRejected(shader([String(repeating: "if(t>-1) ", count: 65) + "ret*=0.99;"]), .tooMuchControlFlow)
        assertRejected(shader([String(repeating: "for(int i=0;i<1;i++) ", count: 65) + "ret*=0.99;"]), .tooMuchControlFlow)
        assertAccepted(shader(["float iffy = 1.0; float do_it = 2.0; float format = 3.0; // names that only contain keywords"]))
        // Equations have no such keywords: `if` is a function there, limited by bracket nesting.
        assertAccepted(F.preset(perFrame: [String](repeating: "q1 = if(above(q1,1), 0, q1+1);", count: 100)))
    }

    func testUnbalancedEquations() {
        assertRejected(F.preset(perFrame: ["q1 = sin(time;"]), .unbalancedEquation)
        assertRejected(F.preset(perPixel: ["zoom = zoom) + 1;"]), .unbalancedEquation)
        assertRejected(F.preset(extra: ["wave_0_per_point1=x = (sample;"]), .unbalancedEquation)
        assertAccepted(F.preset(perFrame: ["q1 = sin(time); // an unclosed ( in a comment"]))
    }

    func testIncompleteShaders() {
        assertRejected(F.preset(warp: ["shader_body", "{", "    ret = tex2D(sampler_main, uv).xyz;"]), .incompleteShader)   // cut off
        assertRejected(F.preset(comp: ["{", "    ret = tex2D(sampler_main, uv).xyz;", "}"]), .incompleteShader)          // no shader_body
        assertRejected(F.preset(comp: ["shader_body", "{", "    ret = tex2D(sampler_main, uv.xyz;", "}"]), .incompleteShader)
        assertAccepted(F.preset(comp: ["shader_body", "{", "    ret = tex2D(sampler_main, uv).xyz; // }", "}"]))
    }

    // MARK: - Warnings (R9-R11)

    func testTextureDependencies() {
        let comp = ["sampler sampler_mytexture;", "shader_body", "{",
                    "    ret = tex2D(sampler_main, uv).xyz + tex2D(sampler_fw_noise_lq, uv).xyz + tex2D(sampler_rand03, uv).xyz;",
                    "    ret += tex2D(sampler_blur2, uv).xyz + tex2D(sampler_MyTexture, uv).xyz + tex2D(sampler_pc_Worms, uv).xyz;",
                    "    ret += tex2D(sampler_rand07_smalltiled, uv).xyz + tex3D(sampler_noisevol_hq, uvw).xyz;", "}"]
        let result = validate(F.preset(comp: comp), textures: ["worms"])
        XCTAssertNil(result.rejection)
        XCTAssertEqual(warningDetails(result, .missingTexture), ["mytexture"])
        XCTAssertTrue(result.warnings.first?.message.contains("mytexture") ?? false)
        XCTAssertEqual(warningDetails(validate(F.preset(comp: comp)), .missingTexture), ["mytexture", "worms"])
        // A sampler named only in a comment is not a dependency.
        let commented = ["shader_body", "{", "    ret = tex2D(sampler_main, uv).xyz; // sampler_ghost", "}"]
        XCTAssertEqual(warningDetails(validate(F.preset(comp: commented)), .missingTexture), [])
    }

    func testNumberingGapIsAWarningAndLinesAfterItAreNotJudged() {
        let text = F.preset(perFrame: []) + "per_frame_1=q1 = 1;\nper_frame_3=q2 = sin(time;\n"
        let result = validate(text)
        XCTAssertNil(result.rejection, "the engine never reads per_frame_3")
        XCTAssertEqual(warningDetails(result, .numberingGap), ["per_frame_"])
    }

    func testRepeatedKeysAndIgnoredLines() {
        let result = validate(F.preset(extra: ["zoom=2.0", "zoom=3.0", "just some words", "another"]))
        XCTAssertNil(result.rejection)
        XCTAssertEqual(warningDetails(result, .repeatedKeys), ["2"])
        XCTAssertEqual(warningDetails(result, .ignoredLines), ["1"], "\"just some words\" is a setting named just; \"another\" is ignored")
    }

    func testWarningsAreCapped() {
        let comp = ["shader_body", "{"] + (0..<80).map { "    ret += tex2D(sampler_t\($0)x, uv).xyz;" } + ["}"]
        XCTAssertEqual(validate(F.preset(comp: comp)).warnings.count, L.maxWarnings)
    }

    // MARK: - License lines (R12)

    func testLicenseLinesAreKeptVerbatimAndNeverInvented() {
        let long = "// Copyright " + String(repeating: "y", count: 400)
        let lines = ["// License: CC-BY 4.0", "copyright 2004 Someone", "// © Someone Else", "// released to the public domain",
                     "// Creative Commons Zero", "// licence: none", long]
        let result = validate(F.preset(perFrame: ["q1 = (c)*2;", "q2 = cc0 + 1;"], extra: lines))
        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.licenseLines, ["// License: CC-BY 4.0", "copyright 2004 Someone", "// © Someone Else",
                                             "// released to the public domain", "// Creative Commons Zero"])
        let cut = validate(F.preset(extra: [long])).licenseLines
        XCTAssertEqual(cut.first?.count, L.maxLicenseLineCharacters)
        XCTAssertEqual(validate(F.preset(perFrame: ["q1 = (c)*2;"])).licenseLines, [])
    }

    // MARK: - Bounded on hostile shapes (R7)

    func testHostileShapesFinishQuickly() {
        let shapes: [[UInt8]] = [
            [UInt8](repeating: 0x28, count: L.maxFileBytes),                    // only "("
            [UInt8](repeating: 0x0A, count: L.maxFileBytes),                    // only line feeds
            [UInt8](repeating: 0x3D, count: L.maxFileBytes),                    // only "="
            Array(("[preset00]\n" + String(repeating: "per_frame_1=x;\n", count: 30_000)).utf8),
            Array(("[preset00]\n" + (1...19_000).map { "per_frame_\($0)=(" }.joined(separator: "\n")).utf8),
            Array(("[preset00]\n" + (1...19_000).map { "k\($0)=1" }.joined(separator: "\n")).utf8),
        ]
        for (index, bytes) in shapes.enumerated() {
            let start = Date()
            _ = MilkdropPresetValidator.validate(bytes, knownTextures: [])
            // A hang guard (see PresetMutationSweepTests): CI's Debug simulator is several times
            // slower than the Mac, so a 1 s limit would fail there without a defect.
            XCTAssertLessThan(Date().timeIntervalSince(start), 10.0, "shape \(index) looks hung")
        }
    }

    // MARK: - The built-in corpus (S7)

    /// Runs when the preset packs are checked out (the main checkout, or `PRE012_CORPUS`); a
    /// feature worktree has none.
    func testNoBuiltInPresetExceedsALimit() throws {
        let root = ProcessInfo.processInfo.environment["PRE012_CORPUS"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/presets")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("cream-of-the-crop/README.md").path),
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw XCTSkip("the preset packs are not checked out here")
        }
        let limitKinds: Set<PresetQuarantineReason.Kind> = [.binaryContent, .lineTooLong, .tooManyLines, .missingHeader, .noSettings,
                                                             .blockTooLarge, .statementTooLong, .nestingTooDeep,
                                                             .statementTooComplex, .tooMuchControlFlow]
        var files = 0
        var other: [PresetQuarantineReason.Kind: Int] = [:]
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "milk" {
            let bytes = [UInt8](try Data(contentsOf: url))
            files += 1
            XCTAssertLessThanOrEqual(bytes.count, L.maxFileBytes, url.lastPathComponent)
            guard let kind = MilkdropPresetValidator.validate(bytes, knownTextures: []).rejection?.kind else { continue }
            XCTAssertFalse(limitKinds.contains(kind), "\(url.lastPathComponent): \(kind)")
            other[kind, default: 0] += 1
        }
        XCTAssertGreaterThan(files, 12_000)
        print("PRE-012 corpus: \(files) files, rejected for other reasons: \(other)")
    }
}
