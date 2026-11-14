// LibraryIntegrityCoordinator.swift — roadmap PRE-018 (specs/194-pre-018-integrity-scanner; R1-R14;
// research D4, D6, D8; contracts/library-integrity.md): My Presets › Check Library.
//
// * `check()` copies the reference stores' preset IDs on the main actor, reads the user preset
//   inventory inside UserPresetLibrary (an actor), and runs the pure PresetIntegrityScanner in a
//   detached utility task, so nothing heavy runs on the main thread (R2). One scan or fix at a time.
// * Fixes: removing a dangling reference (the only safe fix; Fix All Safe applies exactly these, R9),
//   Re-import… and Restore from Library (the checksum relink, R7), Move to Quarantine and Remove Preset
//   (the screen confirms first, R10). After every fix the library is checked again (R13).
// * Every result is announced on the shared announcer's library lane (R12). Nothing is stored (R15).
import Foundation
import Observation
import PresetLibrary

@MainActor
@Observable
final class LibraryIntegrityCoordinator {
    /// The last scan's report; nil before the first.
    private(set) var report: PresetIntegrityReport?
    /// The last scan's or fix's sentence (`libraryCheckResult`).
    private(set) var resultText: String = PresetIntegrityText.notChecked
    private(set) var isRunning = false

    /// The shared announcer's library lane (set by AppCoordinator).
    @ObservationIgnored var announce: (String) -> Void = { (_: String) in }
    @ObservationIgnored private weak var presets: PresetCoordinator?
    @ObservationIgnored private weak var userPresets: UserPresetsCoordinator?
    @ObservationIgnored private let limits: PresetIntegrityLimits

    init(presets: PresetCoordinator?, userPresets: UserPresetsCoordinator?, limits: PresetIntegrityLimits = .standard) {
        self.presets = presets
        self.userPresets = userPresets
        self.limits = limits
    }

    /// Edge Cases: not before the library is loaded, never two at once.
    var canCheck: Bool { !isRunning && presets?.library != nil && userPresets != nil }

    var issues: [PresetIntegrityIssue] { report?.issues ?? [] }
    var hasSafeIssues: Bool { !(report?.safeIssues.isEmpty ?? true) }

    // MARK: - Check (R1-R5, R14)

    func check() async {
        guard canCheck else { return }
        isRunning = true
        resultText = PresetIntegrityText.checking
        let found: PresetIntegrityReport = await scan()
        report = found
        isRunning = false
        finish(found.summary)
    }

    private func scan() async -> PresetIntegrityReport {
        guard let presets, let userPresets else { return PresetIntegrityReport(issues: [], presetsChecked: 0, referencesChecked: 0,
                                                                                 incomplete: true, userPresetsUnavailable: false) }
        let references: PresetReferenceSnapshot = presets.integrityReferences()
        let library: PresetLibrary? = presets.library
        let limits: PresetIntegrityLimits = limits
        let inventory: UserPresetIntegrityInventory = await userPresets.library.integrityInventory(limits: limits)
        let task = Task.detached(priority: .utility) { () -> PresetIntegrityReport in
            PresetIntegrityScanner.scan(inventory: inventory, references: references,
                                        isBuiltIn: { (id: String) -> Bool in library?.preset(id: id) != nil }, limits: limits)
        }
        return await task.value
    }

    // MARK: - Fixes (R6-R10, R13)

    /// Fix All Safe: removes every dangling reference and nothing else (R9).
    func fixAllSafe() async {
        guard let report, let presets, !isRunning else { return }
        isRunning = true
        var removed = 0
        var failed = 0
        for issue in report.safeIssues {
            if presets.removeDanglingReference(issue) { removed += 1 } else { failed += 1 }
        }
        var text: String = PresetIntegrityText.removedReferences(removed)
        if failed > 0 { text += " " + PresetIntegrityText.fixFailed }
        await rescan(after: text)
    }

    /// One issue's fix other than Re-import… (which needs a picked file). The screen confirms
    /// Remove Preset and Move to Quarantine before calling (R10).
    func apply(_ action: PresetIntegrityAction, to issue: PresetIntegrityIssue) async {
        guard !isRunning, issue.actions.contains(action), action != .relinkFile else { return }
        isRunning = true
        let text: String = await perform(action, issue)
        await rescan(after: text)
    }

    /// Re-import…: the picked file is accepted only with the record's checksum (R7, MED-013 pattern).
    func relinkPicked(_ issue: PresetIntegrityIssue, _ result: Result<URL, any Error>) async {
        guard !isRunning, issue.kind == .missingFile, let userPresets else { return }
        isRunning = true
        let text: String
        switch result {
        case .failure:
            text = UserPresetsCoordinator.pickerFailedText
        case .success(let url):
            if let data = Self.readPicked(url) {
                text = Self.words(await userPresets.relink(issue.presetID, with: data))
            } else {
                text = PresetIntegrityText.checksumMismatch
            }
        }
        await rescan(after: text)
    }

    /// Relinks with bytes already in hand (tests; the DEBUG seed's stand-in for the picker).
    func relink(_ issue: PresetIntegrityIssue, with data: Data) async {
        guard !isRunning, issue.kind == .missingFile, let userPresets else { return }
        isRunning = true
        let text: String = Self.words(await userPresets.relink(issue.presetID, with: data))
        await rescan(after: text)
    }

    private func perform(_ action: PresetIntegrityAction, _ issue: PresetIntegrityIssue) async -> String {
        guard let presets, let userPresets else { return PresetIntegrityText.fixFailed }
        let name: String = issue.presetName ?? issue.presetID
        switch action {
        case .removeReference:
            return presets.removeDanglingReference(issue) ? PresetIntegrityText.removedReferences(1) : PresetIntegrityText.fixFailed
        case .restoreFromLibrary:
            guard let data = bundledOriginal(of: issue.presetID) else { return PresetIntegrityText.fixFailed }
            return Self.words(await userPresets.relink(issue.presetID, with: data))
        case .moveToQuarantine:
            let moved: Bool = await userPresets.quarantineByUser(issue.presetID, detail: Self.quarantineDetail(issue))
            return moved ? PresetIntegrityText.quarantined(name) : PresetIntegrityText.fixFailed
        case .removePreset:
            return await userPresets.removeForIntegrity(issue.presetID) ? PresetIntegrityText.removed(name) : PresetIntegrityText.fixFailed
        case .relinkFile:
            return PresetIntegrityText.fixFailed
        }
    }

    /// The bundled bytes an unedited copy was made from (PRE-015), read through the loader.
    private func bundledOriginal(of id: String) -> Data? {
        guard let userPresets, let record = userPresets.allRecords.first(where: { (p: UserPreset) -> Bool in p.id == id }),
              let origin = record.duplicateOf, origin.sha256 == record.sha256,
              let bundled = presets?.library?.preset(id: origin.presetID), let read = userPresets.bundledData else { return nil }
        return try? read(bundled)
    }

    private func rescan(after text: String) async {
        let found: PresetIntegrityReport = await scan()
        report = found
        isRunning = false
        finish(text + " " + found.summary)
    }

    private func finish(_ text: String) {
        resultText = text
        announce(text)
    }

    // MARK: - Words

    nonisolated static func words(_ outcome: PresetRelinkOutcome) -> String {
        switch outcome {
        case .restored(let name): PresetIntegrityText.restored(name)
        case .checksumMismatch: PresetIntegrityText.checksumMismatch
        case .notMissing, .unknownPreset, .unavailable, .saveFailed: PresetIntegrityText.fixFailed
        }
    }

    nonisolated static func quarantineDetail(_ issue: PresetIntegrityIssue) -> String {
        switch issue.kind {
        case .missingTexture: "Uses the missing texture “\(issue.detail ?? "")”."
        default: issue.detail ?? issue.title
        }
    }

    /// A picked file's bytes, at most the import size limit; nil when unreadable or larger.
    nonisolated static func readPicked(_ url: URL) -> Data? {
        let scoped: Bool = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= PresetImportLimits.maxFileBytes else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}
