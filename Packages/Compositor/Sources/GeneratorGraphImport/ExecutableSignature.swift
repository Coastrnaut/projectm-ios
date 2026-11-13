// ExecutableSignature.swift — recognizes programs, libraries, scripts and archives by their first
// bytes, and names the first code entry of a zip archive (SHD-011-R3; research SHD-011-D3). Public
// since FILE-001 so every importer shares one list (scene archive assets). It only
// compares bytes already in memory and limited by GraphImportLimits.maximumBytes; nothing is
// extracted, decompressed, written or loaded. Plain Swift; builds on Linux.

public enum ExecutableSignature {
    public enum Verdict: Equatable, Sendable {
        case executable(ExecutableKind)
        case archive(codeEntry: String?)
    }

    private static let executables: [([UInt8], ExecutableKind)] = [
        ([0xFE, 0xED, 0xFA, 0xCE], .machO), ([0xFE, 0xED, 0xFA, 0xCF], .machO),
        ([0xCE, 0xFA, 0xED, 0xFE], .machO), ([0xCF, 0xFA, 0xED, 0xFE], .machO),
        ([0xCA, 0xFE, 0xBA, 0xBE], .universalBinary), ([0xBE, 0xBA, 0xFE, 0xCA], .universalBinary),
        ([0xCA, 0xFE, 0xBA, 0xBF], .universalBinary), ([0xBF, 0xBA, 0xFE, 0xCA], .universalBinary),
        ([0x7F, 0x45, 0x4C, 0x46], .elf),
        ([0x4D, 0x5A], .windowsExecutable),                                  // "MZ"
        ([0x23, 0x21], .script),                                             // "#!"
        (Array("!<arch>\n".utf8), .staticLibrary),
        (Array("MTLB".utf8), .metalLibrary),
        ([0x00, 0x61, 0x73, 0x6D], .webAssembly),                            // "\0asm"
    ]

    private static let zipSignatures: [[UInt8]] = [[0x50, 0x4B, 0x03, 0x04], [0x50, 0x4B, 0x05, 0x06], [0x50, 0x4B, 0x07, 0x08]]
    private static let otherArchives: [[UInt8]] = [[0x1F, 0x8B], Array("xar!".utf8)]

    /// Extensions that mark a zip entry (or one of its folders) as code.
    static let codeEntryExtensions: Set<String> = [
        "dylib", "so", "a", "o", "framework", "bundle", "app", "appex", "metallib", "exe", "dll",
        "sh", "command", "py", "js", "wasm", "jar",
    ]

    public static func classify(_ bytes: [UInt8]) -> Verdict? {
        for (magic, kind) in executables where hasPrefix(bytes, magic) {
            return .executable(kind)
        }
        if zipSignatures.contains(where: { (m: [UInt8]) -> Bool in hasPrefix(bytes, m) }) {
            return .archive(codeEntry: firstCodeEntry(inZip: bytes))
        }
        if otherArchives.contains(where: { (m: [UInt8]) -> Bool in hasPrefix(bytes, m) }) {
            return .archive(codeEntry: nil)
        }
        return nil
    }

    static func hasPrefix(_ bytes: [UInt8], _ magic: [UInt8]) -> Bool {
        bytes.count >= magic.count && Array(bytes[0..<magic.count]) == magic
    }

    /// The first central-directory entry name with a path component ending in a code extension.
    /// Walks every `PK\x01\x02` record inside the bytes; every read is bounds-checked.
    static func firstCodeEntry(inZip bytes: [UInt8]) -> String? {
        var i = 0
        while i + 46 <= bytes.count {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x01, bytes[i + 3] == 0x02 {
                let length = Int(bytes[i + 28]) | (Int(bytes[i + 29]) << 8)
                let start = i + 46
                if length > 0, start + length <= bytes.count {
                    let name = String(decoding: bytes[start..<(start + length)], as: UTF8.self)
                    if isCodeEntry(name) { return name }
                    i = start + length
                    continue
                }
            }
            i += 1
        }
        return nil
    }

    static func isCodeEntry(_ name: String) -> Bool {
        name.split(separator: "/").contains { (component: Substring) -> Bool in
            guard let dot = component.lastIndex(of: ".") else { return false }
            return codeEntryExtensions.contains(component[component.index(after: dot)...].lowercased())
        }
    }
}
