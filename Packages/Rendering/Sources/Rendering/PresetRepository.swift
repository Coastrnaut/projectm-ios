// PresetRepository.swift — the bundled presets joined with LICENSES.md (task T074; FR-045, FR-047;
// research R-09; data-model.md §Preset).
//
// LICENSES.md sits in the presets folder and holds one Markdown table row per preset:
//
//   | File | Display name | Pack | Author | License | Source URL | Source version |
//   |------|--------------|------|--------|---------|------------|----------------|
//   | cream/Geiss - Dancer.milk | Dancer | cream-of-the-crop | Geiss | CC-BY-4.0 | https://… | 1a2b3c4 |
//
// "File" is the path relative to the presets folder. Every field is required (FR-047): a preset
// file with no row, or with an empty field, is excluded and reported, never shown. Rows whose file
// is missing are reported too. A literal "|" inside a cell is written "\|".
// The catalog is sorted alphabetically by display name (then by path), as FR-045's browser expects.
import Foundation

public struct PresetCatalog: Sendable, Equatable {
    public var presets: [Preset]
    public var excluded: [PresetExclusion]
}

public struct PresetExclusion: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// The preset file has no LICENSES.md row.
        case noLicenseRow
        /// The row exists but these fields are empty.
        case missingFields([String])
        /// A LICENSES.md row names a file that is not bundled.
        case fileMissing
        /// Two rows name the same file.
        case duplicateRow
    }

    /// Path relative to the presets folder.
    public var path: String
    public var reason: Reason
}

public enum PresetRepositoryError: Error, Equatable {
    case presetsFolderMissing(String)
    case licensesFileMissing
    /// LICENSES.md has no table with the expected header.
    case licensesTableMissing
}

public struct PresetRepository: Sendable {
    public static let licensesFileName = "LICENSES.md"
    public static let presetExtensions: Set<String> = ["milk", "prjm"]
    /// The LICENSES.md columns, in order (R-09).
    public static let columns = ["File", "Display name", "Pack", "Author", "License", "Source URL", "Source version"]

    public let presetsFolder: URL

    public init(presetsFolder: URL) {
        self.presetsFolder = presetsFolder
    }

    /// Reads the folder and LICENSES.md. Throws only when the folder, the file or its table is missing.
    public func load() throws -> PresetCatalog {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: presetsFolder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PresetRepositoryError.presetsFolderMissing(presetsFolder.path)
        }
        let licensesURL = presetsFolder.appendingPathComponent(PresetRepository.licensesFileName)
        guard let text = try? String(contentsOf: licensesURL, encoding: .utf8) else {
            throw PresetRepositoryError.licensesFileMissing
        }
        let rows = try PresetRepository.parseLicenses(text)
        let files = presetFiles()

        var excluded: [PresetExclusion] = []
        var byPath: [String: [String]] = [:]
        for row in rows {
            let path = row[0]
            if byPath[path] != nil {
                excluded.append(PresetExclusion(path: path, reason: .duplicateRow))
                continue
            }
            byPath[path] = row
        }

        var presets: [Preset] = []
        for path in files {
            guard let row = byPath[path] else {
                excluded.append(PresetExclusion(path: path, reason: .noLicenseRow))
                continue
            }
            let missing = zip(PresetRepository.columns, row).filter { $0.1.isEmpty }.map(\.0)
            if !missing.isEmpty {
                excluded.append(PresetExclusion(path: path, reason: .missingFields(missing)))
                continue
            }
            presets.append(Preset(id: path, name: row[1], fileURL: presetsFolder.appendingPathComponent(path),
                                  packID: row[2], author: row[3], license: row[4],
                                  sourceURL: row[5], sourceVersion: row[6]))
        }
        let fileSet = Set(files)
        for path in byPath.keys.sorted() where !fileSet.contains(path) {
            excluded.append(PresetExclusion(path: path, reason: .fileMissing))
        }

        presets.sort {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        excluded.sort { $0.path < $1.path }
        return PresetCatalog(presets: presets, excluded: excluded)
    }

    /// Relative paths of every preset file under the folder, sorted.
    func presetFiles() -> [String] {
        let base = presetsFolder.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var paths: [String] = []
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        for case let url as URL in enumerator {
            guard PresetRepository.presetExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard full.hasPrefix(prefix) else { continue }
            paths.append(String(full.dropFirst(prefix.count)))
        }
        return paths.sorted()
    }

    /// The table rows of LICENSES.md (7 cells each, trimmed), after the header and separator rows.
    static func parseLicenses(_ text: String) throws -> [[String]] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let expected = columns.map { $0.lowercased() }
        guard let headerIndex = lines.firstIndex(where: { cells(of: $0).map { $0.lowercased() } == expected }) else {
            throw PresetRepositoryError.licensesTableMissing
        }
        var rows: [[String]] = []
        for line in lines[(headerIndex + 1)...] {
            guard line.hasPrefix("|") else {
                if rows.isEmpty && line.isEmpty { continue }
                break   // the table ended
            }
            let row = cells(of: line)
            if row.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { continue }   // separator
            rows.append(Array((row + Array(repeating: "", count: columns.count)).prefix(columns.count)))
        }
        return rows
    }

    /// Cells of one Markdown table row; "\|" is a literal pipe.
    static func cells(of line: String) -> [String] {
        guard line.hasPrefix("|") else { return [] }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for ch in line.dropFirst() {
            if escaped {
                current.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { cells.append(tail) }
        return cells
    }
}
