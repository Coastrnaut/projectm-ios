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

    init(library: UserPresetLibrary, provingPeriod: Duration = PresetImportLimits.provingPeriod,
         announce: @escaping @MainActor (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }) {
        self.library = library
        self.provingPeriod = provingPeriod
        self.announce = announce
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
        guard !isImporting else { return }
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
        guard preset.source != PresetLibrary.userSource, let presets, !isDuplicating else { return }
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
                                             blobHash: preset.hash, requiresLibraryUnlock: pack?.locked ?? false)
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
        presets?.setUserPresets(snapshot.playable.map(\.indexed))
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

    nonisolated static func byteCountText(_ count: Int) -> String {
        "\(PresetImportLimits.grouped(count)) \(count == 1 ? "byte" : "bytes")"
    }
}
