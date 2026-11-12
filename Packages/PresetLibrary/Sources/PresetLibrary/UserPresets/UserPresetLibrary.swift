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
    public var availability: UserPresetStore.Availability
    public var notice: UserPresetStore.LoadNotice

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
            for record in created.leftoverRecords() {
                guard let preset = created.preset(id: record.presetID) else {
                    created.clearRecord(record.phase)
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
        let playable = visible.filter { $0.state == .playable }.sorted {
            switch $0.name.localizedStandardCompare($1.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return $0.id < $1.id
            }
        }
        return UserPresetSnapshot(playable: playable, pending: visible.filter { $0.state == .pending },
                                  quarantined: visible.filter { $0.state == .quarantined }.reversed(),
                                  availability: store.availability, notice: store.loadNotice)
    }

    /// The stored bytes of a playable preset, and of nothing else (R20).
    public func data(for id: String) -> Data? {
        guard let store = loaded(), !held.contains(id), let preset = store.preset(id: id), preset.state == .playable,
              let data = store.contents(of: id), data.count == preset.byteCount else { return nil }
        return data
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
        for id in store.presets.filter({ $0.state == .pending }).map(\.id) {
            await runTrial(of: id)
            if store.preset(id: id)?.state == .pending { break }
        }
    }

    private func runTrial(of id: String) async {
        guard let store, let trial, !trialInFlight, !held.contains(id),
              let preset = store.preset(id: id), preset.state == .pending,
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
