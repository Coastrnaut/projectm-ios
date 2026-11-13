// UITestStorageFixture.swift — DEBUG only (FILE-009-R10). `-uitestStorageFixture` points the Storage
// screen at `<tmp>/StorageFixture/container`, a copy of the container's layout recreated once per
// launch with known sizes (research R7), and shows "Add Test Recording" (2,000,000 more bytes in
// Recordings). The real stores are never touched. Not compiled into Release builds.
#if DEBUG
import Foundation
import LocalPortability

enum UITestStorageFixture {
    static let argument = "-uitestStorageFixture"
    static let addedRecordingBytes = 2_000_000

    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("StorageFixture/container", isDirectory: true)
    }

    /// Seeded once per launch, on first use.
    static let locations: StorageLocations = {
        let container = root
        let locations = StorageLocations.make(
            applicationSupport: container.appendingPathComponent("Library/Application Support", isDirectory: true),
            temporary: container.appendingPathComponent("tmp", isDirectory: true),
            caches: container.appendingPathComponent("Library/Caches", isDirectory: true),
            container: container)
        try? FileManager.default.removeItem(at: container)
        func first(_ category: StorageCategory) -> URL { locations.roots[category]?.first ?? container }
        let files: [(URL, String, Int)] = [
            (first(.photos), "photo.heic", 2_000_000),
            (first(.videos), "video.mov", 5_000_000),
            (first(.scenes), "current.scene", 10_000),
            (first(.scenes), "current.scene.bak", 10_000),
            (first(.scenes), "current.scene.tmp", 10_000),
            (first(.presets), "index.json", 50_000),
            (first(.importedAudio), "track.m4a", 3_000_000),
            (first(.recordings), "recording.mov", 1_000_000),
            (first(.sharesAndExports), "share.png", 20_000),
            (first(.caches), "shader.cache", 4_000),
            (container.appendingPathComponent("Library/Preferences", isDirectory: true), "settings.plist", 1_000),
        ]
        for (folder, name, size) in files { write(size, to: folder.appendingPathComponent(name)) }
        return locations
    }()

    /// Adds one more recording file of `addedRecordingBytes` bytes.
    static func addRecording() {
        guard let folder = locations.roots[.recordings]?.first else { return }
        write(addedRecordingBytes, to: folder.appendingPathComponent("added-\(UUID().uuidString).mov"))
    }

    private static func write(_ count: Int, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(repeating: 0x5A, count: count).write(to: url)
    }
}
#endif
