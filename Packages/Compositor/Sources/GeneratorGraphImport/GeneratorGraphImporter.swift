// GeneratorGraphImporter.swift — the import path for user-supplied generator-graph files
// (SHD-011-R2 to R7; contracts/graph-import.md; ADR-0024; ADR-0019 Decision 6).
//
// Input is the bytes a document picker delivered and the picked file's name. Checks run in a fixed
// order and the first failure decides: file-name extension, emptiness, the byte-size limit (before
// any content is read), executable and archive signatures, UTF-8, a JSON object at the top level,
// bracket nesting; only then does `JSONDecoder` decode the SHD-002 document, which SHD-002 validates
// and compiles unchanged. An accepted graph is drawn only by SHD-002's one fixed interpreter shader.
// This module reads no file, bundle or URL, opens no network connection, compiles no shader and
// loads nothing (GraphImportSourceSafetyTests; scripts/check_compliance.py). Builds on Linux.

import Foundation
import GeneratorGraph

/// An accepted import: the decoded document, its compiled plan, and the canonical bytes (sorted
/// keys, only the document's own fields) that any storage keeps instead of the original file.
public struct ImportedGeneratorGraph: Sendable, Equatable {
    public let document: GeneratorGraphDocument
    public let compiled: CompiledGeneratorGraph
    public let canonicalData: Data
}

public enum GeneratorGraphImporter {
    public static func importGraph(_ data: Data, fileName: String? = nil) throws(GeneratorGraphImportError) -> ImportedGeneratorGraph {
        if let ext = fileExtension(fileName) {
            if GraphImportLimits.executableExtensions.contains(ext) { throw .executableFileType(ext) }
            if !GraphImportLimits.acceptedExtensions.contains(ext) { throw .unsupportedFileType(ext) }
        }
        if data.isEmpty { throw .empty }
        if data.count > GraphImportLimits.maximumBytes {
            throw .tooLarge(bytes: data.count, limit: GraphImportLimits.maximumBytes)
        }
        let bytes = [UInt8](data)
        switch ExecutableSignature.classify(bytes) {
        case let .executable(kind)?: throw .executableContent(kind)
        case let .archive(entry)?: throw .archive(codeEntry: entry)
        case nil: break
        }
        let body = hasBOM(bytes) ? Array(bytes[3...]) : bytes
        guard String(validating: body, as: UTF8.self) != nil else { throw .notText }
        guard body.first(where: { (b: UInt8) -> Bool in !isWhitespace(b) }) == UInt8(ascii: "{") else {
            throw .notGraphDocument
        }
        if nesting(body) > GraphImportLimits.maximumNesting {
            throw .nestingTooDeep(limit: GraphImportLimits.maximumNesting)
        }

        let document: GeneratorGraphDocument
        do {
            document = try JSONDecoder().decode(GeneratorGraphDocument.self, from: Data(body))
        } catch let error as DecodingError {
            throw .malformed(reason(error))
        } catch {
            throw .malformed("invalid JSON")
        }

        let compiled: CompiledGeneratorGraph
        do {
            compiled = try GeneratorGraphCompiler.compile(document)
        } catch {
            throw .invalidGraph(error.issues)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let canonical = try? encoder.encode(document) else { throw .malformed("could not be re-encoded") }
        return ImportedGeneratorGraph(document: document, compiled: compiled, canonicalData: canonical)
    }

    /// The lowercased extension of the name's last path component, or nil when there is none (a
    /// leading dot, as in ".json", is a hidden name, not an extension).
    static func fileExtension(_ fileName: String?) -> String? {
        guard let fileName, let last = fileName.split(separator: "/").last,
              let dot = last.lastIndex(of: "."), dot != last.startIndex else { return nil }
        let ext = last[last.index(after: dot)...]
        return ext.isEmpty ? nil : ext.lowercased()
    }

    static func hasBOM(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF
    }

    static func isWhitespace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D }

    /// Deepest `{`/`[` nesting outside JSON strings (escapes inside strings are skipped). One pass,
    /// no recursion.
    static func nesting(_ bytes: [UInt8]) -> Int {
        var depth = 0
        var deepest = 0
        var inString = false
        var escaped = false
        for b in bytes {
            if inString {
                if escaped { escaped = false } else if b == UInt8(ascii: "\\") { escaped = true } else if b == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch b {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                deepest = max(deepest, depth)
            case UInt8(ascii: "}"), UInt8(ascii: "]"): depth -= 1
            default: break
            }
        }
        return deepest
    }

    /// A fixed, platform-independent reason for a decoding failure (never the platform's text).
    static func reason(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            let at = path(context.codingPath)
            return at.isEmpty ? "missing key \"\(key.stringValue)\"" : "missing key \"\(key.stringValue)\" at \(at)"
        case let .typeMismatch(_, context):
            return "wrong type at \(described(context.codingPath))"
        case let .valueNotFound(_, context):
            return "missing value at \(described(context.codingPath))"
        case let .dataCorrupted(context):
            return context.codingPath.isEmpty ? "invalid JSON" : "invalid value at \(path(context.codingPath))"
        @unknown default:
            return "invalid JSON"
        }
    }

    private static func described(_ codingPath: [any CodingKey]) -> String {
        let p = path(codingPath)
        return p.isEmpty ? "the top level" : p
    }

    static func path(_ codingPath: [any CodingKey]) -> String {
        var out = ""
        for key in codingPath {
            if let index = key.intValue, key.stringValue.hasPrefix("Index ") {
                out += "[\(index)]"
            } else {
                out += out.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return out
    }
}
