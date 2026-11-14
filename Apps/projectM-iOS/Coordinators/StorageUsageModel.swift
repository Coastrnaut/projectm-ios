// StorageUsageModel.swift — FILE-009-R5: measures off the main thread on a detached utility task;
// a newer request or leaving the screen cancels the running one, and a late result is dropped.
// FILE-010-R2, R5, R6: Clear Caches plans off the main thread with the files in use at that moment, asks
// for confirmation, clears off the main thread with the files in use gathered again, then measures again.
// Leaving the screen does not stop a running clear.
// FILE-008-R11: after each measurement, the space the shared photo and video payloads save (logical −
// physical bytes of the content-addressed folders), also off the main thread.
import Foundation
import LocalPortability
import Observation

@MainActor
@Observable
final class StorageUsageModel {
    private(set) var report: StorageReport?
    private(set) var isMeasuring = false
    /// FILE-008-R11: bytes saved by shared media copies (0: nothing shared).
    private(set) var sharedSavings: Int64 = 0

    /// FILE-010: what the cleanup alert shows.
    enum CleanupPrompt: Equatable {
        case confirm(CacheCleanupPlan)
        /// Nothing to clear; `keptInUse`: the only cache files left are in use.
        case nothingToClear(keptInUse: Bool)
    }

    private(set) var cleanupPrompt: CleanupPrompt?
    private(set) var isPlanningCleanup = false
    private(set) var isClearing = false
    /// The last clear's result (the screen's note).
    private(set) var lastCleanup: CacheCleanupResult?

    @ObservationIgnored private let locations: StorageLocations
    @ObservationIgnored private let calculator: StorageUsageCalculator
    @ObservationIgnored private var generation = 0
    /// The running measurement (tests await it).
    @ObservationIgnored private(set) var work: Task<StorageReport, any Error>?
    /// The step that hands the measurement (and the shared savings) to the screen (tests await it).
    @ObservationIgnored private(set) var finishWork: Task<Void, Never>?
    @ObservationIgnored private let cleaner: CacheCleaner
    /// Absolute paths the running app must keep (FILE-010-R5).
    @ObservationIgnored private let filesInUse: @MainActor () -> Set<String>
    /// The running cleanup step, planning or clearing (tests await it).
    @ObservationIgnored private(set) var cleanupWork: Task<Void, Never>?

    init(locations: StorageLocations, calculator: StorageUsageCalculator = StorageUsageCalculator(),
         cleaner: CacheCleaner = CacheCleaner(), filesInUse: @escaping @MainActor () -> Set<String> = { () -> Set<String> in [] }) {
        self.locations = locations
        self.calculator = calculator
        self.cleaner = cleaner
        self.filesInUse = filesInUse
    }

    /// Clear Caches is offered once measured and while nothing else runs.
    var canClearCaches: Bool { report != nil && !isMeasuring && !isPlanningCleanup && !isClearing }

    // MARK: - FILE-010 cache cleanup

    /// Plans the cleanup off the main thread, then shows the confirmation (or "nothing to clear").
    func prepareCleanup() {
        guard !isPlanningCleanup, !isClearing else { return }
        isPlanningCleanup = true
        cleanupPrompt = nil
        let request = locations.cleanupRequest(inUse: filesInUse())
        let cleaner = cleaner
        cleanupWork = Task { @MainActor [weak self] in
            let plan: CacheCleanupPlan? = try? await Task.detached(priority: .utility) { () throws -> CacheCleanupPlan in
                try cleaner.plan(request)
            }.value
            self?.planned(plan)
        }
    }

    func planned(_ plan: CacheCleanupPlan?) {
        isPlanningCleanup = false
        guard let plan else { return }
        cleanupPrompt = plan.isEmpty ? .nothingToClear(keptInUse: !plan.keptInUse.isEmpty) : .confirm(plan)
    }

    /// Cancel (or OK): nothing is removed.
    func dismissCleanup() {
        cleanupPrompt = nil
    }

    /// Clear: removes the confirmed plan's items off the main thread, re-checking the files in use.
    func confirmCleanup(_ plan: CacheCleanupPlan) {
        cleanupPrompt = nil
        guard !isClearing else { return }
        isClearing = true
        lastCleanup = nil
        let inUse = filesInUse()
        let cleaner = cleaner
        cleanupWork = Task { @MainActor [weak self] in
            let result: CacheCleanupResult = await Task.detached(priority: .utility) { () -> CacheCleanupResult in
                cleaner.execute(plan, inUse: inUse)
            }.value
            self?.cleared(result)
        }
    }

    private func cleared(_ result: CacheCleanupResult) {
        isClearing = false
        lastCleanup = result
        refresh()
    }

    /// Cancels any running measurement and starts a new one.
    func refresh() {
        work?.cancel()
        generation += 1
        let current = generation
        isMeasuring = true
        let request = locations.request
        let calculator = calculator
        let folders = locations.mediaFolders
        let work = Task.detached(priority: .utility) { () throws -> StorageReport in try calculator.measure(request) }
        self.work = work
        finishWork = Task { @MainActor [weak self] in
            let result: StorageReport? = try? await work.value
            let saved: Int64 = await Task.detached(priority: .utility) { () -> Int64 in Self.sharedSavings(of: folders) }.value
            self?.finish(result, generation: current, sharedSavings: saved)
        }
    }

    /// Stops the running measurement; the last report stays.
    func cancel() {
        work?.cancel()
        generation += 1
        isMeasuring = false
    }

    /// Only the newest request's result is shown; a cancelled one (nil) changes nothing.
    func finish(_ result: StorageReport?, generation finished: Int, sharedSavings saved: Int64? = nil) {
        guard finished == generation else { return }
        isMeasuring = false
        if let result { report = result }
        if result != nil, let saved { sharedSavings = saved }
    }

    /// FILE-008-R11: logical − physical bytes over the media folders.
    nonisolated static func sharedSavings(of folders: [ContentAddressedMediaFolder]) -> Int64 {
        folders.reduce(Int64(0)) { (sum: Int64, folder: ContentAddressedMediaFolder) -> Int64 in sum + folder.usage().savedBytes }
    }

    /// The generation `finish` accepts (tests).
    var currentGeneration: Int { generation }
}
