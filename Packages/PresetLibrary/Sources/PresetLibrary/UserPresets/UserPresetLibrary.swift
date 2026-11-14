// UserPresetLibrary.swift — importing presets, quarantine and the trial state machine
// (PRE-012-R2-R6, R14-R20, R24-R27; contracts/user-presets.md).
//
// One imported file moves through these states:
//
//   picked ──refused──▶ (nothing stored)
//   picked ──static check failed──▶ quarantined
//   picked ──ok──▶ pending ──trial passed──▶ playable ──3 s on screen──▶ playable, proven
//                  pending ──trial failed / timed out──▶ quarantined
//                  pending ──no trial possible──▶ pending (tried again later)
//   playable ──failed on the visible renderer──▶ quarantined
//   any ──the app ended during its trial or its first seconds on screen──▶ quarantined at launch
//
// Invariants (tested):
//   1. `data(for:)` returns bytes only for a playable preset. Nothing else hands stored bytes
//      out, so a pending or quarantined file cannot reach a renderer (R20).
//   2. A refusal changes no byte under the directory.
//   3. Before a trial, and before an unproven preset's first load on screen, a record naming the
//      preset is on disk; it is removed when that step ends. A record found at `load()` means
//      the app ended inside the step: the preset is quarantined and never tried again (R17, R18).
//   4. One trial at a time.
//
// PRE-015 (specs/010-pre-015-user-preset-duplication) adds:
//   bundled ──duplicate──▶ pending ──(the same trial)──▶ playable | quarantined
//   playable ──edit──▶ playable with the new text, only after the new text passed the checks
//   copy of a locked pack, entitlement absent ──▶ awaiting unlock (listed, never handed out)
// Invariants (tested):
//   5. `data(for:)` and `editorText(for:)` return nothing for a copy awaiting the unlock (R8).
//   6. A refused or failing edit changes no stored byte; an edit's text is tried before it is
//      stored, with `edit.json` on disk during the trial. That record found at `load()` means
//      the app ended during the check: the edit is dropped, the preset stays as it was (R13).
//
// PRE-014 (specs/012-pre-014-bulk-preset-export) adds `exportPlan()` and `export(ids:…)`: an
// archive of playable presets that were imported or copied from Included presets, written to a
// file the app chose; the store is only read (ADR-0008: copies of full-library presets never
// leave).
import Foundation

/// What an import is compared against. Supplied by the app once the built-in library is loaded.
public struct PresetImportContext: Sendable {
    public struct BuiltIn: Sendable, Equatable {
        public var name: String
        public var pack: String
        public init(name: String, pack: String) {
            self.name = name
            self.pack = pack
        }
    }

    /// Git blob hash → the built-in preset with that content (every pack, locked or not).
    public var builtIn: [String: BuiltIn]
    /// The takedown list (PresetBlocklist.json; ADR-0007).
    public var blockedHashes: Set<String>
    /// Lowercase names, without extension, of the textures shipped with the app.
    public var knownTextures: Set<String>

    public init(builtIn: [String: BuiltIn], blockedHashes: Set<String>, knownTextures: Set<String>) {
        self.builtIn = builtIn
        self.blockedHashes = blockedHashes
        self.knownTextures = knownTextures
    }

    public static let empty = PresetImportContext(builtIn: [:], blockedHashes: [], knownTextures: [])
}

public struct UserPresetSnapshot: Sendable, Equatable {
    /// Alphabetical by name.
    public var playable: [UserPreset]
    /// Passed the static checks, not tried yet; oldest first.
    public var pending: [UserPreset]
    /// Newest first.
    public var quarantined: [UserPreset]
    /// Copies of locked-pack presets while the full library is not unlocked (PRE-015-R8);
    /// alphabetical. Neither playable nor editable.
    public var needsUnlock: [UserPreset]
    public var availability: UserPresetStore.Availability
    public var notice: UserPresetStore.LoadNotice

    public init(playable: [UserPreset], pending: [UserPreset], quarantined: [UserPreset], needsUnlock: [UserPreset] = [],
                availability: UserPresetStore.Availability, notice: UserPresetStore.LoadNotice) {
        self.playable = playable; self.pending = pending; self.quarantined = quarantined; self.needsUnlock = needsUnlock
        self.availability = availability; self.notice = notice
    }

    public static let empty = UserPresetSnapshot(playable: [], pending: [], quarantined: [], availability: .available, notice: .none)
}

public actor UserPresetLibrary {
    private let directory: URL
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String
    private let write: (@Sendable (Data, URL) throws -> Void)?

    private var store: UserPresetStore?
    private var context = PresetImportContext.empty
    private var trial: (any PresetTrialRunning)?
    private var trialInFlight = false
    /// Presets a leftover record names whose quarantine could not be saved: unplayable anyway.
    private var held: Set<String> = []
    /// The full-library entitlement (PRE-015-R8). Copies of locked packs wait for it.
    private var libraryUnlocked = false
    /// Names of presets whose edit was dropped because the app ended during its check (R13).
    private var editNotices: [String] = []
    /// ACC-002: flash risk rules by stored content hash (sha256), so each text is screened once.
    private var flashRiskByContent: [String: [String]] = [:]

    public init(directory: URL,
                now: @escaping @Sendable () -> Date = { Date() },
                makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
                write: (@Sendable (Data, URL) throws -> Void)? = nil) {
        self.directory = directory
        self.now = now
        self.makeID = makeID
        self.write = write
    }

    // MARK: - Loading

    /// Reads the record and deals with records left by a launch that ended inside a trial or a
    /// proving period. Safe to call again.
    @discardableResult
    public func load() -> UserPresetSnapshot {
        if store == nil {
            let created = write.map { UserPresetStore(directory: directory, write: $0) } ?? UserPresetStore(directory: directory)
            store = created
            created.removeLeftoverStaging()   // FILE-003: an archive install the app did not finish
            if let fault = storeFault { created.fileOperationFault = fault }
            for record in created.leftoverRecords() {
                guard let preset = created.preset(id: record.presetID) else {
                    created.clearRecord(record.phase)
                    continue
                }
                if record.phase == .editCheck {
                    // The stored text never changed: only the unchecked edit is dropped (R13).
                    editNotices.append(preset.name)
                    created.clearRecord(.editCheck)
                    continue
                }
                if preset.state == .quarantined {
                    created.clearRecord(record.phase)
                    continue
                }
                let reason = PresetQuarantineReason(record.phase == .trial ? .interruptedDuringCheck : .interruptedOnScreen)
                do {
                    try created.update(preset.id) { $0.state = .quarantined; $0.quarantine = reason }
                    created.clearRecord(record.phase)
                } catch {
                    held.insert(preset.id)   // the record stays; a later launch finishes the quarantine
                }
            }
        }
        return snapshot
    }

    public func setContext(_ context: PresetImportContext) { self.context = context }

    /// The engine-side check. Nil: presets wait unchecked.
    public func setTrial(_ trial: (any PresetTrialRunning)?) { self.trial = trial }

    public var snapshot: UserPresetSnapshot {
        guard let store else { return .empty }
        let visible = store.presets.filter { !held.contains($0.id) }
        let waiting = visible.filter { $0.state != .quarantined && awaitsUnlock($0) }
        let usable = visible.filter { !awaitsUnlock($0) }
        return UserPresetSnapshot(playable: Self.alphabetical(usable.filter { $0.state == .playable }),
                                  pending: usable.filter { $0.state == .pending },
                                  quarantined: visible.filter { $0.state == .quarantined }.reversed(),
                                  needsUnlock: Self.alphabetical(waiting),
                                  availability: store.availability, notice: store.loadNotice)
    }

    private static func alphabetical(_ presets: [UserPreset]) -> [UserPreset] {
        presets.sorted {
            switch $0.name.localizedStandardCompare($1.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return $0.id < $1.id
            }
        }
    }

    /// A copy of a locked-pack preset while the full library is not unlocked (PRE-015-R8).
    private func awaitsUnlock(_ preset: UserPreset) -> Bool {
        preset.duplicateOf?.requiresLibraryUnlock == true && !libraryUnlocked
    }

    /// The stored bytes of a playable preset, and of nothing else (R20; PRE-015-R8).
    public func data(for id: String) -> Data? {
        guard let store = loaded(), !held.contains(id), let preset = store.preset(id: id), preset.state == .playable,
              !awaitsUnlock(preset), let data = store.contents(of: id), data.count == preset.byteCount else { return nil }
        return data
    }

    /// ACC-002-R4: the flash risk rules of every playable preset the screen flags (id → rule ids),
    /// by the same rules as the bundled library (PresetFlashRisk). Unflagged presets are absent.
    /// Each stored text is screened once (cached by its content hash; an edit changes the hash).
    public func flashRisk() -> [String: [String]] {
        var result: [String: [String]] = [:]
        for preset in snapshot.playable {
            let rules: [String]
            if let cached = flashRiskByContent[preset.sha256] {
                rules = cached
            } else {
                guard let data = data(for: preset.id) else { continue }
                rules = PresetFlashRisk.indexField(for: String(decoding: data, as: UTF8.self)) ?? []
                flashRiskByContent[preset.sha256] = rules
            }
            if !rules.isEmpty { result[preset.id] = rules }
        }
        return result
    }

    /// The full-library entitlement changed (PRE-015-R8). Copies of locked packs are held while
    /// it is absent and come back when it returns; nothing is deleted.
    public func setLibraryUnlocked(_ unlocked: Bool) { libraryUnlocked = unlocked }

    /// Names of presets whose edit was dropped because the app ended while checking it (R13).
    /// Each name is returned once.
    public func takeEditNotices() -> [String] {
        defer { editNotices = [] }
        return editNotices
    }

    // MARK: - Import

    /// Imports one picked file. Never throws; every outcome has words for the user.
    public func importFile(at url: URL) async -> PresetImportOutcome {
        guard let store = loaded() else { return .refused(.libraryUnavailable) }
        if case .newerFormat = store.availability { return .refused(.libraryUnavailable) }

        let bytes: [UInt8]
        switch Self.read(url) {
        case .success(let read): bytes = read
        case .failure(let refusal): return .refused(refusal)
        }
        let sha256 = ContentHash.sha256Hex(bytes)
        let blobHash = ContentHash.gitBlobSHA1Hex(bytes)
        if let existing = store.preset(sha256: sha256) {
            if existing.state == .quarantined {
                return .refused(.duplicateOfQuarantined(name: existing.originalFileName, reason: existing.quarantine?.message ?? ""))
            }
            return .refused(.duplicateOfImported(name: existing.name))
        }
        if context.blockedHashes.contains(blobHash) { return .refused(.blocked) }
        if let builtIn = context.builtIn[blobHash] { return .refused(.duplicateOfBuiltIn(name: builtIn.name, pack: builtIn.pack)) }

        let validation = MilkdropPresetValidator.validate(bytes, knownTextures: context.knownTextures)
        let fileName = UserPresetName.cleanedFileName(url.lastPathComponent)
        let names = UserPresetName.displayName(fromFileName: url.lastPathComponent)
        let quarantinedCount = store.presets.filter { $0.state == .quarantined }.count
        if validation.rejection != nil {
            guard quarantinedCount < PresetImportLimits.maxQuarantined else { return .refused(.quarantineFull) }
        } else {
            guard store.presets.count - quarantinedCount < PresetImportLimits.maxUserPresets else { return .refused(.libraryFull) }
        }
        let preset = UserPreset(id: UserPreset.idPrefix + makeID(), name: names.name, author: names.author,
                                originalFileName: fileName, sha256: sha256, blobHash: blobHash, byteCount: bytes.count,
                                importedAt: now(), state: validation.rejection == nil ? .pending : .quarantined,
                                quarantine: validation.rejection, warnings: validation.warnings,
                                license: PresetLicenseMetadata(authorFromFileName: !names.author.isEmpty,
                                                               linesFound: validation.licenseLines))
        do {
            try store.add(preset, contents: Data(bytes))
        } catch {
            return .refused(.saveFailed)
        }
        if preset.state == .quarantined { return .quarantined(preset) }

        await runTrial(of: preset.id)
        guard let current = store.preset(id: preset.id) else { return .waiting(preset) }
        switch current.state {
        case .playable: return .added(current)
        case .quarantined: return .quarantined(current)
        case .pending: return .waiting(current)
        }
    }

    /// Reads at most the size limit plus one byte. The URL's name and location are used for
    /// nothing else (R2-R4). A symbolic link is not followed.
    private static func read(_ url: URL) -> Result<[UInt8], PresetImportRefusal> {
        #if canImport(Darwin)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return .failure(.unreadable) }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { return .failure(.notAFile) }
        guard url.pathExtension.lowercased() == "milk" else { return .failure(.wrongType) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .failure(.unreadable) }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: PresetImportLimits.maxFileBytes + 1) else { return .failure(.empty) }
        if data.isEmpty { return .failure(.empty) }
        if data.count > PresetImportLimits.maxFileBytes { return .failure(.tooLarge) }
        return .success([UInt8](data))
    }

    // MARK: - Trials (R14-R17)

    /// Tries every waiting preset, oldest first, until one cannot be tried now.
    public func runPendingTrials() async {
        guard let store = loaded() else { return }
        for id in store.presets.filter({ $0.state == .pending && !awaitsUnlock($0) }).map(\.id) {
            await runTrial(of: id)
            if store.preset(id: id)?.state == .pending { break }
        }
    }

    private func runTrial(of id: String) async {
        guard let store, let trial, !trialInFlight, !held.contains(id),
              let preset = store.preset(id: id), preset.state == .pending, !awaitsUnlock(preset),
              let data = store.contents(of: id), data.count == preset.byteCount else { return }
        // The record must be on disk before an engine sees the preset; without it, no trial.
        guard (try? store.writeRecord(.trial, presetID: id)) != nil else { return }
        trialInFlight = true
        let result = await trial.run(data, timeout: PresetImportLimits.trialTimeout)
        trialInFlight = false

        guard store.preset(id: id)?.state == .pending else {   // removed while it was tried
            store.clearRecord(.trial)
            return
        }
        let quarantine: PresetQuarantineReason?
        switch result {
        case .passed:
            _ = try? store.update(id) { $0.state = .playable }   // if this cannot be saved it stays waiting
            store.clearRecord(.trial)
            return
        case .unavailable:
            store.clearRecord(.trial)
            return
        case .failed(let message): quarantine = PresetQuarantineReason(.engineRejected, detail: Self.oneLine(message))
        case .timedOut: quarantine = PresetQuarantineReason(.timedOut)
        }
        do {
            try store.update(id) { $0.state = .quarantined; $0.quarantine = quarantine }
            store.clearRecord(.trial)
        } catch {
            held.insert(id)   // unplayable now; the record that stays quarantines it at the next launch
        }
    }

    // MARK: - On the visible renderer (R18, R19)

    /// Call before an unproven preset is loaded on the visible renderer. True when a record was
    /// written and `endProving` must follow; false for a proven or unknown preset, or when the
    /// record cannot be written.
    public func beginProving(_ id: String) -> Bool {
        guard let store = loaded(), let preset = store.preset(id: id), preset.state == .playable, !preset.provenOnScreen,
              !held.contains(id) else { return false }
        return (try? store.writeRecord(.proving, presetID: id)) != nil
    }

    /// The proving period ended. `proven`: the preset drew for the whole period.
    public func endProving(_ id: String, proven: Bool) {
        guard let store = loaded() else { return }
        if proven, store.preset(id: id)?.state == .playable {
            _ = try? store.update(id) { $0.provenOnScreen = true }
        }
        store.clearRecord(.proving)
    }

    /// A playable preset failed to load on the visible renderer (R19).
    public func quarantineOnScreenFailure(_ id: String, message: String) {
        guard let store = loaded(), let preset = store.preset(id: id), preset.state != .quarantined else { return }
        do {
            try store.update(id) {
                $0.state = .quarantined
                $0.quarantine = PresetQuarantineReason(.failedOnScreen, detail: Self.oneLine(message))
            }
        } catch {
            held.insert(id)
        }
        store.clearRecord(.proving)
    }

    // MARK: - Removal (R24)

    /// Deletes a preset or a quarantined file with its stored copy. False when it is unknown or
    /// the change could not be saved.
    @discardableResult
    public func remove(_ id: String) -> Bool {
        guard let store = loaded() else { return false }
        do {
            try store.remove(id)
            held.remove(id)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Export (PRE-014-R2-R6; ADR-0008)

    /// What the Export sheet lists: playable, not held, imported or copied from an Included
    /// preset; and how many records are left out, by reason. Empty while the record is from a
    /// newer app version.
    public func exportPlan() -> UserPresetExportPlan {
        guard let store = loaded(), store.availability == .available else { return .empty }
        var exportable: [UserPreset] = []
        var excluded: [UserPresetExportExclusion: Int] = [:]
        for preset in store.presets {
            if let reason = UserPresetExportPlan.exclusion(of: preset, held: held.contains(preset.id)) {
                excluded[reason, default: 0] += 1
            } else {
                exportable.append(preset)
            }
        }
        return UserPresetExportPlan(exportable: Self.alphabetical(exportable), excluded: excluded)
    }

    /// Writes the archive of the selected presets to `url` (created or replaced). The plan is
    /// applied again here, so an id that is not exportable is never written; an id that no
    /// longer exists is counted as unavailable. On any failure the file is deleted. The store is
    /// only read. Never throws.
    public func export(ids: [String], appVersion: String, exportedAt: Date, to url: URL) -> Result<UserPresetExportSummary, UserPresetExportError> {
        export(ids: ids, appVersion: appVersion, exportedAt: exportedAt, to: url, failAfterWrites: nil)
    }

    /// `failAfterWrites`: tests make the file fail after that many writes (a full disk).
    func export(ids: [String], appVersion: String, exportedAt: Date, to url: URL,
                failAfterWrites: Int?) -> Result<UserPresetExportSummary, UserPresetExportError> {
        guard let store = loaded() else { return .failure(.libraryUnavailable) }
        if case .newerFormat = store.availability { return .failure(.libraryUnavailable) }
        let plan = exportPlan()
        let exportable = Set(plan.exportable.map(\.id))
        var excluded = plan.excluded
        var selected: [UserPreset] = []
        var seen: Set<String> = []
        for id in ids where seen.insert(id).inserted {
            if let preset = store.preset(id: id) {
                if exportable.contains(id) { selected.append(preset) }   // otherwise already counted by the plan
            } else {
                excluded[.unavailable, default: 0] += 1
            }
        }
        guard !selected.isEmpty else { return .failure(.nothingSelected) }

        let files = FileManager.default
        guard files.createFile(atPath: url.path, contents: nil), let handle = try? FileHandle(forWritingTo: url) else {
            try? files.removeItem(at: url)
            return .failure(.writeFailed)
        }
        var writes = 0
        let failure: UserPresetExportError?
        do {
            try UserPresetArchiveWriter.write(selected, appVersion: appVersion, exportedAt: exportedAt,
                                              contents: { store.contents(of: $0.id) },
                                              sink: { data in
                                                  if let limit = failAfterWrites, writes >= limit { throw CocoaError(.fileWriteOutOfSpace) }
                                                  writes += 1
                                                  try handle.write(contentsOf: data)
                                              })
            try handle.synchronize()
            failure = nil
        } catch is UserPresetArchiveWriter.WriteError {
            failure = .contentMismatch
        } catch {
            failure = .writeFailed
        }
        try? handle.close()
        if let failure {
            try? files.removeItem(at: url)
            return .failure(failure)
        }
        return .success(UserPresetExportSummary(exported: selected.count, excluded: excluded, fileName: url.lastPathComponent))
    }

    // MARK: - Duplicating a built-in preset (PRE-015-R2-R7)

    /// Copies a built-in preset into the library. `contents` are the bytes the app read from its
    /// bundle or archive; they must be the preset the index describes. Never throws.
    public func duplicate(_ source: BundledPresetSource, contents: Data) async -> PresetDuplicateOutcome {
        guard let store = loaded() else { return .refused(.libraryUnavailable) }
        if case .newerFormat = store.availability { return .refused(.libraryUnavailable) }
        if source.requiresLibraryUnlock && !libraryUnlocked { return .refused(.locked) }
        let bytes = [UInt8](contents)
        guard !bytes.isEmpty, ContentHash.gitBlobSHA1Hex(bytes) == source.blobHash.lowercased() else {
            return .refused(.sourceMismatch)
        }
        let blobHash = source.blobHash.lowercased()
        if context.blockedHashes.contains(blobHash) { return .refused(.blocked) }
        let sha256 = ContentHash.sha256Hex(bytes)
        if let existing = store.preset(sha256: sha256) {
            if existing.state == .quarantined {
                return .refused(.alreadyInQuarantine(name: existing.name, reason: existing.quarantine?.message ?? ""))
            }
            return .refused(.alreadyCopied(name: existing.name))
        }
        guard bytes.count <= PresetImportLimits.maxFileBytes else { return .refused(.invalid(reason: PresetImportRefusal.tooLarge.message)) }
        let validation = MilkdropPresetValidator.validate(bytes, knownTextures: context.knownTextures)
        if let rejection = validation.rejection { return .refused(.invalid(reason: rejection.message)) }
        let quarantinedCount = store.presets.filter { $0.state == .quarantined }.count
        guard store.presets.count - quarantinedCount < PresetImportLimits.maxUserPresets else { return .refused(.libraryFull) }

        let name = UserPresetName.copyName(of: UserPresetName.cleanedName(source.name), taken: store.presets.map(\.name))
        let origin = PresetDuplicateOrigin(
            presetID: String(source.id.prefix(PresetDuplicateOrigin.maxIDCharacters)),
            name: String(UserPresetName.cleanedName(source.name).prefix(PresetImportLimits.maxNameCharacters)).isEmpty
                ? "Preset" : UserPresetName.cleanedName(source.name),
            packID: String(source.packID.prefix(PresetImportLimits.maxNameCharacters)),
            packTitle: String(source.packTitle.prefix(PresetImportLimits.maxNameCharacters)),
            sha256: sha256, blobHash: blobHash, licenseStatement: source.licenseStatement,
            requiresLibraryUnlock: source.requiresLibraryUnlock)
        let preset = UserPreset(id: UserPreset.idPrefix + makeID(), name: name,
                                author: UserPresetName.cleanedName(source.author),
                                originalFileName: UserPresetName.cleanedFileName(source.fileName), sha256: sha256, blobHash: blobHash,
                                byteCount: bytes.count, importedAt: now(), state: .pending, warnings: validation.warnings,
                                license: PresetLicenseMetadata(origin: .bundledDuplicate, rightsVerified: false, authorFromFileName: false,
                                                               linesFound: validation.licenseLines),
                                duplicateOf: origin)
        do {
            try store.add(preset, contents: contents)
        } catch {
            return .refused(.saveFailed)
        }
        await runTrial(of: preset.id)
        guard let current = store.preset(id: preset.id) else { return .waiting(preset) }
        switch current.state {
        case .playable: return .added(current)
        case .quarantined: return .quarantined(current)
        case .pending: return .waiting(current)
        }
    }

    // MARK: - Editing (PRE-015-R9-R15)

    /// The current text of a preset the user can edit: playable, not awaiting the unlock.
    public func editorText(for id: String) -> PresetEditorText? {
        guard let preset = loaded()?.preset(id: id), let data = data(for: id) else { return nil }
        return PresetEditorText.decode(data, sha256: preset.sha256)
    }

    /// Saves a new name and, when `text` is not nil, a new text. `expectedSHA256` is the text the
    /// editor opened. A new text is checked statically and tried on the off-screen engine
    /// before it replaces the stored one; nothing is stored otherwise. Never throws.
    public func edit(_ id: String, name: String, text: String?, expectedSHA256: String) async -> PresetEditOutcome {
        guard let store = loaded() else { return .refused(.libraryUnavailable) }
        if case .newerFormat = store.availability { return .refused(.libraryUnavailable) }
        guard let preset = store.preset(id: id), preset.state == .playable, !held.contains(id) else { return .refused(.notEditable) }
        if awaitsUnlock(preset) { return .refused(.needsUnlock) }
        guard preset.sha256 == expectedSHA256 else { return .refused(.changedMeanwhile) }
        let newName = UserPresetName.cleanedName(name)
        guard !newName.isEmpty else { return .refused(.emptyName) }

        var newBytes: [UInt8]?
        if let text {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .refused(.emptyText) }
            let bytes = Array(text.utf8)
            guard bytes.count <= PresetImportLimits.maxFileBytes else { return .refused(.tooLarge) }
            if let stored = store.contents(of: id), [UInt8](stored) == bytes {
                newBytes = nil
            } else {
                newBytes = bytes
            }
        }
        guard let bytes = newBytes else {
            guard newName != preset.name else { return .unchanged }
            let stamp = now()
            do {
                try store.update(id) { $0.name = newName; $0.modifiedAt = stamp }   // a rename is not tried (R15)
            } catch {
                return .refused(.saveFailed)
            }
            return store.preset(id: id).map { .saved($0) } ?? .refused(.changedMeanwhile)
        }

        let blobHash = ContentHash.gitBlobSHA1Hex(bytes)
        let sha256 = ContentHash.sha256Hex(bytes)
        if context.blockedHashes.contains(blobHash) { return .refused(.blocked) }
        if let builtIn = context.builtIn[blobHash], blobHash != preset.duplicateOf?.blobHash {
            return .refused(.sameAsBuiltIn(name: builtIn.name, pack: builtIn.pack))
        }
        if let other = store.preset(sha256: sha256), other.id != id {
            return .refused(.sameAsUserPreset(name: other.state == .quarantined ? other.originalFileName : other.name))
        }
        let validation = MilkdropPresetValidator.validate(bytes, knownTextures: context.knownTextures)
        if let rejection = validation.rejection { return .refused(.invalid(reason: rejection.message)) }
        guard let trial, !trialInFlight else { return .refused(.checkUnavailable) }
        // The record must be on disk before an engine sees the new text (R13).
        guard (try? store.writeRecord(.editCheck, presetID: id, candidateSHA256: sha256)) != nil else { return .refused(.saveFailed) }
        trialInFlight = true
        let result = await trial.run(Data(bytes), timeout: PresetImportLimits.trialTimeout)
        trialInFlight = false
        defer { store.clearRecord(.editCheck) }

        guard let current = store.preset(id: id), current.sha256 == expectedSHA256, current.state == .playable,
              !held.contains(id) else { return .refused(.changedMeanwhile) }
        switch result {
        case .passed: break
        case .failed(let message): return .refused(.checkFailed(message: Self.oneLine(message)))
        case .timedOut: return .refused(.checkTimedOut)
        case .unavailable: return .refused(.checkUnavailable)
        }
        var updated = current
        updated.name = newName
        updated.sha256 = sha256
        updated.blobHash = blobHash
        updated.byteCount = bytes.count
        updated.warnings = validation.warnings
        updated.license.linesFound = validation.licenseLines
        updated.provenOnScreen = false
        updated.modifiedAt = now()
        do {
            try store.replaceContents(id, with: updated, contents: Data(bytes))
        } catch {
            return .refused(.saveFailed)
        }
        return .saved(updated)
    }

    // MARK: - Archive import (FILE-003)

    /// FILE-003 tests: a fault injected before store file operations (see `UserPresetStore`).
    private var storeFault: (@Sendable (UserPresetStore.FileOperation, URL) throws -> Void)?

    func setStoreFault(_ fault: (@Sendable (UserPresetStore.FileOperation, URL) throws -> Void)?) {
        storeFault = fault
        store?.fileOperationFault = fault
    }

    /// FILE-003-R2-R7 (contract C2): the dry run of an archive against the library as it is now.
    /// Reads only (the first call loads the record, as every entry point does).
    public func planArchiveImport(_ data: Data, policy: PresetArchiveConflictPolicy = .keepBoth) -> PresetArchiveImportPlan {
        guard let store = loaded(), store.availability == .available else {
            return PresetArchiveImportPlan(archiveSHA256: ContentHash.sha256Hex([UInt8](data)), policy: policy,
                                           refusal: PresetImportRefusal.libraryUnavailable.message, entries: [])
        }
        return PresetArchiveImportPlanner.plan(archive: data, library: store.presets, context: context, policy: policy)
    }

    /// FILE-003-R8-R10: plans again; a different plan is returned as `.changed` with nothing written.
    /// Otherwise adds exactly the plan's presets, waiting for their trial, all or nothing. The
    /// caller runs the trials (`runPendingTrials`).
    public func installArchive(_ data: Data, plan: PresetArchiveImportPlan) -> PresetArchiveInstallOutcome {
        let current = planArchiveImport(data, policy: plan.policy)
        guard current == plan else { return .changed(current) }
        if let refusal = plan.refusal { return .refused(PresetArchiveText.nothingInstalled(refusal)) }
        guard plan.canInstall, let store = loaded(), let archive = try? UserPresetArchiveReader.read(data) else {
            return .refused(PresetArchiveText.nothingToInstall)
        }
        var records: [String: ExportedUserPreset] = [:]
        for record in archive.manifest.presets { records[record.id] = record }
        let date = now()
        var items: [(preset: UserPreset, contents: Data)] = []
        for entry in plan.entries {
            guard let action = entry.install else { continue }
            guard let record = records[entry.incomingID], let text = archive.texts[entry.incomingID] else {
                return .refused(PresetArchiveText.nothingToInstall)
            }
            // Research FILE-003-D5: the archive's warnings and licence lines are not trusted.
            let validation = MilkdropPresetValidator.validate([UInt8](text), knownTextures: context.knownTextures)
            var preset = record.userPreset(state: .pending)
            preset.id = action.id
            preset.name = action.name
            preset.importedAt = date
            preset.warnings = validation.warnings
            preset.license.linesFound = validation.licenseLines
            preset.license.rightsVerified = false
            items.append((preset, text))
        }
        do {
            try store.addAll(items)
        } catch {
            return .refused(PresetArchiveText.nothingInstalled(PresetArchiveText.saveFailed))
        }
        return .installed(items.map(\.preset))
    }

    // MARK: - Helpers

    private func loaded() -> UserPresetStore? {
        if store == nil { load() }
        return store
    }

    /// An engine message as one bounded line of printable text.
    private static func oneLine(_ message: String) -> String {
        let scalars = message.unicodeScalars.map { scalar -> Character in
            scalar.properties.generalCategory == .control ? " " : Character(scalar)
        }
        return String(String(scalars).trimmingCharacters(in: .whitespaces).prefix(PresetImportLimits.maxDetailCharacters))
    }
}
