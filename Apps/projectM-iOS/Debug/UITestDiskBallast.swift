// UITestDiskBallast.swift — DEBUG only (QA-011 Batch 6: REC-015-T17, REC-009-T11). `-uitestDiskBallast <freeMB>` fills
// the volume with one ballast file in Caches until the free space the disk guard reads
// (`volumeAvailableCapacityForImportantUsage`, REC-015) is about <freeMB>; `-uitestDiskBallastGrowMBps <n>` then grows
// it by n MB a second while a recording file exists in `<tmp>/Recordings`, so a real recording meets the real guard
// within seconds instead of minutes. Safety: the ballast never leaves less
// than 200 MB of real free space (`volumeAvailableCapacity`) or less than the guard's 200 MiB reserve, and every DEBUG
// launch deletes a ballast left by an earlier launch first (the tests also relaunch once in tearDown). The probe
// `diskBallast` (with `-uitestDiagnostics`) reads "state=<…> ballastMB=<n> freeMB=<n> realFreeMB=<n> guardMB=<n>
// targetMB=<n>" (freeMB the important-use figure, guardMB the smaller one the disk guard reads);
// state `capped` means the device's purgeable space kept the reading above the target. The readings stay in memory.
// QA-011 pass 3 (D3, 43 GB free): one extension of the whole gap never returned within 300 s and the probe read
// "state=filling ballastMB=0" throughout. The fill now grows in steps of at most `fillStepBytes`, publishes
// "state=filling ballastMB=<n> …" after each step, and ends "state=slow" when `fillBudgetSeconds` pass first.
// QA-011 rerun 4 (D3, 2026-11-19): the fill aimed the important-use reading at 600 MB while it stayed 2.8 GB above the
// real free space (purgeable space the system did not free), so the last step tried to write the real space down to
// the 200 MB floor and never returned ("state=filling ballastMB=74000 freeMB=3755 realFreeMB=946" for 390 s); REC-015
// held at freeMB=606 realFreeMB=209 and the guard never stopped. The guard now reads the smaller of the two
// (`VolumeStorageReading.guardBytes`), and so does the ballast: it fills and grows against `guardMB`, the figure the
// guard reads, and checks its time budget between 16 MB chunks, so one slow write cannot hold it in "filling".
// Not compiled into Release builds.
#if DEBUG
import Foundation
import FrameRecording

@MainActor
@Observable
final class UITestDiskBallast {
    static let shared = UITestDiskBallast()
    static let argument = "-uitestDiskBallast"
    static let growArgument = "-uitestDiskBallastGrowMBps"
    /// Never leave less real free space than this.
    nonisolated static let realFloorBytes: Int64 = 200_000_000
    /// Never grow below the disk guard's reserve (RecordingStoragePolicy.reserveBytes, 200 MiB).
    nonisolated static let reserveBytes: Int64 = 209_715_200
    /// The longest a fill may take before it reports `state=slow` (the device tests wait a little longer).
    nonisolated static let fillBudgetSeconds: Double = 360
    private(set) var value = "state=idle"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    nonisolated static var file: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("QA011-DiskBallast.bin")
    }

    /// A file in `<tmp>/Recordings` (VideoRecordingCoordinator.defaultDirectory): a recording is being written or offered.
    nonisolated static func recordingFileExists() -> Bool {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Recordings", isDirectory: true)
        return !((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty
    }

    /// Every DEBUG launch: delete an earlier ballast, then fill when asked.
    func startAtLaunch() {
        try? FileManager.default.removeItem(at: Self.file)
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: Self.argument), i + 1 < arguments.count,
              let freeMB = Int64(arguments[i + 1]), freeMB > 0 else { return }
        var grow: Int64 = 0
        if let g = arguments.firstIndex(of: Self.growArgument), g + 1 < arguments.count { grow = Int64(arguments[g + 1]) ?? 0 }
        let target = freeMB * 1_000_000
        value = "state=filling ballastMB=0 targetMB=\(freeMB)"
        Task.detached(priority: .userInitiated) {
            let worker = BallastWriter(url: Self.file)
            let filled = worker.fill(toFree: target, budgetSeconds: Self.fillBudgetSeconds) { (line: String) in
                Task { @MainActor in   // a late progress line never replaces the final one
                    if UITestDiskBallast.shared.value.hasPrefix("state=filling") { UITestDiskBallast.shared.value = line }
                }
            }
            await MainActor.run { UITestDiskBallast.shared.value = filled }
            guard grow > 0, !filled.hasPrefix("state=failed") else { return }
            for _ in 0..<1_200 {   // at most 10 minutes
                try? await Task.sleep(for: .milliseconds(500))
                guard Self.recordingFileExists() else { continue }   // grows only while a recording is being made
                let line = worker.grow(by: grow * 500_000, floor: Self.reserveBytes)
                await MainActor.run { UITestDiskBallast.shared.value = line }
                if line.hasPrefix("state=failed") { return }   // at the floor: keep topping up while recording
            }
        }
    }
}

/// The ballast file (off the main actor): preallocated with F_PREALLOCATE, written in 16 MB chunks where that is
/// not counted by the volume.
final class BallastWriter: @unchecked Sendable {
    let url: URL
    private var handle: FileHandle?
    private(set) var bytes: Int64 = 0
    private var target: Int64 = 0

    init(url: URL) { self.url = url }

    /// `reading` is what the disk guard reads (`VolumeStorageReading.guardBytes`: the smaller of the two); -1 unknown.
    static func readings(_ url: URL) -> (important: Int64, real: Int64, reading: Int64) {
        let folder = url.deletingLastPathComponent()
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let important = values?.volumeAvailableCapacityForImportantUsage ?? -1
        let real = Int64(values?.volumeAvailableCapacity ?? -1)
        let reading = VolumeStorageReading.guardBytes(important: important > 0 ? important : nil, real: real > 0 ? real : nil)
        return (important, real, reading ?? -1)
    }

    func line(_ state: String) -> String {
        let r = Self.readings(url)
        return "state=\(state) ballastMB=\(bytes / 1_000_000) freeMB=\(r.important / 1_000_000) "
            + "realFreeMB=\(r.real / 1_000_000) guardMB=\(r.reading / 1_000_000) targetMB=\(target / 1_000_000)"
    }

    enum Extension { case done, refused, outOfTime }

    /// Adds `count` bytes to the file (`refused` when the volume refused; `outOfTime` when `deadline` passed between
    /// two 16 MB chunks, keeping what was written).
    private func extend(by count: Int64, deadline: Date = .distantFuture) -> Extension {
        guard count > 0, let handle else { return count == 0 ? .done : .refused }
        var store = fstore_t(fst_flags: UInt32(F_ALLOCATEALL), fst_posmode: Int32(F_PEOFPOSMODE), fst_offset: 0,
                             fst_length: off_t(count), fst_bytesalloc: 0)
        let fd = handle.fileDescriptor
        let before = Self.readings(url).real
        if fcntl(fd, F_PREALLOCATE, &store) != -1, ftruncate(fd, off_t(bytes + count)) == 0 {
            // Counted by the volume? Otherwise write the range for real.
            if before - Self.readings(url).real >= count / 2 {
                bytes += count
                return .done
            }
            _ = ftruncate(fd, off_t(bytes))   // not counted: write the range for real from the current end
        }
        do {
            try handle.seek(toOffset: UInt64(bytes))
            let chunk = Data(count: 16 * 1_048_576)
            var left = count
            while left > 0 {
                if Date() >= deadline {
                    try handle.synchronize()
                    return .outOfTime
                }
                let piece = min(left, Int64(chunk.count))
                try handle.write(contentsOf: piece == Int64(chunk.count) ? chunk : chunk.prefix(Int(piece)))
                left -= piece
                bytes += piece
            }
            try handle.synchronize()
            return .done
        } catch {
            return .refused
        }
    }

    /// The largest single extension of a fill (a progress line follows each one).
    static let fillStepBytes: Int64 = 1_000_000_000

    /// Fills until the guard's reading is about `free`, never below the real-space floor, in steps of at most
    /// `fillStepBytes` (each step re-reads the volume, which moves as the system purges). `progress` gets a
    /// "state=filling" line after every step. Ends `holding` (reached), `capped` (real space ran out first), `failed`,
    /// or `slow` (`budgetSeconds` passed first).
    func fill(toFree free: Int64, budgetSeconds: Double = .infinity,
              progress: (String) -> Void = { (_: String) in }) -> String {
        target = free
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        guard handle != nil else { return line("failed") }
        let started = Date()
        for _ in 0..<1_000 {   // 1 TB at most
            let r = Self.readings(url)
            guard r.important > 0, r.real > 0 else { return line("failed") }
            let wanted = r.reading - free
            if wanted <= 8_000_000 { return line("holding") }
            let allowed = r.real - UITestDiskBallast.realFloorBytes
            if allowed <= 0 { return line("capped") }
            if Date().timeIntervalSince(started) >= budgetSeconds { return line("slow") }
            switch extend(by: min(wanted, allowed, Self.fillStepBytes), deadline: started.addingTimeInterval(budgetSeconds)) {
            case .done: break
            case .refused: return line("failed")
            case .outOfTime: return line("slow")
            }
            progress(line("filling"))
        }
        return line("holding")
    }

    /// How far above the floor the last growth step stops: the disk guard stops a recording below
    /// reserve + 10 s × at least 1 Mb/s × 1.25 (RecordingStoragePolicy.stopThreshold, about 1.56 MB above the
    /// reserve), so the ballast must end closer to the reserve than that.
    nonisolated static let floorMarginBytes: Int64 = 500_000

    /// The bytes one growth step may add: `step`, shortened so the guard's reading ends `floorMarginBytes` above
    /// `floor` and the real space above `realFloor`; 0 when it is there already.
    ///
    /// QA-011 pass 5 (D3, 2026-11-19): a whole 10 MB step that would cross the floor was refused, so the ballast
    /// stopped anywhere up to 10 MB above the 200 MiB reserve ("state=floor … guardMB=211") and stayed there (the
    /// loop ended). The guard stops below the reserve plus 10 s of video (about 1.6-15 MB above it by bit rate), so
    /// a low-rate recording (the Photo visual) ran 150 s with the reading just above its stop line and the
    /// recording's own writes too slow to cross it (REC-015-T17). The last step is now shortened to land just above
    /// the reserve, and the ballast keeps topping up while the recording runs (the system may purge space meanwhile).
    nonisolated static func growthStep(step: Int64, reading: Int64, real: Int64, floor: Int64, realFloor: Int64) -> Int64 {
        let room = min(reading - floor - floorMarginBytes, real - realFloor)
        return max(0, min(step, room))
    }

    /// One growth step; "state=growing" after a step, "state=floor" when the reading is at the floor already.
    func grow(by step: Int64, floor: Int64) -> String {
        let r = Self.readings(url)
        let bytes = Self.growthStep(step: step, reading: r.reading, real: r.real, floor: floor,
                                    realFloor: UITestDiskBallast.realFloorBytes)
        guard bytes >= 4_096 else { return line("floor") }
        return extend(by: bytes) == .done ? line("growing") : line("failed")
    }
}
#endif
