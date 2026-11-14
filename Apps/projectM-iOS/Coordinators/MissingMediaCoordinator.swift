// MissingMediaCoordinator.swift — MED-013 (spec MED-013-R1, R2, R4, R5, R6, R8; research MED-013-D2, D5):
// the Missing Media screen's model and the visualizer's "Missing media" placeholder.
//
// * `refresh` adopts checksum matches first (MED-013-R4), then lists what is still missing.
// * `mediaImported` (after every photo or video import): the same adoption, announced only when it
//   relinked something.
// * Find in folder and Relink… run the service off the main actor; one operation at a time.
// * The placeholder is set when a show cue applies a scene with missing media (never removing a reference)
//   and cleared when the next applied scene has none or its media resolves after a relink.
// * Results and refusals are announced on the announcer's library lane (ACC-004; set by AppCoordinator).
// Main actor; the file work is small and bounded (MediaFolderScan) and runs on a detached task.
import Foundation
import Observation
import SceneFormat
import ShowControl

/// The scene whose media is missing, for the placeholder tile (MED-013-R2).
struct MissingMediaPlaceholder: Equatable, Sendable {
    let sceneName: String
    /// The missing references (store, identifier).
    let missing: [SceneMediaReference]

    /// "Opening: its photo or video is no longer stored".
    var valueText: String { "\(sceneName): its photo or video is no longer stored" }
}

@MainActor
@Observable
final class MissingMediaCoordinator {
    static let emptyText = "No missing media."
    static let busyText = "Working…"

    private(set) var items: [MissingMediaItem] = []
    private(set) var isWorking = false
    /// The last operation's result (shown under the list).
    private(set) var resultText: String?
    private(set) var placeholder: MissingMediaPlaceholder?
    /// The placeholder tile's Relink… opened the screen.
    var showsScreenFromPlaceholder = false

    /// Set once by AppCoordinator (tests pass their own); nil leaves the list empty.
    @ObservationIgnored var service: MediaRelinkService?
    /// The show's cues (cue counts; set by AppCoordinator).
    @ObservationIgnored var cues: () -> ShowCueList = { () -> ShowCueList in ShowCueList() }
    /// ACC-004 library lane (set by AppCoordinator).
    @ObservationIgnored var announce: (String) -> Void = { (_: String) -> Void in }
    #if DEBUG
    /// UI tests: Find Missing Media in Folder… scans this folder instead of opening the picker.
    @ObservationIgnored var fixtureFolder: URL?
    #endif

    init(service: MediaRelinkService? = nil) {
        self.service = service
    }

    // MARK: - List

    /// Adopts checksum matches, then lists what is still missing.
    func refresh() {
        guard let service else { return }
        let before = service.missingItems(cues: cues())
        if !before.isEmpty { _ = service.relinkByChecksum(before) }
        items = service.missingItems(cues: cues())
        updatePlaceholder()
    }

    /// After a photo or video import: matching content relinks automatically (MED-013-R4).
    /// Counts what the import relinked: items listed before (an identifier still registered resolves by
    /// itself once its payload is back) and identifiers adopted now.
    func mediaImported() {
        guard let service else { return }
        let missing = service.missingItems(cues: cues())
        if !missing.isEmpty { _ = service.relinkByChecksum(missing) }
        let before: Set<String> = Set((items + missing).map(\.id))
        let now = service.missingItems(cues: cues())
        let relinked = before.subtracting(now.map(\.id)).count
        items = now
        updatePlaceholder()
        guard relinked > 0 else { return }
        announce(MediaRelinkReport(relinked: relinked).message)
    }

    // MARK: - Find in folder (MED-013-R5)

    var canFindInFolder: Bool { !isWorking && items.contains { (i: MissingMediaItem) -> Bool in i.checksumKnown } }

    #if DEBUG
    /// UI tests only: scans the fixture folder (pickers cannot be automated).
    func findInFixtureFolderIfSet() -> Bool {
        guard let folder = fixtureFolder else { return false }
        Task { await findInFolder(folder) }
        return true
    }
    #endif

    func folderPicked(_ result: Result<URL, any Error>) async {
        switch result {
        case let .success(url): await findInFolder(url)
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled { finish(MediaRelinkError.unreadableFolder.message) }
        }
    }

    func findInFolder(_ url: URL) async {
        guard let service, !isWorking else { return }
        isWorking = true
        let missing = items
        let report: MediaRelinkReport = await Task.detached(priority: .userInitiated) { () -> MediaRelinkReport in
            service.scanFolder(url, items: missing)
        }.value
        isWorking = false
        refresh()
        finish(report.message)
    }

    // MARK: - Replacement (MED-013-R6)

    func replacementPicked(_ item: MissingMediaItem, _ result: Result<URL, any Error>) async {
        switch result {
        case let .success(url): await replace(item, with: url)
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled { finish(MediaRelinkError.unreadableFolder.message) }
        }
    }

    func replace(_ item: MissingMediaItem, with url: URL) async {
        guard let service, !isWorking else { return }
        isWorking = true
        let list = cues()
        let outcome: Result<MediaRelinkReport, MediaRelinkError> = await Task.detached(priority: .userInitiated) {
            () -> Result<MediaRelinkReport, MediaRelinkError> in
            do throws(MediaRelinkError) {
                return .success(try await service.replace(item, with: url, cues: list))
            } catch {
                return .failure(error)
            }
        }.value
        isWorking = false
        refresh()
        switch outcome {
        case let .success(report): finish(report.message)
        case let .failure(error): finish(error.message)
        }
    }

    private func finish(_ text: String) {
        resultText = text
        announce(text)
    }

    // MARK: - Placeholder (MED-013-R2)

    /// A show cue applied `document`; `missingMedia` is SCN-001's `missingAsset` warning.
    func sceneApplied(_ document: SceneDocument, missingMedia: Bool) {
        guard missingMedia, let service else {
            placeholder = nil
            return
        }
        let missing = document.mediaReferences.filter { (r: SceneMediaReference) -> Bool in
            guard let id = UUID(uuidString: r.storeID) else { return false }
            return service.folder(r.store).resolve(id) == nil
        }
        placeholder = missing.isEmpty ? nil : MissingMediaPlaceholder(sceneName: document.name, missing: missing)
    }

    private func updatePlaceholder() {
        guard let current = placeholder, let service else { return }
        let still = current.missing.filter { (r: SceneMediaReference) -> Bool in
            guard let id = UUID(uuidString: r.storeID) else { return false }
            return service.folder(r.store).resolve(id) == nil
        }
        if still.isEmpty {
            placeholder = nil
            return
        }
        // A replacement renamed the identifier in the scene: the old one no longer counts.
        let named: Set<String> = Set(items.map { (i: MissingMediaItem) -> String in i.storeID.uuidString })
        let remaining = still.filter { (r: SceneMediaReference) -> Bool in named.contains(r.storeID) }
        placeholder = remaining.isEmpty ? nil : MissingMediaPlaceholder(sceneName: current.sceneName, missing: remaining)
    }

    func dismissPlaceholder() { placeholder = nil }
}
