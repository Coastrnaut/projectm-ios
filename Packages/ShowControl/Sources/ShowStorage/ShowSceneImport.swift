// ShowSceneImport.swift — FILE-004 (specs/111-file-004-import-conflict-resolver; FILE-004-R1-R7, R10;
// contract C3; research FILE-004-D2, D4, D5): installing imported scenes into the show's folder with a
// choice per duplicate scene ID: Skip, Keep both (a derived scene ID and a copy name) or Replace (the
// stored scene keeps its ID, so every cue that refers to it stays valid).
//
// * `ShowSceneImportPlanner.plan` is pure: equal inputs give equal plans (derived IDs come from
//   SHA-256 of the incoming ID and the scene's canonical bytes), so the install re-validates with `==`.
// * `ShowStore.planSceneImport` reads only. `installImportedScenes` plans again, then:
//     1. stages every final scene in `ImportStaging/` (written whole, read back and hashed);
//     2. writes `scene-import.journal.json` (phase "prepared": added and replaced IDs);
//     3. moves each replaced scene file into `ImportStaging/replaced/` (the backup);
//     4. moves the staged files into `Scenes/`;
//     5. replaces the journal with phase "committed" and the new show bytes — the commit point;
//     6. writes `show.json`, removes `ImportStaging/` and the journal.
//   A failure in 1-5 restores every moved file and removes everything added (byte-for-byte as
//   before). After 5 an unfinished step is completed by `recoverInterruptedSceneImport()` (call it
//   before `load()`), which also rolls a "prepared" journal back. Every file operation goes through one
//   function with a test hook.
// * The scene import screen (SCN-014) is not built: the app does not call this yet.
// No networking; nothing read is executed.
import Foundation
import LocalPortability
import SceneFormat
import ShowControl

/// What happens to an imported scene whose ID is already stored (FILE-004-R1).
public enum ShowSceneImportChoice: String, Sendable, Hashable, CaseIterable {
    /// Install it under a derived scene ID and, when its name is taken, a copy name. The default.
    case keepBoth
    /// Leave it out; the stored scene is not touched.
    case skip
    /// The stored scene keeps its ID and takes the imported content.
    case replace
}

public enum ShowSceneImportKind: Sendable, Hashable {
    case new
    /// The same canonical bytes are stored under the same ID: nothing to do.
    case identical
    /// The ID is stored (or used by an earlier scene of this import). `existingName` is nil when the
    /// stored file cannot be read; `cueCount` is how many cues use it.
    case idConflict(existingName: String?, cueCount: Int)
}

/// One scene the install writes.
public struct ShowSceneImportAction: Sendable, Hashable {
    public let sceneID: String
    public let name: String
    /// True when the stored scene with this ID is overwritten.
    public let replaces: Bool
    /// The cue appended for a new or kept-both scene; nil for a replaced scene.
    public let cueID: UUID?
}

public struct ShowSceneImportEntry: Sendable, Hashable {
    public let incomingID: String
    public let incomingName: String
    /// SHA-256 of the incoming scene's canonical SCN-001 bytes.
    public let contentSHA256: String
    public let kind: ShowSceneImportKind
    /// The effective choice for a conflict; nil otherwise.
    public let choice: ShowSceneImportChoice?
    /// Nil when skipped or identical.
    public let install: ShowSceneImportAction?
    /// Replace was chosen without a stored target (or it was replaced earlier): installed as Keep both.
    public let fellBack: Bool

    public var isConflict: Bool {
        if case .idConflict = kind { return true }
        return false
    }
}

public enum ShowSceneImportRefusal: Error, Sendable, Hashable {
    /// The stored show could not be read (damaged or from a newer app version).
    case showUnreadable
    /// An earlier scene import did not finish; `recoverInterruptedSceneImport()` must run first.
    case interruptedImport
    /// An imported scene's ID is not a scene ID.
    case invalidSceneID(String)
    /// The show cannot hold the cues the import adds.
    case tooManyCues(limit: Int)

    public var message: String {
        switch self {
        case .showUnreadable: "The show could not be read."
        case .interruptedImport: "An earlier scene import did not finish."
        case let .invalidSceneID(id): "\"\(id)\" is not a scene ID."
        case let .tooManyCues(limit): "A show holds at most \(limit) cues."
        }
    }
}

/// A stored scene as the planner sees it.
public struct ShowStoredSceneSummary: Sendable, Hashable {
    public let id: String
    /// Nil when the file cannot be read.
    public let name: String?
    /// SHA-256 of the file's bytes.
    public let contentSHA256: String

    public init(id: String, name: String?, contentSHA256: String) {
        self.id = id
        self.name = name
        self.contentSHA256 = contentSHA256
    }
}

public struct ShowSceneImportPlan: Sendable, Hashable {
    /// SHA-256 over the show file and every stored scene file when planned.
    public let libraryDigest: String
    /// "Apply to all".
    public let defaultChoice: ShowSceneImportChoice
    /// Per-conflict choices by incoming scene ID, as given.
    public let overrides: [String: ShowSceneImportChoice]
    public let refusal: ShowSceneImportRefusal?
    /// In import order.
    public let entries: [ShowSceneImportEntry]

    public var actions: [ShowSceneImportAction] { entries.compactMap(\.install) }
    public var canInstall: Bool { refusal == nil && !actions.isEmpty }
    public var conflictCount: Int { entries.filter(\.isConflict).count }
    public var replaceCount: Int { actions.filter(\.replaces).count }
}

/// How a scene install ended.
public enum ShowSceneImportOutcome: Sendable, Equatable {
    /// The show with its new cues, and the scenes as stored, in import order.
    case installed(ShowCueList, [SceneDocument])
    /// The show or its scenes changed since the plan: the new plan; nothing was written.
    case changed(ShowSceneImportPlan)
    /// Nothing was written; the words say why.
    case refused(String)

    public static func == (lhs: ShowSceneImportOutcome, rhs: ShowSceneImportOutcome) -> Bool {
        switch (lhs, rhs) {
        case let (.installed(a, b), .installed(c, d)): a.encoded() == c.encoded() && b == d
        case let (.changed(a), .changed(b)): a == b
        case let (.refused(a), .refused(b)): a == b
        default: false
        }
    }
}

public enum ShowSceneImportText {
    public static let nothingToInstall = "Nothing to install."
    public static let saveFailed = "The scenes could not be saved."
    public static func nothingInstalled(_ reason: String) -> String { "Nothing was installed. " + reason }
}

// MARK: - The planner (pure)

public enum ShowSceneImportPlanner {
    public static func plan(incoming: [SceneDocument], stored: [ShowStoredSceneSummary], show: ShowCueList, libraryDigest: String,
                            defaultChoice: ShowSceneImportChoice = .keepBoth,
                            overrides: [String: ShowSceneImportChoice] = [:]) -> ShowSceneImportPlan {
        func refused(_ refusal: ShowSceneImportRefusal) -> ShowSceneImportPlan {
            ShowSceneImportPlan(libraryDigest: libraryDigest, defaultChoice: defaultChoice, overrides: overrides, refusal: refusal, entries: [])
        }
        if let bad = incoming.first(where: { (document: SceneDocument) -> Bool in !ShowCueList.isSceneID(document.id) }) {
            return refused(.invalidSceneID(bad.id))
        }
        var storedByID: [String: ShowStoredSceneSummary] = [:]
        for scene in stored { storedByID[scene.id] = scene }
        var takenIDs: Set<String> = Set(storedByID.keys)
        var takenNames: Set<String> = Set(stored.compactMap { (scene: ShowStoredSceneSummary) -> String? in scene.name?.lowercased() })
        var takenCueIDs: Set<UUID> = Set(show.cues.map(\.id))
        var plannedNames: [String: String] = [:]   // planned scene ID → name
        var replaced: Set<String> = []
        var entries: [ShowSceneImportEntry] = []
        var addedCues = 0

        for document in incoming {
            let sha = PortableSHA256.hex(document.encoded())
            let cueCount: Int = show.cues.filter { (cue: ShowCue) -> Bool in cue.sceneID == document.id }.count
            let kind: ShowSceneImportKind
            if let existing = storedByID[document.id], plannedNames[document.id] == nil {
                kind = existing.contentSHA256 == sha && !replaced.contains(document.id) ? .identical
                    : .idConflict(existingName: existing.name, cueCount: cueCount)
            } else if let planned = plannedNames[document.id] {
                kind = .idConflict(existingName: planned, cueCount: cueCount)
            } else {
                kind = .new
            }
            if kind == .identical {
                entries.append(ShowSceneImportEntry(incomingID: document.id, incomingName: document.name, contentSHA256: sha, kind: kind,
                                                    choice: nil, install: nil, fellBack: false))
                continue
            }
            let isConflict: Bool = kind != .new
            let choice: ShowSceneImportChoice? = isConflict ? (overrides[document.id] ?? defaultChoice) : nil
            if choice == .skip {
                entries.append(ShowSceneImportEntry(incomingID: document.id, incomingName: document.name, contentSHA256: sha, kind: kind,
                                                    choice: choice, install: nil, fellBack: false))
                continue
            }
            let canReplace: Bool = storedByID[document.id] != nil && !replaced.contains(document.id) && plannedNames[document.id] == nil
            let action: ShowSceneImportAction
            if choice == .replace && canReplace {
                replaced.insert(document.id)
                action = ShowSceneImportAction(sceneID: document.id, name: document.name, replaces: true, cueID: nil)
            } else {
                let sceneID: String = isConflict ? derivedSceneID(incomingID: document.id, contentSHA256: sha, avoiding: takenIDs) : document.id
                let name: String = isConflict && takenNames.contains(document.name.lowercased())
                    ? copyName(document.name, taken: takenNames) : document.name
                let cueID = derivedCueID(sceneID: sceneID, avoiding: takenCueIDs)
                takenCueIDs.insert(cueID)
                addedCues += 1
                action = ShowSceneImportAction(sceneID: sceneID, name: name, replaces: false, cueID: cueID)
            }
            takenIDs.insert(action.sceneID)
            takenNames.insert(action.name.lowercased())
            plannedNames[action.sceneID] = action.name
            let fellBack: Bool = choice == .replace && !action.replaces
            entries.append(ShowSceneImportEntry(incomingID: document.id, incomingName: document.name, contentSHA256: sha, kind: kind,
                                                choice: choice, install: action, fellBack: fellBack))
        }
        guard show.cues.count + addedCues <= ShowCueList.maximumCues else { return refused(.tooManyCues(limit: ShowCueList.maximumCues)) }
        return ShowSceneImportPlan(libraryDigest: libraryDigest, defaultChoice: defaultChoice, overrides: overrides, refusal: nil, entries: entries)
    }

    /// Research FILE-004-D2: canonical uppercase UUID text from the first 16 bytes of SHA-256(seed),
    /// version nibble 8 (RFC 9562 custom) and variant `10`.
    public static func derivedUUID(_ seed: String) -> UUID {
        let hex: [Character] = Array(PortableSHA256.hex(Array(seed.utf8)).uppercased().prefix(32))
        var digits: [Character] = hex
        digits[12] = "8"
        let variantDigits: [Character] = ["8", "9", "A", "B"]
        let nibble: Int = Int(String(digits[16]), radix: 16) ?? 0
        digits[16] = variantDigits[nibble % 4]
        let parts: [String] = [String(digits[0..<8]), String(digits[8..<12]), String(digits[12..<16]), String(digits[16..<20]),
                               String(digits[20..<32])]
        return UUID(uuidString: parts.joined(separator: "-")) ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0x80, 0, 0x80, 0, 0, 0, 0, 0, 0, 0))
    }

    /// Kept both: SHA-256("FILE-004|scene|<incoming id>|<content sha256>|<n>"), smallest n ≥ 1 free.
    public static func derivedSceneID(incomingID: String, contentSHA256: String, avoiding taken: Set<String>) -> String {
        var number = 1
        while true {
            let candidate = derivedUUID("FILE-004|scene|" + incomingID + "|" + contentSHA256 + "|" + String(number)).uuidString
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    /// The cue for an added scene: SHA-256("FILE-004|cue|<final scene id>|<n>"), smallest n ≥ 1 free.
    public static func derivedCueID(sceneID: String, avoiding taken: Set<UUID>) -> UUID {
        var number = 1
        while true {
            let candidate = derivedUUID("FILE-004|cue|" + sceneID + "|" + String(number))
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    /// "<name> copy", then "<name> copy 2", … not in `taken` (lowercase names); fits 120 characters.
    public static func copyName(_ name: String, taken: Set<String>) -> String {
        let base = SceneDocument.normalizedName(name) ?? SceneDocument.fallbackName
        var number = 1
        while true {
            let suffix: String = number == 1 ? SceneDocument.copySuffix : SceneDocument.copySuffix + " " + String(number)
            let room: Int = SceneLimits.maximumNameLength - suffix.count
            let shortened: String = base.count > room ? (SceneDocument.normalizedName(String(base.prefix(room))) ?? SceneDocument.fallbackName) : base
            let candidate = shortened + suffix
            if !taken.contains(candidate.lowercased()) { return candidate }
            number += 1
        }
    }

    /// A cue label (1…80 characters) for a scene name.
    static func cueLabel(_ name: String) -> String {
        ShowCueList.normalizedLabel(name) ?? ShowCueList.normalizedLabel(String(name.prefix(ShowCueList.maximumLabelLength))) ?? "Cue"
    }
}

// MARK: - Store: plan, install, recover

/// A file operation of the scene install (tests inject faults per operation).
enum ShowSceneImportFileOperation: Sendable, Equatable {
    case createDirectory, write, move, remove
}

/// Thrown by a test fault hook to stop the install as if the app ended there (no rollback).
struct ShowSceneImportInterruption: Error {}

private struct ShowSceneImportJournal: Codable {
    var version = 1
    var phase: String
    var added: [String]
    var replaced: [String]
    var directoryExisted: Bool
    var scenesFolderExisted: Bool
    /// Base64 of the new show bytes (committed only).
    var show: String?
}

extension ShowStore {
    static let importStagingFolderName = "ImportStaging"
    static let importJournalFileName = "scene-import.journal.json"

    var importStagingFolder: URL { directory.appendingPathComponent(Self.importStagingFolderName, isDirectory: true) }
    var importBackupFolder: URL { importStagingFolder.appendingPathComponent("replaced", isDirectory: true) }
    var importJournalFile: URL { directory.appendingPathComponent(Self.importJournalFileName, isDirectory: false) }

    /// The stored show (an empty show with a fixed ID when there is none), or nil when it cannot be read.
    private func readShowForImport() -> (list: ShowCueList, bytes: Data?)? {
        guard let data = try? Data(contentsOf: showFile) else {
            return (ShowCueList(id: ShowSceneImportPlanner.derivedUUID("FILE-004|show"), name: ShowCueList.defaultName), nil)
        }
        guard let decoded = try? ShowCueList.decode(data) else { return nil }
        return (decoded.list, data)
    }

    private func storedSummaries() -> [ShowStoredSceneSummary] {
        storedSceneIDs().sorted().compactMap { (id: String) -> ShowStoredSceneSummary? in
            guard let data = try? Data(contentsOf: sceneFile(id)) else { return nil }
            return ShowStoredSceneSummary(id: id, name: try? scene(id).document.name, contentSHA256: PortableSHA256.hex(data))
        }
    }

    private func libraryDigest(show: Data?, scenes: [ShowStoredSceneSummary]) -> String {
        var lines: [String] = ["show:" + (show.map { (data: Data) -> String in PortableSHA256.hex(data) } ?? "none")]
        for scene in scenes { lines.append("scene:" + scene.id + ":" + scene.contentSHA256) }
        return PortableSHA256.hex(Array(lines.joined(separator: "\n").utf8))
    }

    /// FILE-004 contract C3: the dry run against the stored show and scenes. Reads only.
    public func planSceneImport(_ documents: [SceneDocument], defaultChoice: ShowSceneImportChoice = .keepBoth,
                                overrides: [String: ShowSceneImportChoice] = [:]) -> ShowSceneImportPlan {
        let scenes = storedSummaries()
        func refused(_ refusal: ShowSceneImportRefusal, digest: String) -> ShowSceneImportPlan {
            ShowSceneImportPlan(libraryDigest: digest, defaultChoice: defaultChoice, overrides: overrides, refusal: refusal, entries: [])
        }
        guard let show = readShowForImport() else {
            return refused(.showUnreadable, digest: libraryDigest(show: try? Data(contentsOf: showFile), scenes: scenes))
        }
        let digest = libraryDigest(show: show.bytes, scenes: scenes)
        if FileManager.default.fileExists(atPath: importJournalFile.path) { return refused(.interruptedImport, digest: digest) }
        return ShowSceneImportPlanner.plan(incoming: documents, stored: scenes, show: show.list, libraryDigest: digest,
                                           defaultChoice: defaultChoice, overrides: overrides)
    }

    /// FILE-004-R6, R7: plans again (a different plan is returned with nothing written), then installs
    /// all or nothing (header). `documents` must be the scenes the plan was made from, in order.
    public func installImportedScenes(_ documents: [SceneDocument], plan: ShowSceneImportPlan) -> ShowSceneImportOutcome {
        installImportedScenes(documents, plan: plan, fault: nil)
    }

    func installImportedScenes(_ documents: [SceneDocument], plan: ShowSceneImportPlan,
                               fault: ((ShowSceneImportFileOperation, URL) throws -> Void)?) -> ShowSceneImportOutcome {
        let current = planSceneImport(documents, defaultChoice: plan.defaultChoice, overrides: plan.overrides)
        guard current == plan else { return .changed(current) }
        if let refusal = plan.refusal { return .refused(ShowSceneImportText.nothingInstalled(refusal.message)) }
        guard plan.canInstall, documents.count == plan.entries.count, var list = readShowForImport()?.list else {
            return .refused(ShowSceneImportText.nothingToInstall)
        }
        // The scenes as they will be stored, and the show with the new cues.
        var finals: [SceneDocument] = []
        do {
            for (document, entry) in zip(documents, plan.entries) {
                guard let action = entry.install else { continue }
                let final: SceneDocument = action.sceneID == document.id
                    ? try document.renamed(to: action.name) : try document.duplicated(newID: action.sceneID, name: action.name)
                finals.append(final)
                if let cueID = action.cueID {
                    try list.append(sceneID: action.sceneID, label: ShowSceneImportPlanner.cueLabel(action.name), cueID: cueID)
                }
            }
        } catch {
            return .refused(ShowSceneImportText.nothingToInstall)
        }
        let replacedIDs: [String] = plan.actions.filter(\.replaces).map(\.sceneID)
        let addedIDs: [String] = finals.map(\.id)
        let files = SceneImportFiles(fault: fault)
        let manager = FileManager.default
        let directoryExisted = manager.fileExists(atPath: directory.path)
        let scenesExisted = manager.fileExists(atPath: scenesFolder.path)
        var movedIn: [String] = []
        var movedOut: [String] = []
        func rollback() {
            for id in movedIn.reversed() { try? files.remove(sceneFile(id)) }
            for id in movedOut.reversed() { try? files.move(backupFile(id), to: sceneFile(id)) }
            if manager.fileExists(atPath: importStagingFolder.path) { try? files.remove(importStagingFolder) }
            if manager.fileExists(atPath: importJournalFile.path) { try? files.remove(importJournalFile) }
            if !scenesExisted { files.removeIfEmpty(scenesFolder) }
            if !directoryExisted { files.removeIfEmpty(directory) }
        }
        let showBytes = list.encoded()
        do {
            try files.createDirectory(importStagingFolder)
            for final in finals {
                let bytes = Data(final.encoded())
                let staged = stagedFile(final.id)
                try files.write(bytes, to: staged)
                guard let back = try? Data(contentsOf: staged), back == bytes else { throw ShowStoreError.writeFailed }
            }
            if !replacedIDs.isEmpty { try files.createDirectory(importBackupFolder) }
            var journal = ShowSceneImportJournal(phase: "prepared", added: addedIDs, replaced: replacedIDs,
                                                 directoryExisted: directoryExisted, scenesFolderExisted: scenesExisted, show: nil)
            try files.write(try JSONEncoder().encode(journal), to: importJournalFile)
            try files.createDirectory(scenesFolder)
            for id in replacedIDs {
                try files.move(sceneFile(id), to: backupFile(id))
                movedOut.append(id)
            }
            for id in addedIDs {
                try files.move(stagedFile(id), to: sceneFile(id))
                movedIn.append(id)
            }
            journal.phase = "committed"
            journal.show = showBytes.base64EncodedString()
            try files.write(try JSONEncoder().encode(journal), to: importJournalFile)   // the commit
        } catch is ShowSceneImportInterruption {
            return .refused("interrupted")   // tests only: the app ended here
        } catch {
            rollback()
            return .refused(ShowSceneImportText.nothingInstalled(ShowSceneImportText.saveFailed))
        }
        // Committed: what is left is finished by `recoverInterruptedSceneImport()` if it fails here.
        do {
            try files.write(showBytes, to: showFile)
            try files.remove(importStagingFolder)
            try files.remove(importJournalFile)
        } catch {
            // The scenes are in place; the show and clean-up are completed at the next recovery.
        }
        return .installed(list, finals)
    }

    /// FILE-004 research D4: completes or undoes a scene install the app did not finish. A "prepared"
    /// journal is rolled back (replaced scenes restored exactly, added files removed); a "committed" one
    /// is rolled forward (the show written, the backups removed). A staging folder without a journal is
    /// removed. Returns true when it changed anything. Call before `load()`.
    @discardableResult
    public func recoverInterruptedSceneImport() -> Bool {
        recoverInterruptedSceneImport(fault: nil)
    }

    func recoverInterruptedSceneImport(fault: ((ShowSceneImportFileOperation, URL) throws -> Void)?) -> Bool {
        let manager = FileManager.default
        let files = SceneImportFiles(fault: fault)
        guard let data = try? Data(contentsOf: importJournalFile) else {
            guard manager.fileExists(atPath: importStagingFolder.path) else { return false }
            try? files.remove(importStagingFolder)
            return true
        }
        guard let journal = try? JSONDecoder().decode(ShowSceneImportJournal.self, from: data), journal.version == 1 else {
            return false   // never guessed: planning refuses until this is resolved
        }
        if journal.phase == "committed" {
            if let encoded = journal.show, let show = Data(base64Encoded: encoded), (try? Data(contentsOf: showFile)) != show {
                guard (try? files.write(show, to: showFile)) != nil else { return false }
            }
        } else {
            let replaced = Set(journal.replaced)
            for id in journal.added where !replaced.contains(id) && ShowCueList.isSceneID(id) {
                if manager.fileExists(atPath: sceneFile(id).path) { try? files.remove(sceneFile(id)) }
            }
            for id in journal.replaced where ShowCueList.isSceneID(id) && manager.fileExists(atPath: backupFile(id).path) {
                if manager.fileExists(atPath: sceneFile(id).path) { try? files.remove(sceneFile(id)) }
                guard (try? files.move(backupFile(id), to: sceneFile(id))) != nil else { return false }
            }
            if !journal.scenesFolderExisted { files.removeIfEmpty(scenesFolder) }
        }
        if manager.fileExists(atPath: importStagingFolder.path) { try? files.remove(importStagingFolder) }
        try? files.remove(importJournalFile)
        return true
    }

    private func stagedFile(_ id: String) -> URL {
        importStagingFolder.appendingPathComponent(id + Self.sceneFileSuffix, isDirectory: false)
    }

    private func backupFile(_ id: String) -> URL {
        importBackupFolder.appendingPathComponent(id + Self.sceneFileSuffix, isDirectory: false)
    }
}

/// The single place the scene install touches files (whole writes, renames within the volume).
private struct SceneImportFiles {
    let fault: ((ShowSceneImportFileOperation, URL) throws -> Void)?

    func createDirectory(_ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try fault?(.createDirectory, url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ data: Data, to url: URL) throws {
        try fault?(.write, url)
        try data.write(to: url, options: .atomic)
    }

    func move(_ from: URL, to: URL) throws {
        try fault?(.move, to)
        try FileManager.default.moveItem(at: from, to: to)
    }

    func remove(_ url: URL) throws {
        try fault?(.remove, url)
        try FileManager.default.removeItem(at: url)
    }

    func removeIfEmpty(_ folder: URL) {
        if let items = try? FileManager.default.contentsOfDirectory(atPath: folder.path), items.isEmpty { try? remove(folder) }
    }
}
