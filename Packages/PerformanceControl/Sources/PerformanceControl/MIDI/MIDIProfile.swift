// MIDIProfile.swift — MIDI mapping profiles (MIDI-012-R1, R4, R5, R11; specs/171-midi-012-profiles, contract P1,
// research MIDI-012-D1-D4).
//
// Pure Swift (Foundation's JSON coders only), Linux-testable.
// * A profile is a user-named snapshot of the stored mapping lines (`settings.midi.mappings`), verbatim and in order:
//   no line is parsed or rewritten, so channels, controller numbers and destination IDs survive byte for byte, and
//   lines this version cannot read are kept (D1). Comparisons use UTF-8 bytes (Swift `String` equality is canonical
//   equivalence, which would hide a byte change).
// * The optional link is a system unique number of an input (never a name-based fallback ID and never a name; ADR-0038
//   Decisions 4 and 8). It stays on the device: the exported document never carries it.
// * The exported document (`.pmmidi`) is sorted-key JSON: format tag, version, name, lines (D2). Import is untrusted:
//   size, format, version, line count, line length and control characters are checked (D4).
import Foundation

/// The bounds every profile and file obeys (research MIDI-012-D4).
public enum MIDIProfileLimits {
    public static let maxProfiles: Int = 32
    public static let maxLines: Int = 512
    public static let maxLineBytes: Int = 256
    public static let maxNameLength: Int = 60
    /// An imported document is read up to this size.
    public static let maxImportBytes: Int = 128 * 1024
    /// The local store file.
    public static let maxStoreBytes: Int = 4 * 1024 * 1024
}

/// One saved profile (data-model "Profile").
public struct MIDIProfile: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public var name: String
    public var lines: [String]
    /// A system unique number of a MIDI input (local only).
    public var link: Int32?

    public init(id: String, name: String, lines: [String], link: Int32? = nil) {
        self.id = id
        self.name = name
        self.lines = lines
        self.link = link
    }

    /// Lines in use that are not empty mappings: every stored line counts.
    public var mappingCount: Int { lines.count }

    /// Whether these lines equal `other` byte for byte and in order.
    public static func sameBytes(_ lines: [String], _ other: [String]) -> Bool {
        guard lines.count == other.count else { return false }
        for (left, right) in zip(lines, other) where !left.utf8.elementsEqual(right.utf8) { return false }
        return true
    }
}

// MARK: - Line kinds (research MIDI-012-D3)

/// What a stored mapping line is, for the import report.
public enum MIDIMappingLineKind: String, Sendable, Hashable, CaseIterable {
    case controlChange, noteTrigger, ccButton, realTime, scene, unread

    /// The kind of `line`; owned lines the owning list cannot read are `.unread`.
    public static func classify(_ line: String) -> MIDIMappingLineKind {
        if line.hasPrefix(MIDIControlBinding.controlChangeTag + ":") {
            return MIDIControlBinding(storageLine: line) == nil ? .unread : .controlChange
        }
        if MIDISceneBinding.isSceneLine(line) {
            let readable: Bool = MIDISceneBinding(storageLine: line) != nil || MIDIProgramCueMode(storageLine: line) != nil
            return readable ? .scene : .unread
        }
        if MIDINoteBinding.isTriggerLine(line) {
            guard let binding = MIDINoteBinding(storageLine: line) else { return .unread }
            switch binding.key.kind {
            case .controlChange: return .ccButton
            case .start, .stop: return .realTime
            default: return .noteTrigger
            }
        }
        return .unread
    }

    /// "control change" etc. (singular), for the report.
    public var title: String {
        switch self {
        case .controlChange: "control"
        case .noteTrigger: "note trigger"
        case .ccButton: "button"
        case .realTime: "Start/Stop trigger"
        case .scene: "scene trigger"
        case .unread: "unread line"
        }
    }
}

// MARK: - Import errors

/// Why a document was refused (contract P1). Nothing is added when any of these is thrown.
public enum MIDIProfileImportError: Error, Sendable, Hashable {
    case empty
    case tooLarge
    case notAProfile
    case newerVersion(Int)
    case missingName
    case missingLines
    case tooManyLines(Int)
    case lineTooLong(index: Int)
    case controlCharacters(index: Int)
    case storeFull

    public var message: String {
        switch self {
        case .empty: "The file is empty."
        case .tooLarge: "The file is too large to be a MIDI profile."
        case .notAProfile: "The file is not a projectM MIDI profile."
        case let .newerVersion(version): "The profile was made by a newer version of projectM (format " + String(version) + ")."
        case .missingName: "The file has no profile name."
        case .missingLines: "The file has no mapping lines."
        case let .tooManyLines(count): "The profile has too many lines (" + String(count) + "; at most " + String(MIDIProfileLimits.maxLines) + ")."
        case let .lineTooLong(index): "Line " + String(index + 1) + " is too long."
        case let .controlCharacters(index): "Line " + String(index + 1) + " contains control characters."
        case .storeFull: "No more profiles fit (" + String(MIDIProfileLimits.maxProfiles) + "). Delete one first."
        }
    }
}

// MARK: - Validation

public enum MIDIProfileValidation {
    /// A cleaned name: control characters removed, trimmed, at most 60 characters; nil when nothing is left.
    public static func cleanName(_ raw: String) -> String? {
        let scalars = raw.unicodeScalars.filter { (scalar: Unicode.Scalar) -> Bool in scalar.properties.generalCategory != .control }
        let trimmed: String = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let capped: String = String(trimmed.prefix(MIDIProfileLimits.maxNameLength))
        let result: String = capped.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Checks the line list (count, length, control characters); throws the first problem.
    public static func check(lines: [String]) throws(MIDIProfileImportError) {
        guard lines.count <= MIDIProfileLimits.maxLines else { throw .tooManyLines(lines.count) }
        for (index, line) in lines.enumerated() {
            guard line.utf8.count <= MIDIProfileLimits.maxLineBytes else { throw .lineTooLong(index: index) }
            let hasControl: Bool = line.unicodeScalars.contains { (scalar: Unicode.Scalar) -> Bool in
                scalar.properties.generalCategory == .control
            }
            if hasControl { throw .controlCharacters(index: index) }
        }
    }
}

// MARK: - The exported document (research MIDI-012-D2)

public enum MIDIProfileDocument {
    public static let format: String = "org.projectmios.midi-profile"
    public static let version: Int = 1
    public static let fileExtension: String = "pmmidi"

    private struct Body: Codable {
        let format: String
        let version: Int
        let name: String
        let lines: [String]
    }

    private struct Envelope: Decodable {
        let format: String?
        let version: Int?
        let name: String?
        let lines: [String]?
    }

    /// Sorted-key, pretty-printed JSON with the name and the lines only (never the link).
    public static func encode(name: String, lines: [String]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let body = Body(format: format, version: version, name: name, lines: lines)
        return (try? encoder.encode(body)) ?? Data()
    }

    /// Reads and validates a document (untrusted input). The name is cleaned; the lines are returned verbatim.
    public static func decode(_ data: Data) throws(MIDIProfileImportError) -> (name: String, lines: [String]) {
        guard !data.isEmpty else { throw .empty }
        guard data.count <= MIDIProfileLimits.maxImportBytes else { throw .tooLarge }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw .notAProfile
        }
        guard envelope.format == format else { throw .notAProfile }
        guard let fileVersion = envelope.version, fileVersion >= 1 else { throw .notAProfile }
        guard fileVersion <= version else { throw .newerVersion(fileVersion) }
        guard let rawName = envelope.name, let name = MIDIProfileValidation.cleanName(rawName) else { throw .missingName }
        guard let lines = envelope.lines else { throw .missingLines }
        try MIDIProfileValidation.check(lines: lines)
        return (name, lines)
    }

    /// "Launch Control.pmmidi": `/`, `\`, `:` and control characters become "-"; "MIDI Profile" when nothing is left.
    public static func fileName(for name: String) -> String {
        let replaced: String = String(name.unicodeScalars.map { (scalar: Unicode.Scalar) -> Character in
            if scalar == "/" || scalar == "\\" || scalar == ":" || scalar.properties.generalCategory == .control { return "-" }
            return Character(scalar)
        })
        var base: String = String(replaced.trimmingCharacters(in: .whitespacesAndNewlines).prefix(MIDIProfileLimits.maxNameLength))
        if base.isEmpty || base.hasPrefix(".") { base = "MIDI Profile" }
        return base + "." + fileExtension
    }
}

// MARK: - The import report

/// What an imported profile holds (data-model "Import report").
public struct MIDIProfileReport: Sendable, Hashable {
    public let counts: [MIDIMappingLineKind: Int]
    /// The name of an existing profile with the same lines, if any.
    public let duplicateOf: String?

    public init(lines: [String], existing: [MIDIProfile] = []) {
        var counts: [MIDIMappingLineKind: Int] = [:]
        for line in lines { counts[MIDIMappingLineKind.classify(line), default: 0] += 1 }
        self.counts = counts
        duplicateOf = existing.first { (profile: MIDIProfile) -> Bool in MIDIProfile.sameBytes(profile.lines, lines) }?.name
    }

    public var unread: Int { counts[.unread] ?? 0 }

    /// "3 controls, 1 note trigger, 2 scene triggers. 2 lines are not used by this version and are kept as they are."
    public var summary: String {
        var parts: [String] = []
        for kind in MIDIMappingLineKind.allCases where kind != .unread {
            guard let count = counts[kind], count > 0 else { continue }
            parts.append(String(count) + " " + kind.title + (count == 1 ? "" : "s"))
        }
        var text: String = parts.isEmpty ? "No mappings." : parts.joined(separator: ", ") + "."
        let unread: Int = self.unread
        if unread == 1 {
            text += " 1 line is not used by this version and is kept as it is."
        } else if unread > 1 {
            text += " " + String(unread) + " lines are not used by this version and are kept as they are."
        }
        if let duplicateOf { text += " Same mappings as “" + duplicateOf + "”." }
        return text
    }
}
