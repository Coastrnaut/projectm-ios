// StorageUsageModel.swift — FILE-009-R5: measures off the main thread on a detached utility task;
// a newer request or leaving the screen cancels the running one, and a late result is dropped.
import Foundation
import LocalPortability
import Observation

@MainActor
@Observable
final class StorageUsageModel {
    private(set) var report: StorageReport?
    private(set) var isMeasuring = false

    @ObservationIgnored private let locations: StorageLocations
    @ObservationIgnored private let calculator: StorageUsageCalculator
    @ObservationIgnored private var generation = 0
    /// The running measurement (tests await it).
    @ObservationIgnored private(set) var work: Task<StorageReport, any Error>?

    init(locations: StorageLocations, calculator: StorageUsageCalculator = StorageUsageCalculator()) {
        self.locations = locations
        self.calculator = calculator
    }

    /// Cancels any running measurement and starts a new one.
    func refresh() {
        work?.cancel()
        generation += 1
        let current = generation
        isMeasuring = true
        let request = locations.request
        let calculator = calculator
        let work = Task.detached(priority: .utility) { () throws -> StorageReport in try calculator.measure(request) }
        self.work = work
        Task { @MainActor [weak self] in
            let result: StorageReport? = try? await work.value
            self?.finish(result, generation: current)
        }
    }

    /// Stops the running measurement; the last report stays.
    func cancel() {
        work?.cancel()
        generation += 1
        isMeasuring = false
    }

    /// Only the newest request's result is shown; a cancelled one (nil) changes nothing.
    func finish(_ result: StorageReport?, generation finished: Int) {
        guard finished == generation else { return }
        isMeasuring = false
        if let result { report = result }
    }

    /// The generation `finish` accepts (tests).
    var currentGeneration: Int { generation }
}
