// MilkdropPresetValidator.swift — static checks on an imported preset, before any engine sees it
// (PRE-012-R7-R12; contracts/user-presets.md).
//
// The file is untrusted (Constitution IX). The validator works on bytes, in passes that are each
// linear in the input, with no recursion and no decoding of the whole file as a string. It reads
// the file the way the engine's own parser does (Vendor/projectM PresetFileParser.cpp), so it
// judges what the engine will read:
//   * a line's key ends at its first space or "="; a line without one, or starting with one, is
//     ignored; keys are case-insensitive; the first occurrence of a key wins;
//   * a code block is the lines `<prefix>1`, `<prefix>2`, … up to the first missing number; a
//     leading backtick is dropped from each line.
// Order of checks (the first that fails is the reason): binary content, line length, line count,
// header, settings; then per code block in prefix order: size, bracket nesting, statement length,
// statement complexity, control flow (shaders), balance (equations) or completeness (shaders).
//
// Why nesting, complexity and control flow are limited: the engine's shader translator
// (hlslparser), ANGLE's shader compiler and the equation compiler recurse on the depth of an
// expression or of nested statements, without a limit of their own. On the simulator a shader
// statement with a chain of 768 casts overflowed the stack inside hlslparser, and one with
// 2,048 additions overflowed it inside ANGLE (docs/test-reports/preset-import.md). Depth can only
// come from brackets, operators and control-flow keywords, so the validator bounds those:
//   * brackets nested at most `maxNestingDepth`;
//   * "complexity" of a statement = its punctuation bytes other than `)`, `]`, `}`, `;` (a `.` counts
//     only before a letter): an upper bound on the operators and brackets that can stack up. For
//     a shader the complexity of all its preprocessor lines is added, because a macro can put
//     its body inside any statement;
//   * at most `maxShaderControlKeywords` of if/else/for/while/do in one shader, because
//     `else if` chains and brace-less nesting stack up without any bracket.
import Foundation

public struct PresetValidation: Sendable, Equatable {
    /// Non-nil: the file must be quarantined for this reason.
    public var rejection: PresetQuarantineReason?
    public var warnings: [PresetImportWarning]
    /// Lines that mention a license or copyright, verbatim (R12).
    public var licenseLines: [String]
}

public enum MilkdropPresetValidator {
    /// Texture names the engine provides itself (TextureManager.cpp, MilkdropShader.cpp).
    static let engineTextures: Set<String> = ["main", "blur1", "blur2", "blur3", "noise_lq", "noise_lq_lite", "noise_mq",
                                              "noise_hq", "noisevol_lq", "noisevol_hq"]
    /// Lines before the header that are not settings of the preset.
    private static let versionKeys: Set<String> = ["milkdrop_preset_version", "psversion", "psversion_warp", "psversion_comp"]
    private static let fixedPrefixes: Set<String> = ["per_frame_init_", "per_frame_", "per_pixel_", "warp_", "comp_"]
    private static let shaderPrefixes: Set<String> = ["warp_", "comp_"]

    /// `knownTextures`: lowercase names (without extension) of the textures shipped with the app.
    public static func validate(_ bytes: [UInt8], knownTextures: Set<String>) -> PresetValidation {
        var warnings: [PresetImportWarning] = []
        func result(_ rejection: PresetQuarantineReason?, license: [String] = []) -> PresetValidation {
            PresetValidation(rejection: rejection, warnings: Array(warnings.prefix(PresetImportLimits.maxWarnings)),
                             licenseLines: license)
        }

        // A UTF-8 byte-order mark is not content.
        let start = bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0

        // 1. Binary content: NUL or any control byte other than tab, LF and CR.
        for index in start..<bytes.count {
            let byte = bytes[index]
            if (byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D) || byte == 0x7F {
                return result(PresetQuarantineReason(.binaryContent))
            }
        }

        // 2. and 3. Lines: CRLF, CR and LF each end one line.
        var lines: [Range<Int>] = []
        var lineStart = start
        var index = start
        var tooLong = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x0A || byte == 0x0D {
                if index - lineStart > PresetImportLimits.maxLineBytes { tooLong = true; break }
                if lines.count <= PresetImportLimits.maxLines { lines.append(lineStart..<index) }
                if byte == 0x0D && index + 1 < bytes.count && bytes[index + 1] == 0x0A { index += 1 }
                lineStart = index + 1
            }
            index += 1
        }
        if !tooLong && lineStart < bytes.count {
            if bytes.count - lineStart > PresetImportLimits.maxLineBytes { tooLong = true } else if lines.count <= PresetImportLimits.maxLines {
                lines.append(lineStart..<bytes.count)
            }
        }
        if tooLong { return result(PresetQuarantineReason(.lineTooLong)) }
        if lines.count > PresetImportLimits.maxLines { return result(PresetQuarantineReason(.tooManyLines)) }

        // 4. and 5. Header and settings, as the engine's parser reads them.
        var values: [String: Range<Int>] = [:]
        var headerSeen = false
        var settingBeforeHeader = false
        var settingCount = 0
        var repeated = 0
        var ignored = 0
        for line in lines {
            let trimmed = trim(bytes, line)
            if trimmed.isEmpty { continue }
            if bytes[trimmed.lowerBound] == 0x5B {   // "[": a section header
                if !headerSeen && equalsIgnoringCase(bytes, trimmed, "[preset00]") {
                    headerSeen = true
                } else if !headerSeen {
                    settingBeforeHeader = true   // another section comes first: not a preset file
                }
                continue
            }
            if trimmed.count >= 2 && bytes[trimmed.lowerBound] == 0x2F && bytes[trimmed.lowerBound + 1] == 0x2F { continue }   // comment
            guard let delimiter = (line.lowerBound..<line.upperBound).first(where: { bytes[$0] == 0x20 || bytes[$0] == 0x3D }),
                  delimiter > line.lowerBound else {
                ignored += 1
                continue
            }
            let key = lowercasedKey(bytes, line.lowerBound..<delimiter)
            if values[key] != nil {
                repeated += 1
                continue
            }
            values[key] = (delimiter + 1)..<line.upperBound
            if !versionKeys.contains(key) {
                settingCount += 1
                if !headerSeen { settingBeforeHeader = true }
            }
        }
        if !headerSeen || settingBeforeHeader { return result(PresetQuarantineReason(.missingHeader)) }
        if settingCount == 0 { return result(PresetQuarantineReason(.noSettings)) }

        if String(bytes: bytes[start...], encoding: .utf8) == nil { warnings.append(PresetImportWarning(.notUTF8)) }
        if repeated > 0 { warnings.append(PresetImportWarning(.repeatedKeys, detail: String(repeated))) }
        if ignored > 0 { warnings.append(PresetImportWarning(.ignoredLines, detail: String(ignored))) }

        // 6. Code blocks.
        var numbered: [String: [Int: Range<Int>]] = [:]
        for (key, value) in values {
            guard let (prefix, number) = blockKey(key) else { continue }
            numbered[prefix, default: [:]][number] = value
        }
        var missingTextures: Set<String> = []
        for prefix in numbered.keys.sorted() {
            guard let byNumber = numbered[prefix] else { continue }
            var code: [UInt8] = []
            var number = 1
            var tooLarge = false
            while let range = byNumber[number] {
                var from = range.lowerBound
                if from < range.upperBound && bytes[from] == 0x60 { from += 1 }   // backtick
                if code.count + (range.upperBound - from) + 1 > PresetImportLimits.maxBlockBytes { tooLarge = true; break }
                code.append(contentsOf: bytes[from..<range.upperBound])
                code.append(0x0A)
                number += 1
            }
            if tooLarge { return result(PresetQuarantineReason(.blockTooLarge, detail: prefix)) }
            if byNumber.count > number - 1 { warnings.append(PresetImportWarning(.numberingGap, detail: prefix)) }
            let isShader = shaderPrefixes.contains(prefix)
            blankComments(&code)
            if let reason = checkCode(code, prefix: prefix, isShader: isShader) { return result(reason) }
            if isShader { collectMissingTextures(code, known: knownTextures, into: &missingTextures) }
        }
        for name in missingTextures.sorted() { warnings.append(PresetImportWarning(.missingTexture, detail: name)) }

        return result(nil, license: licenseLines(bytes, lines))
    }

    // MARK: - Code checks

    /// Nesting, statement length, then balance or shader completeness. Iterative.
    private static func checkCode(_ code: [UInt8], prefix: String, isShader: Bool) -> PresetQuarantineReason? {
        var depth = 0
        var maxDepth = 0
        var round = 0
        var curly = 0
        var unbalanced = false
        var statement = 0
        var longest = 0
        var blank = true
        // Complexity: of the current statement, the largest seen, and of all preprocessor lines.
        var complexity = 0
        var mostComplex = 0
        var directives = 0
        var inDirective = false
        var lineHasContent = false
        var lastOnLine: UInt8 = 0
        var keywords = 0
        var word: [UInt8] = []
        for (index, byte) in code.enumerated() {
            // Lines: a shader line starting with "#" is a preprocessor line (a trailing "\" continues it).
            if byte == 0x0A {
                if !(inDirective && lastOnLine == 0x5C) { inDirective = false }
                lineHasContent = false
                lastOnLine = 0
            } else if byte != 0x20 && byte != 0x09 {
                if isShader && !lineHasContent && byte == 0x23 { inDirective = true }
                lineHasContent = true
                lastOnLine = byte
            }
            // Control-flow keywords.
            if isShader {
                if isIdentifier(byte) {
                    if word.count < 8 { word.append(byte) }
                } else {
                    if controlKeywords.contains(word) { keywords += 1 }
                    word.removeAll(keepingCapacity: true)
                }
            }
            // Punctuation that can add a level to an expression tree.
            if isComplexityByte(code, index) {
                if inDirective { directives += 1 } else { complexity += 1 }
            }
            switch byte {
            case 0x28, 0x5B, 0x7B:   // ( [ {
                depth += 1
                maxDepth = max(maxDepth, depth)
                if byte == 0x28 { round += 1 } else if byte == 0x7B { curly += 1 }
            case 0x29, 0x5D, 0x7D:   // ) ] }
                if depth > 0 { depth -= 1 }
                if byte == 0x29 { round -= 1; if round < 0 { unbalanced = true; round = 0 } }
                if byte == 0x7D { curly -= 1; if curly < 0 { unbalanced = true; curly = 0 } }
            default: break
            }
            if byte != 0x20 && byte != 0x09 && byte != 0x0A { blank = false }
            if byte == 0x3B || (isShader && (byte == 0x7B || byte == 0x7D)) {
                longest = max(longest, statement)
                statement = 0
                mostComplex = max(mostComplex, complexity)
                complexity = 0
            } else if byte != 0x20 && byte != 0x09 && byte != 0x0A {
                statement += 1   // white space and comments do not count
            }
        }
        longest = max(longest, statement)
        mostComplex = max(mostComplex, complexity)
        if controlKeywords.contains(word) { keywords += 1 }
        if maxDepth > PresetImportLimits.maxNestingDepth { return PresetQuarantineReason(.nestingTooDeep, detail: prefix) }
        if longest > PresetImportLimits.maxStatementBytes { return PresetQuarantineReason(.statementTooLong, detail: prefix) }
        let complexityLimit = isShader ? PresetImportLimits.maxShaderStatementComplexity : PresetImportLimits.maxEquationStatementComplexity
        if mostComplex + directives > complexityLimit { return PresetQuarantineReason(.statementTooComplex, detail: prefix) }
        if keywords > PresetImportLimits.maxShaderControlKeywords { return PresetQuarantineReason(.tooMuchControlFlow, detail: prefix) }
        if isShader {
            // A blank shader is "no shader" to the engine.
            if !blank && (unbalanced || round != 0 || curly != 0 || !contains(code, "shader_body")) {
                return PresetQuarantineReason(.incompleteShader, detail: prefix)
            }
        } else if unbalanced || round != 0 {
            return PresetQuarantineReason(.unbalancedEquation, detail: prefix)
        }
        return nil
    }

    private static let controlKeywords: Set<[UInt8]> = Set(["if", "else", "for", "while", "do"].map { Array($0.utf8) })

    /// Punctuation other than closing brackets; a "." only when a name follows (member access,
    /// not a number).
    private static func isComplexityByte(_ code: [UInt8], _ index: Int) -> Bool {
        let byte = code[index]
        if byte <= 0x20 || byte >= 0x7F || isIdentifier(byte) { return false }
        if byte == 0x29 || byte == 0x5D || byte == 0x7D || byte == 0x3B { return false }   // ) ] } ;
        if byte == 0x2E {
            guard index + 1 < code.count else { return false }
            let next = code[index + 1]
            return isIdentifier(next) && !isDigit(next)
        }
        return true
    }

    /// Replaces `// …` and `/* … */` comments with spaces, keeping line breaks.
    private static func blankComments(_ code: inout [UInt8]) {
        var index = 0
        let count = code.count
        while index + 1 < count {
            if code[index] == 0x2F && code[index + 1] == 0x2F {
                while index < count && code[index] != 0x0A { code[index] = 0x20; index += 1 }
            } else if code[index] == 0x2F && code[index + 1] == 0x2A {
                code[index] = 0x20; code[index + 1] = 0x20
                index += 2
                while index < count {
                    if index + 1 < count && code[index] == 0x2A && code[index + 1] == 0x2F {
                        code[index] = 0x20; code[index + 1] = 0x20
                        index += 2
                        break
                    }
                    if code[index] != 0x0A { code[index] = 0x20 }
                    index += 1
                }
            } else {
                index += 1
            }
        }
    }

    /// `sampler_<name>` uses that are neither the engine's own textures nor shipped with the app.
    /// Mirrors MilkdropShader.cpp: a two-letter prefix (`fw_`, `pc_`, …) is not part of the name,
    /// and `randNN…` picks a random texture.
    private static func collectMissingTextures(_ code: [UInt8], known: Set<String>, into missing: inout Set<String>) {
        let marker = Array("sampler_".utf8)
        var index = 0
        while index + marker.count <= code.count {
            guard code[index] == marker[0], matches(code, at: index, marker),
                  index == 0 || !isIdentifier(code[index - 1]) else {
                index += 1
                continue
            }
            var end = index + marker.count
            while end < code.count && isIdentifier(code[end]) { end += 1 }
            var name = Array(code[(index + marker.count)..<end]).map(lower)
            index = end
            if name.count > 3 && name[2] == 0x5F { name.removeFirst(3) }
            guard !name.isEmpty, name.count <= 64 else { continue }
            let text = String(decoding: name, as: UTF8.self)
            if engineTextures.contains(text) || known.contains(text) { continue }
            if name.count >= 6 && text.hasPrefix("rand") && isDigit(name[4]) && isDigit(name[5]) { continue }
            if missing.count < PresetImportLimits.maxWarnings * 2 { missing.insert(text) }
        }
    }

    // MARK: - License lines (R12)

    private static let licenseWords = ["license", "licence", "copyright", "public domain", "creative commons", "cc-by", "cc0"]
        .map { Array($0.utf8) }

    /// Comment lines, lines without "=", and trailing comments that mention a license or
    /// copyright. Kept verbatim, cut to the limit; nothing is interpreted.
    private static func licenseLines(_ bytes: [UInt8], _ lines: [Range<Int>]) -> [String] {
        var found: [String] = []
        for line in lines where found.count < PresetImportLimits.maxLicenseLines {
            let trimmed = trim(bytes, line)
            guard trimmed.count >= 4 else { continue }
            var region = trimmed
            let isComment = bytes[trimmed.lowerBound] == 0x2F && bytes[trimmed.lowerBound + 1] == 0x2F
            if !isComment && trimmed.contains(where: { bytes[$0] == 0x3D }) {
                guard let comment = (trimmed.lowerBound..<(trimmed.upperBound - 1)).first(where: { bytes[$0] == 0x2F && bytes[$0 + 1] == 0x2F }) else { continue }
                region = comment..<trimmed.upperBound
            }
            let lowered = bytes[region].map(lower)
            let mentions = licenseWords.contains { contains(lowered, $0) } || contains(lowered, [0xC2, 0xA9])   // ©
            guard mentions else { continue }
            let text = String(decoding: bytes[trimmed], as: UTF8.self)
            found.append(String(text.prefix(PresetImportLimits.maxLicenseLineCharacters)))
        }
        return found
    }

    // MARK: - Bytes

    /// `per_frame_12` → ("per_frame_", 12); `wave_0_per_point3` → ("wave_0_per_point", 3).
    private static func blockKey(_ key: String) -> (String, Int)? {
        let utf8 = Array(key.utf8)
        var split = utf8.count
        while split > 0 && isDigit(utf8[split - 1]) { split -= 1 }
        let digits = utf8.count - split
        guard digits >= 1, digits <= 5, split > 0, utf8[split] != 0x30,   // the engine counts 1…99999, no leading zero
              let number = Int(String(decoding: utf8[split...], as: UTF8.self)) else { return nil }
        let prefix = String(decoding: utf8[..<split], as: UTF8.self)
        if fixedPrefixes.contains(prefix) { return (prefix, number) }
        // wave_<n>_init, wave_<n>_per_frame, wave_<n>_per_point, shape_<n>_init, shape_<n>_per_frame
        let parts = prefix.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "wave" || parts[0] == "shape", !parts[1].isEmpty, parts[1].count <= 3,
              parts[1].utf8.allSatisfy(isDigit),
              parts[2] == "init" || parts[2] == "per_frame" || (parts[0] == "wave" && parts[2] == "per_point") else { return nil }
        return (prefix, number)
    }

    private static func trim(_ bytes: [UInt8], _ range: Range<Int>) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper && (bytes[lower] == 0x20 || bytes[lower] == 0x09) { lower += 1 }
        while upper > lower && (bytes[upper - 1] == 0x20 || bytes[upper - 1] == 0x09) { upper -= 1 }
        return lower..<upper
    }

    private static func lowercasedKey(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        String(decoding: bytes[range].map(lower), as: UTF8.self)
    }

    private static func equalsIgnoringCase(_ bytes: [UInt8], _ range: Range<Int>, _ text: String) -> Bool {
        let expected = Array(text.utf8)
        guard range.count == expected.count else { return false }
        for (offset, byte) in expected.enumerated() where lower(bytes[range.lowerBound + offset]) != byte { return false }
        return true
    }

    private static func matches(_ code: [UInt8], at index: Int, _ marker: [UInt8]) -> Bool {
        guard index + marker.count <= code.count else { return false }
        for offset in 0..<marker.count where code[index + offset] != marker[offset] { return false }
        return true
    }

    private static func contains(_ haystack: [UInt8], _ needle: String) -> Bool { contains(haystack, Array(needle.utf8)) }

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for index in 0...(haystack.count - needle.count) where haystack[index] == needle[0] && matches(haystack, at: index, needle) {
            return true
        }
        return false
    }

    private static func lower(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte }
    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
    private static func isIdentifier(_ byte: UInt8) -> Bool {
        isDigit(byte) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
    }
}
