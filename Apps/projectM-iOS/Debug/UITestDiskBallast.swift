// UITestDiskBallast.swift — DEBUG only (QA-011 Batch 6: REC-015-T17, REC-009-T11). `-uitestDiskBallast <freeMB>` fills
// the volume with one ballast file in Caches until the free space the disk guard reads
// (`volumeAvailableCapacityForImportantUsage`, REC-015) is about <freeMB>; `-uitestDiskBallastGrowMBps <n>` then grows
// it by n MB a second while a recording file exists in `<tmp>/Recordings`, so a real recording meets the real guard
// within seconds instead of minutes. Safety: the ballast never leaves less
// than 200 MB of real free space (`volumeAvailableCapacity`) or less than the guard's 200 MiB reserve, and every DEBUG
// launch deletes a ballast left by an earlier launch first (the tests also relaunch once in tearDown). The probe
// `diskBallast` (with `-uitestDiagnostics`) reads "state=<…> ballastMB=<n> freeMB=<n> realFreeMB=<n> targetMB=<n>";
// state `capped` means the device's purgeable space kept the reading above the target. The readings stay in memory.
// Not compiled into Release builds.
#if DEBUG
import Foundation

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
            let filled = worker.fill(toFree: target)
            await MainActor.run { UITestDiskBallast.shared.value = filled }
            guard grow > 0, !filled.hasPrefix("state=failed") else { return }
            for _ in 0..<1_200 {   // at most 10 minutes
                try? await Task.sleep(for: .milliseconds(500))
                guard Self.recordingFileExists() else { continue }   // grows only while a recording is being made
                let line = worker.grow(by: grow * 500_000, floor: Self.reserveBytes)
                await MainActor.run { UITestDiskBallast.shared.value = line }
                if !line.hasPrefix("state=growing") { return }
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

    static func readings(_ url: URL) -> (important: Int64, real: Int64) {
        let folder = url.deletingLastPathComponent()
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        return (values?.volumeAvailableCapacityForImportantUsage ?? -1, Int64(values?.volumeAvailableCapacity ?? -1))
    }

    func line(_ state: String) -> String {
        let r = Self.readings(url)
        return "state=\(state) ballastMB=\(bytes / 1_000_000) freeMB=\(r.important / 1_000_000) "
            + "realFreeMB=\(r.real / 1_000_000) targetMB=\(target / 1_000_000)"
    }

    /// Adds `count` bytes to the file; false when the volume refused.
    private func extend(by count: Int64) -> Bool {
        guard count > 0, let handle else { return count == 0 }
        var store = fstore_t(fst_flags: UInt32(F_ALLOCATEALL), fst_posmode: Int32(F_PEOFPOSMODE), fst_offset: 0,
                             fst_length: off_t(count), fst_bytesalloc: 0)
        let fd = handle.fileDescriptor
        let before = Self.readings(url).real
        if fcntl(fd, F_PREALLOCATE, &store) != -1, ftruncate(fd, off_t(bytes + count)) == 0 {
            // Counted by the volume? Otherwise write the range for real.
            if before - Self.readings(url).real >= count / 2 {
                bytes += count
                return true
            }
        }
        do {
            try handle.seek(toOffset: UInt64(bytes))
            let chunk = Data(count: 16 * 1_048_576)
            var left = count
            while left > 0 {
                let piece = min(left, Int64(chunk.count))
                try handle.write(contentsOf: piece == Int64(chunk.count) ? chunk : chunk.prefix(Int(piece)))
                left -= piece
            }
            try handle.synchronize()
            bytes += count
            return true
        } catch {
            return false
        }
    }

    /// Fills until the important-use reading is about `free`, never below the real-space floor.
    func fill(toFree free: Int64) -> String {
        target = free
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        guard handle != nil else { return line("failed") }
        for _ in 0..<4 {   // the reading moves as the system purges; a few passes settle it
            let r = Self.readings(url)
            guard r.important > 0, r.real > 0 else { return line("failed") }
            let wanted = r.important - free
            if wanted <= 8_000_000 { return line("holding") }
            let allowed = r.real - UITestDiskBallast.realFloorBytes
            if allowed <= 0 { return line("capped") }
            if !extend(by: min(wanted, allowed)) { return line("failed") }
            if wanted > allowed { return line("capped") }
        }
        return line("holding")
    }

    /// One growth step; "state=growing" while it may grow again.
    func grow(by step: Int64, floor: Int64) -> String {
        let r = Self.readings(url)
        guard r.important - step > floor, r.real - step > UITestDiskBallast.realFloorBytes else { return line("floor") }
        return extend(by: step) ? line("growing") : line("failed")
    }
}
#endif
