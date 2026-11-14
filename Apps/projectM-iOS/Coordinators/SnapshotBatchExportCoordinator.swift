// SnapshotBatchExportCoordinator.swift — REC-002 image batch export (specs/234-rec-002-image-batch-export; R1 to R12;
// contract B2, B4; research REC-002-D1, D7 to D9).
//
// * `prepare()` (the sheet opened) reloads the snapshots and selects every usable one. `start()` refuses while Compare
//   is active, for a non-native visual, with nothing selected or while a batch renders; otherwise it captures the job
//   (R12), deletes the previous batch folder and renders each image off the main actor with `SnapshotStillRenderer`
//   into `<tmp>/SnapshotBatch/<UUID>/<file name>`. Progress is published after each image.
// * It only reads the live state (`AppSettings`, the snapshot list); it never calls the snapshot coordinator's
//   `write` or `store`, the autosave or the history (D1), so it works while the scene is locked (R9).
// * Cancel is checked before each image (D9); Cancel or a failure deletes the folder, so no file remains and nothing
//   is offered (R7). Done deletes the folder; leftovers from a killed app are deleted at init (R6, D7).
// * Save to Photos goes through REC-011's coordinator, one image after the other, stopping at the first refusal or
//   failure ("Saved 2 of 5 to Photos." + REC-011's notice; R8). Share… and Save… are presented by the sheet.
// * Messages go to `status` and to the announcer's library lane (ACC-004, R10).
import FrameCapture
import Foundation
import Observation
import ParameterGraph
import SceneFormat

/// The batch folders (`<tmp>/SnapshotBatch/<UUID>/`), the only place batch files exist.
struct SnapshotBatchFileStore: Sendable {
    let directory: URL

    init(directory: URL = SnapshotBatchFileStore.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SnapshotBatch", isDirectory: true)
    }

    /// Deletes every batch folder (a directory listing only: no file dates are read).
    func removeLeftovers() {
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    }

    func newFolder() throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func remove(_ folder: URL?) {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Renders one item to PNG bytes (the real renderer, or a test stand-in).
typealias SnapshotBatchRender = @Sendable (SnapshotBatchJob, SnapshotBatchItem) throws -> Data

@MainActor
@Observable
final class SnapshotBatchExportCoordinator {
    enum Phase: Equatable {
        case idle
        case rendering(done: Int, total: Int)
        case finished
        case cancelled
        case failed(String)
    }

    static let cancelledMessage = "Export cancelled"
    static let failedMessage = "Export failed"

    private(set) var phase: Phase = .idle
    /// The finished batch's files, in order (empty unless `phase == .finished`).
    private(set) var files: [URL] = []
    /// The last message ("Exported 5 images", a refusal, "Saved 2 of 5 to Photos. …").
    private(set) var status: String?
    /// Save to Photos is running.
    private(set) var isSavingToPhotos = false
    /// DEBUG probe and tests: "01-A.png 1920x1080|02-B.png 1920x1080".
    private(set) var probe = ""
    var size: SnapshotBatchSize = .landscape
    var selection: Set<Int> = []

    @ObservationIgnored weak var snapshots: SceneSnapshotCoordinator?
    @ObservationIgnored weak var settings: AppSettings?
    /// REC-011 (nil: Save to Photos unavailable).
    @ObservationIgnored weak var photos: PhotosSaveCoordinator?
    @ObservationIgnored var announce: (String) -> Void = { (_: String) -> Void in }
    /// Tests: runs on the main actor before each image (a cancel here stops before that image is rendered).
    @ObservationIgnored var beforeImage: (Int) -> Void = { (_: Int) -> Void in }
    @ObservationIgnored let store: SnapshotBatchFileStore
    @ObservationIgnored private let render: SnapshotBatchRender
    @ObservationIgnored private(set) var folder: URL?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cancelRequested = false

    init(store: SnapshotBatchFileStore = SnapshotBatchFileStore(), render: SnapshotBatchRender? = nil) {
        self.store = store
        self.render = render ?? SnapshotBatchExportCoordinator.realRender()
        store.removeLeftovers()   // R6: a killed app may have left a batch
    }

    /// One renderer per process, created on first use.
    nonisolated private static func realRender() -> SnapshotBatchRender {
        let box = RendererBox()
        return { @Sendable (job: SnapshotBatchJob, item: SnapshotBatchItem) throws -> Data in
            try box.renderer().render(job: job, item: item)
        }
    }

    var isRendering: Bool {
        if case .rendering = phase { return true }
        return false
    }

    /// "Rendering 2 of 5".
    var progressText: String? {
        guard case let .rendering(done, total) = phase else { return nil }
        return "Rendering " + String(min(done + 1, total)) + " of " + String(total)
    }

    /// The snapshot rows (usable ones selectable).
    var rows: [SceneSnapshotRow] { snapshots?.rows ?? [] }

    /// At least one usable snapshot: the Settings row is enabled.
    var hasUsableSnapshot: Bool { rows.contains { (r: SceneSnapshotRow) -> Bool in r.isUsable } }

    /// The shown visual can be exported (D3).
    var visualSupported: Bool { settings.map { (s: AppSettings) -> Bool in s.visual.isNative } ?? false }

    /// The sheet opened: every usable snapshot selected (unless a batch renders or is offered).
    func prepare() {
        snapshots?.reload()
        guard !isRendering, phase != .finished else { return }
        selection = Set(rows.filter { (r: SceneSnapshotRow) -> Bool in r.isUsable }.map(\.index))
        phase = .idle
        status = nil
    }

    // MARK: - Export

    /// Captures the job (R12) or returns why not.
    func makeJob() -> Result<SnapshotBatchJob, SnapshotBatchRefusal> {
        if isRendering { return .failure(.busy) }
        guard let snapshots, let settings else { return .failure(.unsupportedVisual) }
        if snapshots.isComparing() { return .failure(.comparing) }
        guard let style = SnapshotBatchPlanner.style(for: settings.visual, settings: settings) else { return .failure(.unsupportedVisual) }
        guard let registry = snapshots.registry else { return .failure(.unsupportedVisual) }
        snapshots.reload()
        let items: [SnapshotBatchItem] = SnapshotBatchPlanner.items(entries: snapshots.entries, selection: selection,
                                                                    base: SnapshotRenderValues(settings: settings),
                                                                    registry: registry, settable: Set(snapshots.parameterIDs))
        guard !items.isEmpty else { return .failure(.nothingSelected) }
        return .success(SnapshotBatchJob(visual: settings.visual, style: style, reduceFlashing: settings.effectiveReduceFlashing,
                                         clamp: settings.safetyClamp, size: size, items: items))
    }

    /// Export: nil when the batch started, else the refusal (also in `status` and announced).
    @discardableResult
    func start() -> SnapshotBatchRefusal? {
        let job: SnapshotBatchJob
        switch makeJob() {
        case let .success(j): job = j
        case let .failure(refusal):
            report(refusal.message)
            return refusal
        }
        discardBatch()   // a new export replaces an offered batch
        let folder: URL
        do {
            folder = try store.newFolder()
        } catch {
            fail("\(error)")
            return nil
        }
        self.folder = folder
        cancelRequested = false
        status = nil
        phase = .rendering(done: 0, total: job.items.count)
        let render: SnapshotBatchRender = render
        task = Task { @MainActor [weak self] () -> Void in
            await self?.run(job, folder: folder, render: render)
        }
        return nil
    }

    private func run(_ job: SnapshotBatchJob, folder: URL, render: @escaping SnapshotBatchRender) async {
        var written: [URL] = []
        var probes: [String] = []
        for item in job.items {
            beforeImage(item.position)
            if cancelRequested { break }
            let url: URL = folder.appendingPathComponent(item.fileName)
            let outcome: Result<String, Error> = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
                Result { () throws -> String in
                    let data: Data = try render(job, item)
                    try data.write(to: url, options: .atomic)
                    let info: String = FrameImageEncoder.inspect(data).map { (i: FrameImageInfo) -> String in
                        String(i.width) + "x" + String(i.height)
                    } ?? "unreadable"
                    return item.fileName + " " + info
                }
            }.value
            switch outcome {
            case let .success(line):
                written.append(url)
                probes.append(line)
                phase = .rendering(done: item.position, total: job.items.count)
            case let .failure(error):
                fail("\(error)")
                return
            }
        }
        task = nil
        if cancelRequested {
            store.remove(folder)
            self.folder = nil
            phase = .cancelled
            report(Self.cancelledMessage)
            return
        }
        files = written
        probe = probes.joined(separator: "|")
        phase = .finished
        report(written.count == 1 ? "Exported 1 image" : "Exported \(written.count) images")
    }

    /// Cancel: stops before the next image, deletes the folder; nothing is offered (R7).
    func cancel() {
        guard isRendering else { return }
        cancelRequested = true
    }

    /// Awaits the running batch (tests).
    func waitForBatch() async {
        await task?.value
    }

    /// Done: the batch's folder is deleted and the sheet returns to the start.
    func done() {
        if isRendering {
            cancel()
            return
        }
        discardBatch()
        phase = .idle
        status = nil
    }

    private func discardBatch() {
        store.remove(folder)
        folder = nil
        files = []
        probe = ""
    }

    private func fail(_ detail: String) {
        task = nil
        discardBatch()
        phase = .failed(detail)
        report(Self.failedMessage)
    }

    // MARK: - Save to Photos (R8)

    /// Adds every image, one after the other; stops at the first refusal or failure.
    func saveAllToPhotos() {
        guard phase == .finished, !isSavingToPhotos, let photos, !files.isEmpty else { return }
        isSavingToPhotos = true
        let files: [URL] = files
        Task { @MainActor [weak self] () -> Void in
            var saved = 0
            var notice: String?
            for url in files {
                guard let data = try? Data(contentsOf: url) else {
                    notice = PhotosSaveOutcome.failedText
                    break
                }
                guard photos.save(.frame(data: data, format: .png, name: url.lastPathComponent)) else {
                    notice = PhotosSaveOutcome.failedText
                    break
                }
                await photos.waitForSave()
                guard photos.lastOutcome == .saved else {
                    notice = photos.lastOutcome?.notice ?? PhotosSaveOutcome.failedText
                    break
                }
                saved += 1
            }
            self?.finishPhotos(saved: saved, total: files.count, notice: notice)
        }
    }

    private func finishPhotos(saved: Int, total: Int, notice: String?) {
        isSavingToPhotos = false
        if let notice {
            report("Saved \(saved) of \(total) to Photos. " + notice)
        } else {
            report(total == 1 ? "Saved 1 image to Photos." : "Saved \(total) images to Photos.")
        }
    }

    private func report(_ message: String) {
        status = message
        announce(message)
    }
}

/// Creates the renderer on first use, from whichever task renders first.
private final class RendererBox: @unchecked Sendable {
    private let lock = NSLock()
    private var made: SnapshotStillRenderer?

    func renderer() throws -> SnapshotStillRenderer {
        try lock.withLock { () throws -> SnapshotStillRenderer in
            if let made { return made }
            let renderer = try SnapshotStillRenderer()
            made = renderer
            return renderer
        }
    }
}

// MARK: - Wiring (shared by the app and SnapshotBatchExportAcceptanceTests)

extension SnapshotBatchExportCoordinator {
    func connect(settings: AppSettings, snapshots: SceneSnapshotCoordinator, photos: PhotosSaveCoordinator?,
                 announce: @escaping (String) -> Void) {
        self.settings = settings
        self.snapshots = snapshots
        self.photos = photos
        self.announce = announce
        snapshots.batchExport = self
    }
}
