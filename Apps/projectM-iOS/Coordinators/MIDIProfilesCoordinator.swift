// MIDIProfilesCoordinator.swift — MIDI mapping profiles in the MIDI Mappings screen (MIDI-012-R2-R10, R12;
// specs/171-midi-012-profiles, contract P2).
//
// * Profiles are `MIDIProfileList` values in `Application Support/MIDIProfiles/profiles.json` (research MIDI-012-D5):
//   a file this build cannot read is never overwritten (saving and editing are refused with a message).
// * Save Current snapshots the stored mapping lines verbatim ("Profile <n>"); Apply hands a profile's lines to
//   `MIDIMappingCoordinator.replaceLines` (one Undo step, announced on the `.midi` lane).
// * Export writes a temporary `.pmmidi` document for the system file mover and removes it afterwards; it never carries
//   the link. Import reads at most 128 KB of an untrusted file, validates it, adds it as a new profile (never applied)
//   and reports what it holds.
// * The link is a system unique number of a listed input; a listed linked input whose profile is not in use is
//   suggested, never applied by itself (research MIDI-012-D8). Input names are read from discovery when shown, never
//   stored.
// * Not in the FILE-005 library backup; erased by FILE-011's Settings category (`LibraryErasePolicy`, research D7).
import Foundation
import Observation
import PerformanceControl

/// One profile row (contract P3).
struct MIDIProfileRow: Identifiable, Equatable {
    let id: String
    let name: String
    let count: Int
    let inUse: Bool
    /// The linked input's current name; "not connected" when it is not listed; nil when not linked.
    let linkText: String?

    /// "3 mappings · In use"
    var detail: String {
        var text: String = String(count) + (count == 1 ? " mapping" : " mappings")
        if inUse { text += " · In use" }
        return text
    }

    /// "Launch Control, 3 mappings, in use, linked to Fake Keys"
    var accessibilityLabel: String {
        var text: String = name + ", " + String(count) + (count == 1 ? " mapping" : " mappings")
        if inUse { text += ", in use" }
        if let linkText { text += ", linked to " + linkText }
        return text
    }
}

/// An input a profile can be linked to.
struct MIDILinkTarget: Identifiable, Equatable {
    let endpoint: MIDIEndpointID
    let name: String
    var id: String { endpoint.description }
}

@MainActor
@Observable
final class MIDIProfilesCoordinator {
    nonisolated static let folderName: String = "MIDIProfiles"
    static let unreadableText: String = "Saved MIDI profiles could not be read, so they are left unchanged."
    static let notConnectedText: String = "a device that is not connected"

    private(set) var list = MIDIProfileList()
    private(set) var readError: MIDIProfileImportError?
    var message: String?
    /// The temporary document waiting for the file mover.
    private(set) var exportFile: URL?
    var showMover = false
    var showImporter = false
    /// The profile being renamed (the rename alert) and the text field's value.
    var renameID: String?
    var renameText: String = ""
    /// The profile waiting for the delete confirmation.
    var deleteID: String?

    /// Unowned: the mapping coordinator owns this coordinator (`profiles`).
    @ObservationIgnored unowned let mappings: MIDIMappingCoordinator
    @ObservationIgnored let store: MIDIProfileFileStore
    @ObservationIgnored private let makeID: () -> String
    @ObservationIgnored private let temporaryDirectory: URL

    init(mappings: MIDIMappingCoordinator, store: MIDIProfileFileStore,
         makeID: @escaping () -> String = { () -> String in UUID().uuidString },
         temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.mappings = mappings
        self.store = store
        self.makeID = makeID
        self.temporaryDirectory = temporaryDirectory
        reload()
    }

    /// `Application Support/MIDIProfiles` (the folder FILE-011's Settings erase removes).
    nonisolated static func defaultDirectory() throws -> URL {
        let support: URL = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
        return support.appendingPathComponent(folderName, isDirectory: true)
    }

    static func makeDefault(mappings: MIDIMappingCoordinator) -> MIDIProfilesCoordinator? {
        guard let directory = try? defaultDirectory() else { return nil }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitestResetMIDIProfiles") { try? FileManager.default.removeItem(at: directory) }
        #endif
        return MIDIProfilesCoordinator(mappings: mappings, store: MIDIProfileFileStore(directory: directory))
    }

    func reload() {
        switch store.load() {
        case let .success(loaded):
            list = loaded
            readError = nil
        case let .failure(error):
            list = MIDIProfileList()
            readError = error
        }
    }

    // MARK: Rows

    var rows: [MIDIProfileRow] {
        let current: [String] = mappings.storedLines
        let names: [MIDIEndpointID: String] = inputNames
        return list.profiles.map { (profile: MIDIProfile) -> MIDIProfileRow in
            let linkText: String? = profile.link.map { (number: Int32) -> String in names[.unique(number)] ?? Self.notConnectedText }
            return MIDIProfileRow(id: profile.id, name: profile.name, count: profile.lines.count,
                                  inUse: MIDIProfileList.inUse(profile, current: current), linkText: linkText)
        }
    }

    private var inputNames: [MIDIEndpointID: String] {
        var names: [MIDIEndpointID: String] = [:]
        for input in mappings.linkableInputs { names[input.id] = input.name }
        return names
    }

    /// Inputs a profile can be linked to (listed, online, with a system unique number).
    var linkTargets: [MIDILinkTarget] {
        mappings.linkableInputs.map { (input: (id: MIDIEndpointID, name: String)) -> MIDILinkTarget in
            MIDILinkTarget(endpoint: input.id, name: input.name)
        }
    }

    func profileName(_ id: String?) -> String {
        id.flatMap { (id: String) -> String? in list.profile(id: id)?.name } ?? ""
    }

    func startRename(_ id: String) {
        renameText = profileName(id)
        renameID = id
    }

    func finishRename() {
        guard let id = renameID else { return }
        renameID = nil
        rename(id: id, to: renameText)
    }

    func confirmDelete() {
        guard let id = deleteID else { return }
        deleteID = nil
        delete(id: id)
    }

    var canSave: Bool { readError == nil && !list.isFull }
    var canImport: Bool { readError == nil }

    /// MIDI-012-R8: the first linked profile whose input is listed and that is not in use, with the input's name.
    var suggestion: (profile: MIDIProfile, inputName: String)? {
        let names: [MIDIEndpointID: String] = inputNames
        guard let profile = list.suggestion(listed: Set(names.keys), current: mappings.storedLines),
              let link = profile.link, let name = names[.unique(link)] else { return nil }
        return (profile, name)
    }

    // MARK: Editing

    func saveCurrent() {
        guard readError == nil else { return say(Self.unreadableText) }
        var next: MIDIProfileList = list
        do {
            let profile: MIDIProfile = try next.saveCurrent(mappings.storedLines, id: makeID())
            guard commit(next) else { return }
            say("Saved MIDI profile " + profile.name + ".")
        } catch {
            say(Self.text(error))
        }
    }

    func apply(id: String) {
        guard let profile = list.profile(id: id) else { return }
        let text: String = "Applied MIDI profile " + profile.name + "."
        mappings.replaceLines(profile.lines, announcement: text)
        message = text
    }

    func rename(id: String, to name: String) {
        guard readError == nil, let old = list.profile(id: id)?.name else { return }
        var next: MIDIProfileList = list
        guard let newName = next.rename(id: id, to: name), newName != old else { return }
        guard commit(next) else { return }
        say("Renamed MIDI profile " + old + " to " + newName + ".")
    }

    func delete(id: String) {
        guard readError == nil else { return }
        var next: MIDIProfileList = list
        guard let removed = next.delete(id: id), commit(next) else { return }
        say("Deleted MIDI profile " + removed.name + ".")
    }

    /// Links a profile to a listed input, or unlinks it (nil).
    func link(id: String, to endpoint: MIDIEndpointID?) {
        guard readError == nil, let profile = list.profile(id: id) else { return }
        var next: MIDIProfileList = list
        guard next.setLink(endpoint, for: id), next != list, commit(next) else { return }
        if let endpoint, let name = inputNames[endpoint] {
            say(profile.name + " linked to " + name + ".")
        } else {
            say(profile.name + " unlinked.")
        }
    }

    /// Writes the list; on failure keeps the old one and says so.
    private func commit(_ next: MIDIProfileList) -> Bool {
        do {
            try store.write(next)
        } catch {
            say("MIDI profiles could not be saved.")
            return false
        }
        list = next
        return true
    }

    private func say(_ text: String) {
        message = text
        mappings.announce(text)
    }

    private static func text(_ error: any Error) -> String {
        (error as? MIDIProfileImportError)?.message ?? "The MIDI profile could not be saved."
    }

    // MARK: Export (MIDI-012-R4)

    /// Writes the profile's document to a temporary folder and opens the file mover; false when it fails.
    @discardableResult
    func prepareExport(id: String) -> Bool {
        guard let profile = list.profile(id: id) else { return false }
        discardExport()
        let folder: URL = temporaryDirectory.appendingPathComponent("MIDIProfileExport-" + UUID().uuidString, isDirectory: true)
        let file: URL = folder.appendingPathComponent(MIDIProfileDocument.fileName(for: profile.name), isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try MIDIProfileDocument.encode(name: profile.name, lines: profile.lines).write(to: file, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            say("The MIDI profile could not be exported.")
            return false
        }
        exportFile = file
        showMover = true
        return true
    }

    func exportFinished(_ result: Result<URL, any Error>) {
        if case .success = result { say("Exported MIDI profile.") }
        discardExport()
    }

    func exportCancelled() {
        discardExport()
    }

    /// Removes the temporary export folder (nothing is left in tmp/).
    private func discardExport() {
        if let exportFile { try? FileManager.default.removeItem(at: exportFile.deletingLastPathComponent()) }
        exportFile = nil
    }

    // MARK: Import (MIDI-012-R5)

    /// Reads a picked file (security-scoped, at most 128 KB plus one byte) and imports it.
    func importFile(at url: URL) {
        let scoped: Bool = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return say("Could not import: the file could not be read.")
        }
        defer { try? handle.close() }
        let data: Data = (try? handle.read(upToCount: MIDIProfileLimits.maxImportBytes + 1)) ?? Data()
        importData(data)
    }

    /// Validates and adds a document as a new profile; never applies it.
    func importData(_ data: Data) {
        guard readError == nil else { return say(Self.unreadableText) }
        do {
            let document = try MIDIProfileDocument.decode(data)
            var next: MIDIProfileList = list
            let report = MIDIProfileReport(lines: document.lines, existing: list.profiles)
            let profile: MIDIProfile = try next.add(name: document.name, lines: document.lines, id: makeID())
            guard commit(next) else { return }
            say("Imported MIDI profile " + profile.name + ". " + report.summary + " Tap Apply to use it.")
        } catch {
            say("Could not import: " + Self.text(error))
        }
    }
}
