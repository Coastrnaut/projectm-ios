// ScenePackCoordinator.swift — Scene Folders' Export Scene… and Import Scene… (SCN-014-R2, R5 to R10;
// contract specs/187-scn-014-dependency-pack/contracts/scene-pack.md P5).
//
// * Export: the stored scene is read from the show store and packed off the main actor
//   (`SceneArchiveService.export`: media only from the app's folders by store ID, slides included, the path
//   audit). The file goes to the system share sheet; `shareFinished()` removes it (shared or cancelled).
// * Import: the picked file is previewed (`ScenePackImporter.preview`, nothing written); Import adopts the
//   media, then `ShowCoordinator.installImportedScene` adds the scene (a copy under a new ID when the ID is
//   taken) and one cue. A refused install releases only the media this import added. Nothing is applied.
// * Results and refusals are announced on the library lane (`show.announceLibrary`, ACC-004).
// * DEBUG `-uitestScenePackFixture` (research SCN-014-D8): the export is kept as the "picked" file and shown as
//   a status line instead of the share sheet, and Import Scene… reads it instead of opening the picker.
// No networking.
import Foundation
import Observation
import SceneFormat
import ShowControl
import ShowStorage

@MainActor
@Observable
final class ScenePackCoordinator {
    static func exportedMessage(_ name: String) -> String { "Exported \(name)." }
    static func importedMessage(_ name: String, cue: Int) -> String { "Imported \(name) as cue \(cue)." }
    static func alreadyInShowMessage(_ name: String) -> String { "\(name) is already in the show." }
    static let unavailableMessage = "Scene packs are not available: the app's folders could not be opened."

    /// The pack the share sheet offers (nil: no sheet).
    private(set) var shareURL: URL?
    private(set) var isExporting = false
    private(set) var isImporting = false
    /// The preview sheet's content (nil: no sheet).
    private(set) var preview: ScenePackPreview?
    /// The last result or refusal, shown in Scene Folders.
    private(set) var status: String?
    var showPicker = false

    @ObservationIgnored private unowned let show: ShowCoordinator   // the show owns this coordinator
    @ObservationIgnored private let importer: ScenePackImporter?
    @ObservationIgnored private var pickedURL: URL?
    /// DEBUG fixture mode (research SCN-014-D8).
    @ObservationIgnored var keepsExportForImport = false
    @ObservationIgnored private(set) var lastExportCopy: URL?

    init(show: ShowCoordinator, importer: ScenePackImporter?) {
        self.show = show
        self.importer = importer
    }

    /// The app's stores (nil when a folder cannot be named).
    static func makeDefault(show: ShowCoordinator, defaults: UserDefaults) -> ScenePackCoordinator {
        var importer: ScenePackImporter?
        if let photos = try? PhotoStore.defaultDirectory(), let videos = try? VideoStore.defaultDirectory(), let store = show.store,
           let registry = try? SceneArchiveService.appRegistry() {
            let archive = SceneArchiveService(photos: PhotoStore(directory: photos, defaults: defaults),
                                              videos: VideoStore(directory: videos, defaults: defaults), registry: registry)
            importer = ScenePackImporter(archive: archive, show: store)
        }
        return ScenePackCoordinator(show: show, importer: importer)
    }

    var isBusy: Bool { isExporting || isImporting }

    private func finish(_ message: String) {
        status = message
        show.announceLibrary(message)
    }

    // MARK: Export (R1, R2)

    func export(sceneID: String) {
        guard !isBusy else { return }
        guard let importer, let store = show.store else { return finish(Self.unavailableMessage) }
        let document: SceneDocument
        do throws(ShowSceneReadError) {
            document = try store.scene(sceneID).document
        } catch {
            return finish(error.description)
        }
        isExporting = true
        let archive = importer.archive
        Task {
            let result: Result<SceneArchiveExport, SceneArchiveServiceError> = await Task.detached {
                () -> Result<SceneArchiveExport, SceneArchiveServiceError> in
                do throws(SceneArchiveServiceError) {
                    return .success(try archive.export(document))
                } catch {
                    return .failure(error)
                }
            }.value
            isExporting = false
            switch result {
            case let .success(export): exported(export, name: document.name)
            case let .failure(error): finish(error.message)
            }
        }
    }

    private func exported(_ export: SceneArchiveExport, name: String) {
        if keepsExportForImport {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("ScenePackFixture", isDirectory: true)
                .appendingPathComponent(export.fileName, isDirectory: false)
            try? FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: export.url, to: copy)
            lastExportCopy = copy
            importer?.archive.cleanUpExport()
        } else {
            shareURL = export.url
        }
        finish(Self.exportedMessage(name))
    }

    /// The share sheet closed (shared or cancelled): the temporary pack is removed.
    func shareFinished() {
        shareURL = nil
        importer?.archive.cleanUpExport()
    }

    // MARK: Import (R5 to R7, R10)

    /// "Import Scene…": the file picker, or in fixture mode the last exported pack.
    func startImport() {
        guard !isBusy else { return }
        if show.refusedByLock() { return }   // SCN-015-R3: no picker, no media staged while locked
        if keepsExportForImport {
            if let copy = lastExportCopy { picked(copy) }
            return
        }
        showPicker = true
    }

    /// The picker's result: previews the file (nothing is written).
    func picked(_ url: URL) {
        guard let importer else { return finish(Self.unavailableMessage) }
        isImporting = true
        pickedURL = url
        Task {
            let result = await Task.detached { () -> ScenePackPreview in await importer.preview(at: url) }.value
            isImporting = false
            preview = result
            if case let .refused(message) = result.status { show.announceLibrary(message) }
        }
    }

    func cancelImport() {
        preview = nil
        pickedURL = nil
    }

    /// Import in the preview sheet.
    func confirmImport() {
        guard let importer, let preview, preview.canImport, let url = pickedURL, let document = preview.document,
              let plan = preview.showPlan else { return }
        if show.refusedByLock() { return cancelImport() }   // SCN-015: locked after the preview opened
        isImporting = true
        Task {
            let adopted: Result<ScenePackAdoption, SceneArchiveServiceError> = await Task.detached {
                () -> Result<ScenePackAdoption, SceneArchiveServiceError> in
                do throws(SceneArchiveServiceError) {
                    return .success(try await importer.adoptMedia(at: url, preview: preview))
                } catch {
                    return .failure(error)
                }
            }.value
            isImporting = false
            self.preview = nil
            pickedURL = nil
            switch adopted {
            case let .failure(error): finish(error.message)
            case let .success(adoption): install(document, plan: plan, adoption: adoption, importer: importer)
            }
        }
    }

    private func install(_ document: SceneDocument, plan: ShowSceneImportPlan, adoption: ScenePackAdoption, importer: ScenePackImporter) {
        switch show.installImportedScene(document, plan: plan) {
        case let .installed(list, scenes):
            let scene = scenes.first
            let number = scene.flatMap { (s: SceneDocument) -> Int? in
                list.cues.firstIndex { (cue: ShowCue) -> Bool in cue.sceneID == s.id }.map { (i: Int) -> Int in i + 1 }
            } ?? list.cues.count
            finish(Self.importedMessage(scene?.name ?? document.name, cue: number))
        case .changed:
            importer.release(adoption)
            finish(SceneArchiveServiceError.planChanged.message)
        case let .refused(message):
            importer.release(adoption)
            finish(message)
        }
    }

    func dismissStatus() { status = nil }
}
