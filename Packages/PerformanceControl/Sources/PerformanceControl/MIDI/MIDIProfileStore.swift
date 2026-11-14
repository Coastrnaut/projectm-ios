// MIDIProfileStore.swift — the saved profiles and their local file (MIDI-012-R2, R3, R8, R12; contract P1, research
// MIDI-012-D5, D8).
//
// * `MIDIProfileList` is the value model: at most 32 profiles with unique names, "Profile <n>" for Save Current, a
//   free name for imports ("Name (2)"), rename, delete, link, "In use" and the device suggestion.
// * `MIDIProfileFileStore` reads and atomically writes `<directory>/profiles.json` (format
//   `org.projectmios.midi-profiles`, version 1, at most 4 MB). A file it cannot read (corrupt, too large, newer) sets
//   `readError`, and every later write is refused, so the user's profiles are never overwritten by an older build.
import Foundation

/// The saved profiles (data-model "Store file").
public struct MIDIProfileList: Sendable, Hashable {
    public static let format: String = "org.projectmios.midi-profiles"
    public static let version: Int = 1

    public private(set) var profiles: [MIDIProfile] = []

    public init(profiles: [MIDIProfile] = []) {
        self.profiles = profiles
    }

    public var isFull: Bool { profiles.count >= MIDIProfileLimits.maxProfiles }

    public func profile(id: String) -> MIDIProfile? {
        profiles.first { (profile: MIDIProfile) -> Bool in profile.id == id }
    }

    private func nameTaken(_ name: String, except id: String? = nil) -> Bool {
        let lowered: String = name.lowercased()
        return profiles.contains { (profile: MIDIProfile) -> Bool in profile.id != id && profile.name.lowercased() == lowered }
    }

    /// `name`, or "name (2)", "name (3)" … (at most 60 characters in all).
    public func uniqueName(_ name: String, except id: String? = nil) -> String {
        guard nameTaken(name, except: id) else { return name }
        var number: Int = 2
        while true {
            let suffix: String = " (" + String(number) + ")"
            let base: String = String(name.prefix(MIDIProfileLimits.maxNameLength - suffix.count))
            let candidate: String = base + suffix
            if !nameTaken(candidate, except: id) { return candidate }
            number += 1
        }
    }

    /// "Profile <n>" with the lowest free n.
    public var nextDefaultName: String {
        var number: Int = 1
        while nameTaken("Profile " + String(number)) { number += 1 }
        return "Profile " + String(number)
    }

    /// Adds a profile with the lines verbatim (name cleaned and made unique). Throws when full or the lines are invalid.
    @discardableResult
    public mutating func add(name: String, lines: [String], link: Int32? = nil, id: String) throws(MIDIProfileImportError) -> MIDIProfile {
        guard !isFull else { throw .storeFull }
        guard let cleaned = MIDIProfileValidation.cleanName(name) else { throw .missingName }
        try MIDIProfileValidation.check(lines: lines)
        let profile = MIDIProfile(id: id, name: uniqueName(cleaned), lines: lines, link: link)
        profiles.append(profile)
        return profile
    }

    /// Save Current: the current lines under "Profile <n>".
    @discardableResult
    public mutating func saveCurrent(_ lines: [String], id: String) throws(MIDIProfileImportError) -> MIDIProfile {
        try add(name: nextDefaultName, lines: lines, id: id)
    }

    /// Renames a profile; an empty cleaned name keeps the old one. Returns the name in effect, nil for an unknown id.
    @discardableResult
    public mutating func rename(id: String, to raw: String) -> String? {
        guard let index = profiles.firstIndex(where: { (profile: MIDIProfile) -> Bool in profile.id == id }) else { return nil }
        guard let cleaned = MIDIProfileValidation.cleanName(raw) else { return profiles[index].name }
        profiles[index].name = uniqueName(cleaned, except: id)
        return profiles[index].name
    }

    @discardableResult
    public mutating func delete(id: String) -> MIDIProfile? {
        guard let index = profiles.firstIndex(where: { (profile: MIDIProfile) -> Bool in profile.id == id }) else { return nil }
        return profiles.remove(at: index)
    }

    /// Links a profile to an input (a system unique number) or unlinks it (nil). Fallback IDs are refused.
    @discardableResult
    public mutating func setLink(_ endpoint: MIDIEndpointID?, for id: String) -> Bool {
        guard let index = profiles.firstIndex(where: { (profile: MIDIProfile) -> Bool in profile.id == id }) else { return false }
        switch endpoint {
        case nil:
            profiles[index].link = nil
        case let .unique(number)?:
            profiles[index].link = number
        case .fallback?:
            return false
        }
        return true
    }

    /// Whether `profile`'s lines are the current list, byte for byte.
    public static func inUse(_ profile: MIDIProfile, current: [String]) -> Bool {
        MIDIProfile.sameBytes(profile.lines, current)
    }

    /// The first profile (in list order) linked to a listed input whose lines differ from the current list.
    public func suggestion(listed: Set<MIDIEndpointID>, current: [String]) -> MIDIProfile? {
        profiles.first { (profile: MIDIProfile) -> Bool in
            guard let link = profile.link, listed.contains(.unique(link)) else { return false }
            return !Self.inUse(profile, current: current)
        }
    }

    // MARK: File codec

    private struct File: Codable {
        let format: String
        let version: Int
        let profiles: [MIDIProfile]
    }

    private struct Header: Decodable {
        let format: String?
        let version: Int?
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(File(format: Self.format, version: Self.version, profiles: profiles))) ?? Data()
    }

    /// Reads a store file; throws for anything this version must not overwrite.
    public init(decoding data: Data) throws(MIDIProfileImportError) {
        guard data.count <= MIDIProfileLimits.maxStoreBytes else { throw .tooLarge }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == Self.format,
              let fileVersion = header.version, fileVersion >= 1 else { throw .notAProfile }
        guard fileVersion <= Self.version else { throw .newerVersion(fileVersion) }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { throw .notAProfile }
        guard file.profiles.count <= MIDIProfileLimits.maxProfiles else { throw .notAProfile }
        for profile in file.profiles {
            guard MIDIProfileValidation.cleanName(profile.name) == profile.name else { throw .missingName }
            try MIDIProfileValidation.check(lines: profile.lines)
        }
        profiles = file.profiles
    }
}

/// The profiles file under a directory (the app passes `Application Support/MIDIProfiles`).
public struct MIDIProfileFileStore: Sendable {
    public static let fileName: String = "profiles.json"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName, isDirectory: false) }

    /// The stored list, or an error when a file exists that cannot be read (then nothing may be written).
    public func load() -> Result<MIDIProfileList, MIDIProfileImportError> {
        let path: String = fileURL.path
        guard FileManager.default.fileExists(atPath: path) else { return .success(MIDIProfileList()) }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attributes[.size] as? NSNumber, size.intValue > MIDIProfileLimits.maxStoreBytes {
            return .failure(.tooLarge)
        }
        guard let data = try? Data(contentsOf: fileURL) else { return .failure(.notAProfile) }
        do throws(MIDIProfileImportError) {
            return .success(try MIDIProfileList(decoding: data))
        } catch {
            return .failure(error)
        }
    }

    /// Writes atomically; an empty list removes the file (and the folder when empty).
    public func write(_ list: MIDIProfileList) throws {
        if list.profiles.isEmpty {
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
            if let left = try? FileManager.default.contentsOfDirectory(atPath: directory.path), left.isEmpty {
                try? FileManager.default.removeItem(at: directory)
            }
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try list.encoded().write(to: fileURL, options: .atomic)
    }
}
