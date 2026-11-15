// OfflineExportCoordinator.swift — REC-013 the offline export's state (specs/240-rec-013-deterministic-offline-export;
// R1, R2, R9 to R13, R15; contract C3; research REC-013-D9).
//
// * `start()` captures the job (refusing projectM and media visuals, a bad seed, a missing file or a running export),
//   deletes an offered export, and renders off the main actor into `<tmp>/OfflineExport/<UUID>/`: the audio is loaded
//   (fixture or file), then `OfflineSceneRenderer` writes the MP4 and the checksum sidecar. Progress returns to the
//   main actor after each frame ("Rendering frame N of M").
// * It only reads the live settings; it never writes them, the scene, its snapshots or the undo history (R12).
// * Cancel (a flag read before each frame), a failure or leaving the foreground (D9) deletes the folder: no file
//   remains and nothing is offered. Done deletes the folder; leftovers from a killed app are deleted at init.
// * Save to Photos adds the video through REC-011 (add-only). Messages go to `status` and the library lane (ACC-004).
import Foundation
import Observation
import Synchronization
import VisualBandFeed

/// The export folders (`<tmp>/OfflineExport/<UUID>/`), the only place export files exist.
struct OfflineExportFileStore: Sendable {
    let directory: URL

    init(directory: URL = OfflineExportFileStore.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("OfflineExport", isDirectory: true)
    }

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

/// A flag the render task reads before each frame.
final class OfflineExportCancelFlag: Sendable {
    private let flag = Atomic<Bool>(false)
    func set() { flag.store(true, ordering: .relaxed) }
    var isSet: Bool { flag.load(ordering: .relaxed) }
}

/// Renders one export (the real loader and renderer, or a test stand-in).
typealias OfflineExportRender = @Sendable (OfflineExportJob, URL, OfflineExportCancelFlag,
                                           @escaping @Sendable (Int, Int) -> Void) async throws -> OfflineExportResult

@MainActor
@Observable
final class OfflineExportCoordinator {
    enum Phase: Equatable {
        case idle
        case rendering(frame: Int, total: Int)
        case finished
        case cancelled
        case stopped
        case failed(String)
    }

    enum AudioChoice: String, CaseIterable, Identifiable {
        case fixture
        case file

        var id: String { rawValue }
        var title: String { self == .fixture ? "Fixture" : "Audio File" }
    }

    static let cancelledMessage = "Export cancelled"
    static let failedMessage = "Export failed"
    static let stoppedMessage = "Export stopped: the app left the screen."

    private(set) var phase: Phase = .idle
    private(set) var result: OfflineExportResult?
    private(set) var status: String?
    private(set) var isSavingToPhotos = false
    var shape: SnapshotBatchSize = .landscape
    var rate: OfflineExportRate = .fps30
    var seedText = "1"
    var audioChoice: AudioChoice = .fixture
    /// The picked file (Audio File).
    var audioFile: URL?

    @ObservationIgnored weak var settings: AppSettings?
    @ObservationIgnored weak var photos: PhotosSaveCoordinator?
    @ObservationIgnored var announce: (String) -> Void = { (_: String) -> Void in }
    /// DEBUG and the UI test: the fixture's length (`-uitestOfflineExportSeconds`).
    @ObservationIgnored var fixtureSeconds = Double(OfflineFixtureAudioLength.seconds)
    @ObservationIgnored let store: OfflineExportFileStore
    @ObservationIgnored private let render: OfflineExportRender
    @ObservationIgnored private(set) var folder: URL?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cancelFlag = OfflineExportCancelFlag()
    @ObservationIgnored private var stopRequested = false

    init(store: OfflineExportFileStore = OfflineExportFileStore(), render: OfflineExportRender? = nil) {
        self.store = store
        self.render = render ?? OfflineExportCoordinator.realRender()
        store.removeLeftovers()   // a killed app may have left an export
    }

    /// The audio, then the renderer (one renderer per process, created on first use).
    nonisolated static func realRender() -> OfflineExportRender {
        let box = OfflineRendererBox()
        return { @Sendable (job: OfflineExportJob, folder: URL, cancel: OfflineExportCancelFlag,
                            progress: @escaping @Sendable (Int, Int) -> Void) async throws -> OfflineExportResult in
            let audio: OfflineAudio = try OfflineAudioLoader.load(job)
            return try await box.renderer().export(job: job, audio: audio.samples, folder: folder,
                                                   isCancelled: { () -> Bool in cancel.isSet }, progress: progress)
        }
    }

    var isRendering: Bool {
        if case .rendering = phase { return true }
        return false
    }

    /// The shown visual can be exported (D3).
    var visualSupported: Bool { settings.map { (s: AppSettings) -> Bool in s.visual.isNative } ?? false }

    /// "Rendering frame 12 of 60".
    var progressText: String? {
        guard case let .rendering(frame, total) = phase else { return nil }
        return "Rendering frame " + String(min(frame + 1, total)) + " of " + String(total)
    }

    var progressFraction: Double {
        guard case let .rendering(frame, total) = phase, total > 0 else { return 0 }
        return Double(frame) / Double(total)
    }

    /// The finished export's files (video, sidecar).
    var files: [URL] { result.map { (r: OfflineExportResult) -> [URL] in [r.video, r.sidecar] } ?? [] }

    // MARK: - Export

    /// Captures the job (R2) or returns why not.
    func makeJob() -> Result<OfflineExportJob, OfflineExportRefusal> {
        if isRendering { return .failure(.busy) }
        guard let settings else { return .failure(.unsupportedVisual) }
        let audio: OfflineExportAudioSource? = audioChoice == .fixture ? .fixture : audioFile.map(OfflineExportAudioSource.file)
        return OfflineExportPlanner.job(settings: settings, shape: shape, rate: rate, seedText: seedText, audio: audio,
                                        fixtureSeconds: fixtureSeconds)
    }

    /// Export: nil when it started, else the refusal (also in `status` and announced).
    @discardableResult
    func start() -> OfflineExportRefusal? {
        switch makeJob() {
        case let .success(job):
            start(job)
            return nil
        case let .failure(refusal):
            report(refusal.message)
            return refusal
        }
    }

    /// Renders a captured job (tests pass tiny jobs here).
    func start(_ job: OfflineExportJob) {
        guard !isRendering else { return }
        discardExport()   // a new export replaces an offered one
        let folder: URL
        do {
            folder = try store.newFolder()
        } catch {
            fail("\(error)")
            return
        }
        self.folder = folder
        let flag = OfflineExportCancelFlag()
        cancelFlag = flag
        stopRequested = false
        status = nil
        phase = .rendering(frame: 0, total: 0)
        let render: OfflineExportRender = render
        let target = OfflineExportProgressTarget(self)
        let progress: @Sendable (Int, Int) -> Void = { (done: Int, total: Int) -> Void in
            Task { @MainActor () -> Void in target.coordinator?.advance(done: done, total: total) }
        }
        task = Task { @MainActor [weak self] () -> Void in
            let outcome: Result<OfflineExportResult, Error> = await Task.detached(priority: .utility) { () -> Result<OfflineExportResult, Error> in
                do {
                    return .success(try await render(job, folder, flag, progress))
                } catch {
                    return .failure(error)
                }
            }.value
            self?.finish(outcome, folder: folder)
        }
    }

    private func advance(done: Int, total: Int) {
        guard isRendering else { return }
        phase = .rendering(frame: done, total: total)
    }

    private func finish(_ outcome: Result<OfflineExportResult, Error>, folder: URL) {
        task = nil
        switch outcome {
        case let .success(made) where !cancelFlag.isSet:
            result = made
            phase = .finished
            report("Exported \(made.manifest.frameCount) frames")
        case .success, .failure(OfflineExportError.cancelled):
            store.remove(folder)
            self.folder = nil
            phase = stopRequested ? .stopped : .cancelled
            report(stopRequested ? Self.stoppedMessage : Self.cancelledMessage)
        case .failure(OfflineAudioError.unreadable):
            fail(OfflineAudioError.unreadableMessage, message: OfflineAudioError.unreadableMessage)
        case .failure(OfflineExportError.audioTooShort):
            fail(OfflineExportError.tooShortMessage, message: OfflineExportError.tooShortMessage)
        case let .failure(error):
            fail("\(error)")
        }
    }

    /// Cancel: stops before the next frame and deletes the folder; nothing is offered.
    func cancel() {
        guard isRendering else { return }
        cancelFlag.set()
    }

    /// D9: the app left the foreground (iOS forbids GPU work in the background).
    func sceneLeftForeground() {
        guard isRendering else { return }
        stopRequested = true
        cancelFlag.set()
    }

    /// Awaits the running export (tests).
    func waitForExport() async {
        await task?.value
    }

    /// Done: the export's folder is deleted and the sheet returns to the start.
    func done() {
        if isRendering {
            cancel()
            return
        }
        discardExport()
        phase = .idle
        status = nil
    }

    private func discardExport() {
        store.remove(folder)
        folder = nil
        result = nil
    }

    private func fail(_ detail: String, message: String = OfflineExportCoordinator.failedMessage) {
        task = nil
        discardExport()
        phase = .failed(detail)
        report(message)
    }

    // MARK: - Save to Photos (R11)

    func saveVideoToPhotos() {
        guard phase == .finished, !isSavingToPhotos, let photos, let video = result?.video else { return }
        isSavingToPhotos = true
        Task { @MainActor [weak self] () -> Void in
            let accepted: Bool = photos.save(.recording(video))
            if accepted { await photos.waitForSave() }
            let outcome: PhotosSaveOutcome? = accepted ? photos.lastOutcome : .failed
            self?.isSavingToPhotos = false
            self?.report(outcome == .saved ? "Saved the video to Photos." : (outcome?.notice ?? PhotosSaveOutcome.failedText))
        }
    }

    private func report(_ message: String) {
        status = message
        announce(message)
    }
}

/// The coordinator, weakly, for progress sent from the render task (read on the main actor only).
private final class OfflineExportProgressTarget: @unchecked Sendable {
    weak var coordinator: OfflineExportCoordinator?
    init(_ coordinator: OfflineExportCoordinator) { self.coordinator = coordinator }
}

/// Creates the renderer on first use, from whichever task renders first.
private final class OfflineRendererBox: @unchecked Sendable {
    private let lock = NSLock()
    private var made: OfflineSceneRenderer?

    func renderer() throws -> OfflineSceneRenderer {
        try lock.withLock { () throws -> OfflineSceneRenderer in
            if let made { return made }
            let renderer = try OfflineSceneRenderer()
            made = renderer
            return renderer
        }
    }
}

// MARK: - Wiring (shared by the app and OfflineExportAcceptanceTests)

extension OfflineExportCoordinator {
    func connect(settings: AppSettings, photos: PhotosSaveCoordinator?, announce: @escaping (String) -> Void) {
        self.settings = settings
        self.photos = photos
        self.announce = announce
    }
}
