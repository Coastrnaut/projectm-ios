// PerformanceStateRecorder.swift — PERF-012 (specs/209-perf-012-performance-report, R7, R8; research PERF-012-D5):
// what the performance report says about the session besides frames.
//
// * The session starts when the recorder is created (app launch, with the coordinator). Time is read from an injected
//   uptime clock (tests) or `ProcessInfo.systemUptime`.
// * The state timeline: thermal state, Low Power Mode, power profile and the governor's frame-rate cap and render scale
//   (`QualityGovernor.current()`), sampled at creation and after each of `QualityGovernor.changeNotifications`, appended
//   only when something changed, at most 200 entries (later changes set `truncated`).
// * Memory: `phys_footprint` (task_info TASK_VM_INFO) and `os_proc_available_memory()`, public APIs; the peak is the
//   largest footprint seen at the overlay refreshes and at export.
// * In memory only: no stored key, no file, nothing sent (PERF-012-R11).
import Darwin
import Diagnostics
import Foundation
import Rendering

/// The current thermal/Low Power/profile/budget state, as the report records it.
struct PerformanceStateReading: Equatable, Sendable {
    var thermal: ThermalLevel
    var lowPower: Bool
    var profile: PowerProfile
    var settings: QualitySettings

    static func current() -> PerformanceStateReading {
        let info = ProcessInfo.processInfo
        return PerformanceStateReading(thermal: ThermalLevel(info.thermalState), lowPower: info.isLowPowerModeEnabled,
                                       profile: PowerProfileState.current, settings: QualityGovernor.current())
    }

    var thermalName: String {
        switch thermal {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        }
    }

    func sample(at seconds: Double) -> PerformanceReport.StateSample {
        PerformanceReport.StateSample(atSeconds: seconds, thermal: thermalName, lowPower: lowPower, profile: profile.rawValue,
                                      maxFramesPerSecond: settings.maxFramesPerSecond, renderScale: settings.renderScale)
    }
}

/// Memory counters of this process (PERF-012-D5).
enum ProcessMemory {
    /// The physical footprint (what jetsam and Xcode's memory gauge use); nil when unavailable.
    static func footprintBytes() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { (pointer: UnsafeMutablePointer<task_vm_info_data_t>) -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { (raw: UnsafeMutablePointer<integer_t>) -> kern_return_t in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : nil
    }

    /// Memory the app can still allocate before it reaches its limit; nil when the OS reports none (0).
    static func availableBytes() -> Int? {
        let available: Int = Int(os_proc_available_memory())
        return available > 0 ? available : nil
    }
}

@MainActor
final class PerformanceStateRecorder {
    private let uptime: () -> TimeInterval
    private let read: () -> PerformanceStateReading
    private let start: TimeInterval
    private(set) var timeline: [PerformanceReport.StateSample] = []
    private(set) var truncated = false
    private(set) var peakFootprintBytes: Int?
    private var observers: [NSObjectProtocol] = []

    init(uptime: @escaping () -> TimeInterval = { () -> TimeInterval in ProcessInfo.processInfo.systemUptime },
         read: @escaping () -> PerformanceStateReading = { () -> PerformanceStateReading in PerformanceStateReading.current() },
         observes: Bool = true) {
        self.uptime = uptime
        self.read = read
        start = uptime()
        sample()
        if observes { observeChanges() }
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Seconds since the session began.
    var elapsedSeconds: Double { max(0, uptime() - start) }

    /// The state now, as a timeline entry.
    func currentSample() -> PerformanceReport.StateSample { read().sample(at: elapsedSeconds) }

    /// Appends the current state when it differs from the last entry.
    func sample() {
        let entry: PerformanceReport.StateSample = currentSample()
        if let last = timeline.last, last.sameState(as: entry) { return }
        guard timeline.count < PerformanceReport.maxTimelineEntries else {
            truncated = true
            return
        }
        timeline.append(entry)
    }

    /// Updates the peak footprint (overlay refreshes and the export); returns the current footprint.
    @discardableResult
    func sampleMemory(footprint: Int? = ProcessMemory.footprintBytes()) -> Int? {
        if let footprint, footprint > (peakFootprintBytes ?? 0) { peakFootprintBytes = footprint }
        return footprint
    }

    private func observeChanges() {
        for name in QualityGovernor.changeNotifications {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] (_: Notification) -> Void in
                MainActor.assumeIsolated { self?.sample() }
            }
            observers.append(observer)
        }
    }
}
