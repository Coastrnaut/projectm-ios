// BulkPresetImportCoordinator.swift — "Import Folder or Archive…" in My Presets (roadmap PRE-013,
// specs/174-pre-013-bulk-import; PRE-013-R1, R7-R10, R14; contract C4).
//
// The import itself is PresetLibrary's `BulkPresetImporter`, run in a detached task so listing,
// reading, hashing and the static checks never touch the main thread. Its progress values come back
// through an AsyncStream and are consumed here, in order, before the report: the screen shows
// "n of N files" with the running counts; the shared announcer's library lane hears the start, each
// quarter once (25, 50, 75 %) and the summary. Cancel sets a flag the importer reads before each file
// (atomic per file: what was added stays). After the run the waiting presets are tried and My Presets
// is refreshed (`afterImport`, which also invalidates thumbnails as PRE-002 does for any refresh).
// The report lives in memory only (R14).
import Foundation
import Observation
import PresetLibrary
import UniformTypeIdentifiers

/// Read by the importer off the main thread; set by Cancel.
final class BulkImportCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Bool) {
        lock.lock(); value = newValue; lock.unlock()
    }
}

@MainActor
@Observable
final class BulkPresetImportCoordinator {
    /// A folder or a `.zip`.
    static let pickerTypes: [UTType] = [.folder, .zip]

    private(set) var isRunning = false
    private(set) var isCancelling = false
    /// The latest progress while running.
    private(set) var progress: BulkImportProgress?
    /// The last run's report; the summary sheet is shown while it is set.
    var report: BulkImportReport?

    /// The library lane (set by UserPresetsCoordinator).
    @ObservationIgnored var speak: @MainActor (String) -> Void = { (_: String) in }
    /// Runs the waiting trials and refreshes My Presets (set by UserPresetsCoordinator).
    @ObservationIgnored var afterImport: @MainActor () async -> Void = {}
    /// True while another import, archive install or export runs, or the library cannot change.
    @ObservationIgnored var isBlocked: @MainActor () -> Bool = { false }
    @ObservationIgnored var limits: BulkImportLimits = .standard

    @ObservationIgnored private let library: UserPresetLibrary
    @ObservationIgnored private let cancelFlag = BulkImportCancelFlag()
    @ObservationIgnored private var announcedQuarter = 0

    init(library: UserPresetLibrary) {
        self.library = library
    }

    /// "n of N files" for the progress row.
    var progressText: String {
        guard let progress else { return "Preparing the import…" }
        return Self.progressText(progress)
    }

    nonisolated static func progressText(_ progress: BulkImportProgress) -> String {
        let g = PresetImportLimits.grouped
        let counts: BulkImportCounts = progress.counts
        return "\(g(progress.handled)) of \(g(progress.total)) files. Added \(g(counts.added)), skipped \(g(counts.skipped)), failed \(g(counts.failed))."
    }

    /// The Files picker finished. A cancelled picker changes nothing.
    func importPicked(_ result: Result<URL, any Error>) async {
        switch result {
        case .success(let url): await start(BulkImportSource.picked(url))
        case .failure: return
        }
    }

    /// Runs one import and returns its report (nil when another change is running).
    @discardableResult
    func start(_ source: BulkImportSource) async -> BulkImportReport? {
        guard !isRunning, !isBlocked() else { return nil }
        isRunning = true
        isCancelling = false
        progress = nil
        report = nil
        announcedQuarter = 0
        cancelFlag.set(false)
        let (stream, continuation) = AsyncStream.makeStream(of: BulkImportProgress.self, bufferingPolicy: .unbounded)
        let task = Task.detached(priority: .userInitiated) { [library, limits, cancelFlag] () -> BulkImportReport in
            let result = await BulkPresetImporter.run(source, library: library, limits: limits,
                                                      isCancelled: { () -> Bool in cancelFlag.isSet },
                                                      progress: { (value: BulkImportProgress) in continuation.yield(value) })
            continuation.finish()
            return result
        }
        var sourceName = UserPresetName.cleanedFileName(source.url.lastPathComponent)
        for await value in stream { receive(value, sourceName: sourceName) }
        let finished = await task.value
        sourceName = finished.sourceName
        report = finished
        progress = nil
        isRunning = false
        isCancelling = false
        speak(finished.summary)
        await afterImport()
        return finished
    }

    /// Cancel: the file being handled finishes, the waiting batch is saved, the rest are not handled.
    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        cancelFlag.set(true)
    }

    func dismissReport() { report = nil }

    private func receive(_ value: BulkImportProgress, sourceName: String) {
        if value.handled == 1 { speak(BulkImportText.start(sourceName: sourceName, total: value.total)) }
        progress = value
        let quarter: Int = BulkImportText.quarter(handled: value.handled, total: value.total)
        if quarter > announcedQuarter, value.handled < value.total {
            announcedQuarter = quarter
            speak(BulkImportText.progress(percent: quarter * 25, handled: value.handled, total: value.total))
        }
    }
}
