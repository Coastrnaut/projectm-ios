// UserPresetsCoordinator.swift — presentation state for the presets the user imported (roadmap
// PRE-012, specs/008-pre-012-preset-import-validation; PRE-012-R1, R14-R19, R24, R28, R29).
//
// The library itself (validation, the stored copies, quarantine, the trial state machine) is
// PresetLibrary's `UserPresetLibrary`. This type lists it for the browser, runs imports, words
// the results, and connects it to the two places an imported preset meets an engine:
//   * the off-screen trial: the renderer's `presetTrial`, wrapped as `PresetTrialRunning`;
//   * the visible renderer: PresetCoordinator tells this type before an imported preset is
//     loaded (`willShow`), after it loaded (`didShow`), when another preset replaces it
//     (`stoppedShowing`) and when its load failed (`failedOnScreen`).
// Only playable presets are ever handed to PresetCoordinator, so nothing that is waiting or
// quarantined can be chosen, stepped to or loaded (R20).
//
// Roadmap PRE-015 (specs/010-pre-015-user-preset-duplication): "Duplicate to My Presets" reads a
// built-in preset's bytes through the loader (bundle file or archive) and hands them to the
// library, which checks them against the index hash and stores a copy; the editor's text is
// saved through the library's checked edit. Copies of locked packs wait for the unlock: the
// entitlement reaches the library through `libraryUnlockChanged` (PRE-015-R7, R8).
//
// Roadmap PRE-014 (specs/012-pre-014-bulk-preset-export): Export writes one archive of the
// selected exportable presets into a private temporary folder, words and announces the summary,
// and hands the file to the share sheet; the folder is deleted when the share sheet closes and
// at the next launch. Copies of full-library presets never leave (ADR-0008); nothing is logged.
//
// Roadmap FILE-003 (specs/105-file-003-import-dry-run): a `.zip` picked in "Import Preset…" is a
// preset archive. It is read once into memory and planned (`UserPresetLibrary.planArchiveImport`)
// without writing anything; the preview sheet shows the plan. Install re-plans and installs exactly
// that plan, all or nothing; Cancel discards it, leaving the library byte-for-byte unchanged.
// Announcements go through the shared announcer's `library` lane (`announceLibrary`).
import Foundation
import Observation
import PresetLibrary
import Rendering
import UIKit

/// What PresetCoordinator tells about imported presets on the visible renderer (a fake in tests).
@MainActor
protocol UserPresetGuarding: AnyObject {
    func willShow(_ preset: IndexedPreset) async
    func didShow(_ preset: IndexedPreset)
    func stoppedShowing(_ preset: IndexedPreset) async
    func failedOnScreen(_ preset: IndexedPreset, message: String) async
    /// The full-library entitlement changed; called before the scope changes (PRE-015-R8).
    func libraryUnlockChanged(_ unlocked: Bool) async
}

/// The renderer's off-screen trial as the library's `PresetTrialRunning`.
struct RendererPresetTrial: PresetTrialRunning {
    let trial: any PresetTrialing

    func run(_ contents: Data, timeout: Duration) async -> PresetTrialResult {
        switch await trial.run(contents, timeout: timeout) {
        case .passed: .passed
        case .failed(let message): .failed(message)
        case .timedOut: .timedOut
        case .unavailable(let reason): .unavailable(reason)
        }
    }
}

/// FILE-003: the archive preview on screen.
struct PresetArchiveReview: Identifiable, Equatable {
    let id = UUID()
    var plan: PresetArchiveImportPlan
    /// The changed-library sentence or why the last Install wrote nothing.
    var notice: String?
    /// DEBUG probe: the library's snapshot digest when the preview opened (empty in Release).
    var digestAtPreview: String
}

@MainActor
@Observable
final class UserPresetsCoordinator: UserPresetGuarding {
    static let pickerFailedText = "The file could not be opened."
    /// Frames the visible renderer must have presented during the proving period.
    static let provingFrames = 30

    /// Playable presets, alphabetical.
    private(set) var playable: [UserPreset] = []
    /// Passed the static checks, not tried by an engine yet.
    private(set) var pending: [UserPreset] = []
    /// Newest first.
    private(set) var quarantined: [UserPreset] = []
    /// True while a picked file is being copied, validated and tried (R28).
    private(set) var isImporting = false
    /// Set when the saved record is from a newer app version; imports are then refused.
    private(set) var unavailableMessage: String?
    /// Set once when an unreadable record was set aside.
    private(set) var notice: String?
    /// The result of the last import when it needs the user's attention; shown as an alert.
    var resultMessage: String?
    /// Copies of locked-pack presets while the library is not unlocked (PRE-015-R8).
    private(set) var needsUnlock: [UserPreset] = []
    /// The result of the last "Duplicate to My Presets"; shown as an alert (PRE-015).
    var duplicateMessage: String?
    /// True while a duplicate is copied, checked and tried.
    private(set) var isDuplicating = false
    /// Set once when an edit was dropped because the app closed while checking it (PRE-015-R13).
    private(set) var editNotice: String?
    /// Reads a built-in preset's bytes (the loader's bundle and archive; tests replace it).
    @ObservationIgnored var bundledData: (@MainActor (IndexedPreset) throws -> Data)?

    @ObservationIgnored private let library: UserPresetLibrary
    @ObservationIgnored private let provingPeriod: Duration
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private weak var presets: PresetCoordinator?
    @ObservationIgnored private var presentedFrames: @MainActor () -> Int = { 0 }
    @ObservationIgnored private var provingID: String?
    @ObservationIgnored private var provingTask: Task<Void, Never>?
    @ObservationIgnored private var loaded = false

    /// What the Export sheet lists and says about the rest (PRE-014-R1, R2).
    private(set) var exportPlan: UserPresetExportPlan = .empty
    /// True while an archive is written (PRE-014-R18).
    private(set) var isExporting = false
    /// The written archive while the share sheet is open (PRE-014-R3, R4).
    private(set) var exportFile: URL?
    /// The last export's summary, shown at the top of the Export sheet (PRE-014-R5).
    private(set) var exportSummary: String?
    /// Why the last export failed (PRE-014-R6).
    private(set) var exportError: String?
    @ObservationIgnored private let exportDirectory: URL
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let appVersion: String

    /// FILE-003: the archive preview, or nil.
    private(set) var archiveReview: PresetArchiveReview?
    /// True while an archive install runs.
    private(set) var isInstallingArchive = false
    /// The previewed archive's bytes (memory only; dropped on Cancel and after Install).
    @ObservationIgnored private var archiveData: Data?
    /// FILE-003-R13: the shared announcer's `library` lane (set by AppCoordinator); `announce` otherwise.
    @ObservationIgnored var announceLibrary: (@MainActor (String) -> Void)?
    /// The folders the library owns (FILE-003 snapshots): the user presets and the collections.
    @ObservationIgnored let libraryRoots: [URL]
    /// DEBUG probe `libraryDigest`: the snapshot digest of `libraryRoots`, kept current while enabled.
    private(set) var libraryDigest = ""
    @ObservationIgnored var tracksLibraryDigest = false

    init(library: UserPresetLibrary, provingPeriod: Duration = PresetImportLimits.provingPeriod,
         announce: @escaping @MainActor (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) },
         exportDirectory: URL = UserPresetsCoordinator.defaultExportDirectory,
         now: @escaping @MainActor () -> Date = { Date() },
         appVersion: String = UserPresetsCoordinator.bundleVersion(.main),
         libraryRoots: [URL] = UserPresetsCoordinator.defaultLibraryRoots) {
        self.library = library
        self.libraryRoots = libraryRoots
        self.provingPeriod = provingPeriod
        self.announce = announce
        self.exportDirectory = exportDirectory
        self.now = now
        self.appVersion = appVersion
    }

    /// The app's library in Application Support (R2).
    static func makeDefault() -> UserPresetsCoordinator {
        UserPresetsCoordinator(library: UserPresetLibrary(directory: UserPresetStore.defaultDirectory()))
    }

    // MARK: - Wiring

    /// Imported presets appear in `presets`' library, load through `loader`, and are guarded on
    /// the visible renderer by this coordinator.
    func connect(presets: PresetCoordinator, loader: RendererPresetLoader) {
        self.presets = presets
        presets.userGuard = self
        loader.userPresetData = { [library] id in await library.data(for: id) }
        bundledData = { [weak loader] preset in
            guard let loader else { throw CocoaError(.featureUnsupported) }
            return try loader.bundledData(for: preset)
        }
    }

    /// Reads the saved record. A preset that was being tried or first shown when the app last
    /// ended is quarantined here (R17, R18), before any list or renderer can see it.
    func load() async {
        if exportFile == nil { removeExportFiles() }   // PRE-014-R4: an earlier launch ended while sharing
        _ = await library.load()
        loaded = true
        let dropped = await library.takeEditNotices()
        if !dropped.isEmpty { editNotice = dropped.map(PresetEditRefusal.interruptedNotice(name:)).joined(separator: "\n") }
        await refresh()
    }

    /// What imports are compared against: the built-in presets' content hashes, the takedown
    /// list and the shipped textures.
    func prepare(library builtIn: PresetLibrary, blockedHashes: Set<String>, knownTextures: Set<String>) async {
        let context = await Task.detached(priority: .utility) {
            var hashes: [String: PresetImportContext.BuiltIn] = [:]
            hashes.reserveCapacity(builtIn.presets.count)
            for preset in builtIn.presets where preset.source != PresetLibrary.userSource && hashes[preset.hash] == nil {
                hashes[preset.hash] = .init(name: preset.name, pack: builtIn.pack(id: preset.source)?.title ?? "Included")
            }
            return PresetImportContext(builtIn: hashes, blockedHashes: blockedHashes, knownTextures: knownTextures)
        }.value
        await library.setContext(context)
    }

    /// `prepare` with the takedown list and the texture names read from the app bundle.
    func prepare(library builtIn: PresetLibrary, bundle: Bundle) async {
        await prepare(library: builtIn, blockedHashes: Self.blockedHashes(in: bundle), knownTextures: Self.textureNames(in: bundle))
    }

    /// The renderer exists: imported presets can now be tried off screen. Presets that waited
    /// are tried at once.
    func rendererReady(trial: (any PresetTrialRunning)?, presentedFrames: @escaping @MainActor () -> Int) async {
        self.presentedFrames = presentedFrames
        await library.setTrial(trial)
        guard trial != nil else { return }
        await library.runPendingTrials()
        await refresh()
    }

    // MARK: - Import (R1, R28)

    /// The Files picker finished. A cancelled picker changes nothing.
    func importPicked(_ result: Result<URL, any Error>) async {
        let url: URL
        switch result {
        case .success(let picked): url = picked
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { resultMessage = Self.pickerFailedText }
            return
        }
        if url.pathExtension.lowercased() == "zip" {   // FILE-003-R1: a preset archive
            await previewArchive(at: url)
            return
        }
        guard !isImporting, !isExporting else { return }
        isImporting = true
        if !loaded { await load() }
        let outcome = await library.importFile(at: url)
        await library.runPendingTrials()   // presets that waited behind this one
        await refresh()
        isImporting = false
        let message = outcome.message(fileName: UserPresetName.cleanedFileName(url.lastPathComponent))
        announce(message)
        if outcome.needsAlert { resultMessage = message }
    }

    /// Removes an imported preset or deletes a quarantined file, with its stored copy (R24).
    func remove(_ preset: UserPreset) async {
        if provingID == preset.id { await abandonProving() }
        if await !library.remove(preset.id) { resultMessage = PresetImportRefusal.saveFailed.message }
        await refresh()
    }

    /// The record of a playable preset, for its information view.
    func record(for preset: IndexedPreset) -> UserPreset? { playable.first { $0.id == preset.id } }

    func dismissNotice() { notice = nil }

    func dismissEditNotice() { editNotice = nil }

    // MARK: - Duplicate (PRE-015-R1-R7)

    /// "Duplicate to My Presets" for a built-in preset. A locked one opens the purchase sheet;
    /// one that failed to load this session is refused; otherwise the outcome is announced and
    /// shown.
    func duplicate(_ preset: IndexedPreset) async {
        guard preset.source != PresetLibrary.userSource, let presets, !isDuplicating, !isExporting else { return }
        if presets.isLocked(preset) {
            presets.requestPurchase()   // R7: like choosing it to play
            return
        }
        let outcome: PresetDuplicateOutcome
        if presets.excludedThisSession.contains(preset.id) {
            outcome = .refused(.notPlayable)
        } else {
            isDuplicating = true
            if !loaded { await load() }
            let pack = presets.library?.pack(id: preset.source)
            let source = BundledPresetSource(id: preset.id, name: preset.name, author: preset.author,
                                             fileName: (preset.path as NSString).lastPathComponent, packID: preset.source,
                                             packTitle: pack?.title ?? preset.source, licenseStatement: pack?.license ?? "",
                                             blobHash: preset.hash,
                                             // Unknown pack metadata: only Included is assumed free.
                                             requiresLibraryUnlock: pack?.locked ?? !preset.isIncluded)
            if let data = try? bundledData?(preset) {
                outcome = await library.duplicate(source, contents: data)
            } else {
                outcome = .refused(.sourceMismatch)
            }
            await refresh()
            isDuplicating = false
        }
        let message = outcome.message(sourceName: preset.name)
        announce(message)
        duplicateMessage = message
    }

    // MARK: - Edit (PRE-015-R9-R17)

    /// The text the editor opens, or nil when the preset cannot be edited now.
    func editorText(for preset: UserPreset) async -> PresetEditorText? {
        await library.editorText(for: preset.id)
    }

    /// Saves the editor's name and text. An unchanged text is not sent again; a new one is
    /// checked and tried before it is stored. The outcome is announced; a preset on screen is
    /// reloaded with its new text.
    func saveEdit(_ preset: UserPreset, name: String, text: String, opened: PresetEditorText) async -> PresetEditOutcome {
        let outcome = await library.edit(preset.id, name: name, text: text == opened.text ? nil : text, expectedSHA256: opened.sha256)
        await refresh()
        if case .saved = outcome { await presets?.reloadIfCurrent(preset.id) }
        announce(outcome.message)
        return outcome
    }

    /// The record of a playable user preset, for Edit from any list.
    func editableRecord(for preset: IndexedPreset) -> UserPreset? {
        guard preset.source == PresetLibrary.userSource else { return nil }
        return playable.first { $0.id == preset.id }
    }

    /// A copy that waits for the unlock was tapped: the purchase sheet (R8).
    func chooseHeld(_ preset: UserPreset) {
        presets?.requestPurchase()
    }

    // MARK: - Export (PRE-014-R1-R6, R18)

    nonisolated static let defaultExportDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PresetExport", isDirectory: true)

    /// FILE-010-R5: what cache cleanup must keep — the export folder while an archive is written, the
    /// archive while its share sheet is open.
    var filesInUse: [URL] {
        var urls: [URL] = []
        if isExporting { urls.append(exportDirectory) }
        if let exportFile { urls.append(exportFile) }
        return urls
    }

    /// Export is offered unless the record is from a newer version or another change runs.
    var canExport: Bool { unavailableMessage == nil && !isImporting && !isDuplicating && !isExporting }

    /// "Not exported: …" for the Export sheet's footer, or nil.
    var exportExclusionText: String? { UserPresetExportExclusion.sentence(exportPlan.excluded) }

    /// Reads what can be exported now. Clears the last summary and error.
    func prepareExport() async {
        if !loaded { await load() }
        exportPlan = await library.exportPlan()
        exportSummary = nil
        exportError = nil
    }

    /// Writes the archive of `ids` and returns its file for the share sheet, or nil (the error
    /// is set and announced). An earlier archive is deleted first.
    func export(ids: [String]) async -> URL? {
        guard canExport else { return nil }
        isExporting = true
        defer { isExporting = false }
        removeExportFiles()
        exportSummary = nil
        exportError = nil
        let date = now()
        let folder = exportDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(Self.exportFileName(for: date))
        let result: Result<UserPresetExportSummary, UserPresetExportError>
        if (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) == nil {
            result = .failure(.writeFailed)
        } else {
            result = await library.export(ids: ids, appVersion: appVersion, exportedAt: date, to: url)
        }
        switch result {
        case .success(let summary):
            exportSummary = summary.message
            exportFile = url
            announce(summary.message)
            #if DEBUG
            copyForUITest(url)
            #endif
            return url
        case .failure(let error):
            removeExportFiles()
            exportError = error.message
            announce(error.message)
            return nil
        }
    }

    /// The share sheet closed, shared or not: the archive is deleted (PRE-014-R4).
    func finishSharing() {
        exportFile = nil
        removeExportFiles()
    }

    private func removeExportFiles() {
        if FileManager.default.fileExists(atPath: exportDirectory.path) { try? FileManager.default.removeItem(at: exportDirectory) }
    }

    #if DEBUG
    /// UserPresetExportUITests: `-uitestExportPresetTo <host path>` receives a copy of the archive
    /// (the simulator shares the Mac's file system). DEBUG builds only.
    private func copyForUITest(_ url: URL) {
        guard let path = UserDefaults.standard.string(forKey: "uitestExportPresetTo") else { return }
        let target = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: url, to: target)
    }
    #endif

    // MARK: - Archive import (FILE-003-R1-R13)

    nonisolated static let defaultLibraryRoots: [URL] = [UserPresetStore.defaultDirectory(), PresetCollectionStore.defaultDirectory()]

    /// The largest archive file read: every preset at the size limit plus the manifest and ZIP records.
    nonisolated static let maxArchiveFileBytes: Int = {
        let texts: Int = PresetImportLimits.maxUserPresets * PresetImportLimits.maxFileBytes
        let overhead: Int = PresetImportLimits.maxIndexBytes + (1 << 20)
        return texts + overhead
    }()

    /// Reads the picked archive once (FILE-003-R2) and opens the preview. Nothing is written.
    func previewArchive(at url: URL) async {
        guard !isImporting, !isExporting, !isInstallingArchive, archiveReview == nil else { return }
        isImporting = true
        if !loaded { await load() }
        let digest = currentDigest()
        let plan: PresetArchiveImportPlan
        switch Self.readArchive(url) {
        case .success(let data):
            archiveData = data
            plan = await library.planArchiveImport(data)
        case .failure(let refusal):
            archiveData = nil
            plan = PresetArchiveImportPlan(archiveSHA256: "", policy: .keepBoth, refusal: refusal.message, entries: [])
        }
        isImporting = false
        archiveReview = PresetArchiveReview(plan: plan, notice: nil, digestAtPreview: digest)
        speak(PresetArchiveText.previewAnnouncement(plan))
    }

    /// Plans again with another conflict policy (FILE-003-R6). FILE-004: this is "Apply to all", so the
    /// per-conflict choices are cleared.
    func setArchivePolicy(_ policy: PresetArchiveConflictPolicy) async {
        guard var review = archiveReview, let data = archiveData, !isInstallingArchive,
              review.plan.policy != policy || !review.plan.overrides.isEmpty else { return }
        review.plan = await library.planArchiveImport(data, policy: policy)
        review.notice = nil
        archiveReview = review
    }

    /// FILE-004-R1, R8: one conflict's choice (by its incoming identifier); plans again. A choice equal
    /// to the default is stored as no override.
    func setArchiveChoice(_ choice: PresetArchiveConflictPolicy, for incomingID: String) async {
        guard var review = archiveReview, let data = archiveData, !isInstallingArchive,
              review.plan.choice(for: incomingID) != choice else { return }
        var overrides: [String: PresetArchiveConflictPolicy] = review.plan.overrides
        overrides[incomingID] = choice == review.plan.policy ? nil : choice
        review.plan = await library.planArchiveImport(data, policy: review.plan.policy, overrides: overrides)
        review.notice = nil
        archiveReview = review
    }

    /// Installs exactly the previewed plan (FILE-003-R8-R10). A changed library shows the new plan;
    /// a failure keeps the preview with the reason; success closes it and runs the trials.
    func installArchive() async {
        guard var review = archiveReview, let data = archiveData, review.plan.canInstall, !isInstallingArchive else { return }
        isInstallingArchive = true
        let outcome = await library.installArchive(data, plan: review.plan)
        isInstallingArchive = false
        switch outcome {
        case .installed(let presets):
            archiveReview = nil
            archiveData = nil
            speak(PresetArchiveText.installed(presets.count, replaced: review.plan.replaceCount))
            await refresh()
            await library.runPendingTrials()
            await refresh()
        case .changed(let plan):
            review.plan = plan
            review.notice = PresetArchiveText.changed
            archiveReview = review
            speak(PresetArchiveText.changed)
        case .refused(let message):
            review.notice = message
            archiveReview = review
            speak(message)
        }
    }

    /// Cancel or a dismissed sheet (FILE-003-R11): the plan and the bytes are dropped; nothing else.
    func cancelArchive() {
        archiveReview = nil
        archiveData = nil
        updateDigest()
    }

    private func speak(_ text: String) {
        if let announceLibrary { announceLibrary(text) } else { announce(text) }
    }

    /// The picked file, read under its security scope and size-checked before reading.
    nonisolated static func readArchive(_ url: URL) -> Result<Data, PresetArchiveReadRefusal> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return .failure(.unreadable) }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { return .failure(.unreadable) }
        let size: Int = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxArchiveFileBytes else { return .failure(.tooLarge) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        return .success(data)
    }

    private func currentDigest() -> String {
        #if DEBUG
        guard tracksLibraryDigest else { return "" }
        return LibraryTreeSnapshot.take(libraryRoots).digest
        #else
        return ""
        #endif
    }

    private func updateDigest() {
        #if DEBUG
        if tracksLibraryDigest { libraryDigest = currentDigest() }
        #endif
    }

    #if DEBUG
    /// PresetArchiveImportUITests: `-uitestPresetArchiveFixture` writes a two-preset archive (one
    /// without licence lines) to a temporary file and opens its preview, as if picked. DEBUG only.
    /// FILE-004 (`-uitestPresetArchiveConflictFixture`): the first preset is named "Seeded Lantern", the
    /// UI test's seeded preset, with another text, so the preview has one name conflict.
    func previewFixtureArchive(conflict: Bool = false) async {
        tracksLibraryDigest = true
        updateDigest()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FILE-003 fixture.zip")
        guard let data = Self.fixtureArchive(firstName: conflict ? "Seeded Lantern" : "Fixture Harbor") else { return }
        try? data.write(to: url, options: .atomic)
        await previewArchive(at: url)
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated static func fixtureArchive(firstName: String = "Fixture Harbor") -> Data? {
        func text(_ tag: String, license: Bool) -> String {
            var lines: [String] = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "PSVERSION_WARP=2", "PSVERSION_COMP=2", "[preset00]"]
            if license { lines.append("// License: CC-BY 4.0, Example Author") }
            lines += ["fRating=3.000000", "fDecay=0.950000", "zoom=1.020000", "rot=0.020000", "nWaveMode=3",
                      "per_frame_1=wave_g = 0.5 + 0.5*sin(time*0.7);", "per_frame_2=wave_b = 0.\(tag.count)*bass;",
                      "per_pixel_1=zoom = zoom + 0.01*sin(rad*4 + time);"]
            return lines.joined(separator: "\n") + "\n"
        }
        let items: [(id: String, name: String, text: String)] = [
            ("user/file003-fixture-harbor", firstName, text("harbor", license: true)),
            ("user/file003-fixture-drift", "Fixture Drift", text("drift", license: false)),
        ]
        var records: [UserPreset] = []
        var texts: [String: Data] = [:]
        for item in items {
            let bytes = [UInt8](item.text.utf8)
            records.append(UserPreset(id: item.id, name: item.name, author: "", originalFileName: item.name + ".milk",
                                      sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes), byteCount: bytes.count,
                                      importedAt: Date(timeIntervalSince1970: 1_800_000_000), state: .playable, provenOnScreen: false,
                                      quarantine: nil, warnings: [],
                                      license: PresetLicenseMetadata(authorFromFileName: false, linesFound: [])))
            texts[item.id] = Data(item.text.utf8)
        }
        var output = Data()
        do {
            try UserPresetArchiveWriter.write(records, appVersion: "fixture", exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                              contents: { (preset: UserPreset) -> Data? in texts[preset.id] },
                                              sink: { (chunk: Data) in output.append(chunk) })
        } catch {
            return nil
        }
        return output
    }
    #endif

    // MARK: - Words (FILE-003)

    nonisolated static func archiveEntryText(_ entry: PresetArchivePlanEntry) -> String {
        switch entry.kind {
        case .new: return entry.incomingName
        case .identical(let existing): return "\(entry.incomingName): the same preset is in My Presets as “\(existing)”."
        case .nameConflict(let existing): return "\(entry.incomingName): same name as “\(existing)”."
        case .idConflict(let existing): return "\(entry.incomingName): same identifier as “\(existing)”."
        case .refused(let refusal): return "\(entry.incomingName): \(refusal.message)"
        }
    }

    /// What the install does to this entry (Keep both's new name or identifier; FILE-004: Replace,
    /// a Replace that fell back, Skip), or nil when it is installed as it is.
    nonisolated static func archiveInstallText(_ entry: PresetArchivePlanEntry) -> String? {
        guard let install = entry.install else {
            return entry.isConflict ? "Left out. Your preset is not changed." : nil
        }
        if let replaced = entry.replaces {
            let named: String = install.name == replaced.name ? "" : " It will be named “\(install.name)”."
            return "Replaces “\(replaced.name)”; collections that list it keep it." + named
        }
        let renamed: Bool = install.name != entry.incomingName
        if entry.fellBack {
            let target: String = renamed ? "as “\(install.name)”" : "as a copy"
            return "Nothing of yours to replace, so it is installed " + target + "."
        }
        guard renamed || install.id != entry.incomingID else { return nil }
        if renamed { return "Installed as “\(install.name)”." }
        return "Installed with a new identifier."
    }

    nonisolated static func policyTitle(_ policy: PresetArchiveConflictPolicy) -> String {
        switch policy {
        case .keepBoth: return "Keep both"
        case .skip: return "Skip"
        case .replace: return "Replace"
        }
    }

    nonisolated static func policyDetail(_ policy: PresetArchiveConflictPolicy) -> String {
        switch policy {
        case .keepBoth: return "Install it as a copy. Your preset is not changed."
        case .skip: return "Leave it out."
        case .replace: return "Your preset takes the imported text and name and keeps its place in collections."
        }
    }

    // MARK: - UserPresetGuarding (R18, R19)

    func willShow(_ preset: IndexedPreset) async {
        if provingID == preset.id { return }   // already being proven
        await abandonProving()
        if await library.beginProving(preset.id) { provingID = preset.id }
    }

    func didShow(_ preset: IndexedPreset) {
        guard provingID == preset.id, provingTask == nil else { return }
        let id = preset.id
        let framesAtStart = presentedFrames()
        provingTask = Task { [weak self, provingPeriod] in
            try? await Task.sleep(for: provingPeriod)
            guard !Task.isCancelled, let self, self.provingID == id else { return }
            let drew = self.presentedFrames() - framesAtStart >= Self.provingFrames
            let stillShown = self.presets?.current?.id == id
            self.provingID = nil
            self.provingTask = nil
            await self.library.endProving(id, proven: drew && stillShown)
            await self.refresh()
        }
    }

    func stoppedShowing(_ preset: IndexedPreset) async {
        if provingID == preset.id { await abandonProving() }
    }

    func libraryUnlockChanged(_ unlocked: Bool) async {
        await library.setLibraryUnlocked(unlocked)
        await library.runPendingTrials()   // copies that waited for the unlock and a check
        await refresh()
    }

    func failedOnScreen(_ preset: IndexedPreset, message: String) async {
        if provingID == preset.id {
            provingTask?.cancel()
            provingTask = nil
            provingID = nil
        }
        await library.quarantineOnScreenFailure(preset.id, message: message)
        await refresh()
    }

    /// Ends a proving period without proof and removes its record: the preset stopped being
    /// shown, or the app is leaving the screen (so a later end of the app is not blamed on it).
    func abandonProving() async {
        guard let id = provingID else { return }
        provingTask?.cancel()
        provingTask = nil
        provingID = nil
        await library.endProving(id, proven: false)
    }

    // MARK: - State

    private func refresh() async {
        let snapshot = await library.snapshot
        playable = snapshot.playable
        pending = snapshot.pending
        quarantined = snapshot.quarantined
        needsUnlock = snapshot.needsUnlock
        presets?.retainedUserPresetIDs = Set((snapshot.pending + snapshot.needsUnlock).map(\.id))
        unavailableMessage = snapshot.availability == .available ? nil : UserPresetText.newerFormat
        if snapshot.notice == .unreadableSetAside, notice == nil, !noticeShown {
            notice = UserPresetText.unreadable
            noticeShown = true
        }
        // ACC-002-R4: imported presets carry the same flash risk flag as the bundled library.
        let flashRisk = await library.flashRisk()
        presets?.setUserPresets(snapshot.playable.map { (preset: UserPreset) -> IndexedPreset in preset.indexed(flash: flashRisk[preset.id]) })
        updateDigest()
    }

    @ObservationIgnored private var noticeShown = false

    // MARK: - Bundle data

    /// The hashes of PresetBlocklist.json (ADR-0007): `{"hashes": [{"hash": "<git blob id>", …}]}`.
    nonisolated static func blockedHashes(in bundle: Bundle) -> Set<String> {
        guard let url = bundle.url(forResource: "PresetBlocklist", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return blockedHashes(from: data)
    }

    nonisolated static func blockedHashes(from data: Data) -> Set<String> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["hashes"] as? [Any] else { return [] }
        var hashes: Set<String> = []
        for entry in entries {
            if let hash = (entry as? [String: Any])?["hash"] as? String { hashes.insert(hash.lowercased()) }
            if let hash = entry as? String { hashes.insert(hash.lowercased()) }
        }
        return hashes
    }

    /// Lowercase names, without extension, of the textures in the bundle's PresetTextures folder.
    nonisolated static func textureNames(in bundle: Bundle) -> Set<String> {
        guard let folder = bundle.resourceURL?.appendingPathComponent("PresetTextures"),
              let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
        var names: Set<String> = []
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            names.insert(url.deletingPathExtension().lastPathComponent.lowercased())
        }
        return names
    }

    // MARK: - Words (R29)

    nonisolated static func myPresetsRowLabel(count: Int) -> String {
        "\(UserPresetText.scopeTitle), \(count) \(count == 1 ? "preset" : "presets")"
    }

    nonisolated static func quarantineRowLabel(count: Int) -> String {
        "Quarantine, \(count) \(count == 1 ? "file" : "files")"
    }

    nonisolated static func quarantinedFileLabel(fileName: String, reason: String) -> String {
        "\(fileName), not playable. \(reason)"
    }

    nonisolated static func pendingLabel(name: String) -> String {
        "\(name), waiting to be checked"
    }

    nonisolated static func heldLabel(name: String) -> String {
        "\(name), needs the full library"
    }

    nonisolated static func originText(_ origin: PresetDuplicateOrigin) -> String {
        "Duplicated from “\(origin.name)” in \(origin.packTitle)."
    }

    nonisolated static let duplicateRightsText =
        "projectM-iOS has not verified any rights beyond the pack's statement. You can edit this copy on this device."

    nonisolated static func exportRowLabel(name: String, selected: Bool) -> String {
        "\(name), \(selected ? "selected" : "not selected")"
    }

    nonisolated static func exportCountText(selected: Int, of total: Int) -> String {
        "\(selected) of \(total) \(total == 1 ? "preset" : "presets") selected"
    }

    /// "projectM-iOS Presets 2026-11-12.zip": the local date, no device or user name.
    nonisolated static func exportFileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "projectM-iOS Presets \(formatter.string(from: date)).zip"
    }

    /// "1.1 (2)" from the bundle; informational only (spec Clarifications).
    nonisolated static func bundleVersion(_ bundle: Bundle) -> String {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    nonisolated static func byteCountText(_ count: Int) -> String {
        "\(PresetImportLimits.grouped(count)) \(count == 1 ? "byte" : "bytes")"
    }
}

/// Why a picked archive was not read (FILE-003-R2).
enum PresetArchiveReadRefusal: Error, Equatable, Sendable {
    case unreadable
    case tooLarge

    var message: String {
        switch self {
        case .unreadable: return "The archive could not be read."
        case .tooLarge:
            return "The archive is larger than \(PresetImportLimits.grouped(UserPresetsCoordinator.maxArchiveFileBytes)) bytes, the most the app reads."
        }
    }
}
