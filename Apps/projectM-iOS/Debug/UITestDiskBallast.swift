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
// QA-011 D3 (2026-11-24): every launch after a ballast test took 5-7 minutes on D3 (iPadOS 26.5, 128 GB), never on
// D1 or D2, and a launch of the old build had still not deleted a 66 GB ballast 24 minutes later: the delete sat on the
// main actor in front of the launch. A launch now renames any leftover ballast at once and deletes it off the main
// actor (before a requested fill): 0.9-2.5 s for 66 GB on D3. Asking the running app to delete its own open ballast
// (a Darwin notification, tried the same day) never finished within 240 s on D3 and held up the app's end, so the tests
// only relaunch. Each delete appends its timing to `QA011-DiskBallast-timing.log` in Caches (process age at launch, MB
// deleted, seconds), which `scripts/clear_disk_ballast.py` prints.
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

    /// `-uitestDiskGuardReserveMB <n>`: the disk guard keeps n MB instead of its 200 MiB reserve (QA-011 2026-11-20).
    /// D2 left the network twice when REC-015-T17 filled it to 199 and 700 MB of real free space (pass 4, full run 12):
    /// with an 8 GB reserve the real guard reads the real free space and stops a real recording 8 GB before full.
    nonisolated static let guardReserveArgument = "-uitestDiskGuardReserveMB"
    nonisolated static var guardReserveBytes: Int64 {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: guardReserveArgument), i + 1 < arguments.count,
              let mb = Int64(arguments[i + 1]), mb > 0 else { return reserveBytes }
        return max(reserveBytes, mb * 1_000_000)
    }

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

    /// Timings of every ballast delete (Caches, so `clear_disk_ballast.py` can copy it; DEBUG only).
    nonisolated static var timingLog: URL { file.deletingLastPathComponent().appendingPathComponent("QA011-DiskBallast-timing.log") }

    nonisolated static func appendTiming(_ line: String) {
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: timingLog) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: timingLog)
        }
    }

    /// Seconds since this process started (sysctl's p_starttime); -1 when unknown.
    nonisolated static func processAgeSeconds() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return -1 }
        let start = info.kp_proc.p_starttime
        return Date().timeIntervalSince1970 - (Double(start.tv_sec) + Double(start.tv_usec) / 1e6)
    }

    /// Renames the ballast (and any earlier renamed one) out of the way at once; returns the files to delete.
    nonisolated static func retireLeftovers() -> [URL] {
        let folder = file.deletingLastPathComponent()
        let manager = FileManager.default
        if manager.fileExists(atPath: file.path) {
            try? manager.moveItem(at: file, to: folder.appendingPathComponent("QA011-DiskBallast-old-\(UUID().uuidString).bin"))
        }
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix("QA011-DiskBallast-old-") }.map { folder.appendingPathComponent($0) }
    }

    /// Deletes `urls`, timing it; returns (MB deleted, seconds).
    nonisolated static func delete(_ urls: [URL], context: String) -> (mb: Int64, seconds: Double) {
        guard !urls.isEmpty else { return (0, 0) }
        let started = Date()
        var bytes: Int64 = 0
        for url in urls {
            bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            try? FileManager.default.removeItem(at: url)
        }
        let seconds = Date().timeIntervalSince(started)
        appendTiming("\(context): deleted \(bytes / 1_000_000) MB in \(String(format: "%.1f", seconds)) s")
        return (bytes / 1_000_000, seconds)
    }

    /// Every DEBUG launch: move an earlier ballast aside at once and delete it off the main actor, then fill when asked.
    func startAtLaunch() {
        let age = Self.processAgeSeconds()
        let leftovers = Self.retireLeftovers()
        if !leftovers.isEmpty { Self.appendTiming("launch: process age \(String(format: "%.1f", age)) s, \(leftovers.count) leftover ballast file(s)") }
        let arguments = ProcessInfo.processInfo.arguments
        var target: Int64 = 0, grow: Int64 = 0
        if let i = arguments.firstIndex(of: Self.argument), i + 1 < arguments.count, let freeMB = Int64(arguments[i + 1]), freeMB > 0 {
            target = freeMB * 1_000_000
            value = "state=filling ballastMB=0 targetMB=\(freeMB)"
        }
        if let g = arguments.firstIndex(of: Self.growArgument), g + 1 < arguments.count { grow = Int64(arguments[g + 1]) ?? 0 }
        guard target > 0 || !leftovers.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            _ = Self.delete(leftovers, context: "launch")   // before the fill reads the free space
            guard target > 0 else { return }
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
                let line = worker.grow(by: grow * 500_000, floor: Self.guardReserveBytes)
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
