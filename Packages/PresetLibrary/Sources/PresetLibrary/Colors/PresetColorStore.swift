// PresetColorStore.swift — roadmap PRE-004: owns the colour index file (spec PRE-004-R4, R6, R10;
// research PRE-004-D5, D6; contract C3). `Library/Caches/PresetColors` in the app: counted in
// Storage's "Caches", emptied by Clear Caches, excluded from backup, rebuildable from thumbnails.
//
// * `record` replaces a preset's entry and schedules one save after `saveDelay` (coalesced: more
//   records before it fires ride along). `flush` writes at once.
// * `invalidate` and `retainOnly` follow PRE-002: entries of changed or unlisted presets go.
import Foundation

public actor PresetColorStore {
    public typealias Sleep = @Sendable (Duration) async -> Void

    public static let folderName = "PresetColors"
    public static let defaultSaveDelay: Duration = .seconds(1)

    public nonisolated let directory: URL
    private let saveDelay: Duration
    private let sleep: Sleep
    private var index = PresetColorIndex()
    private var opened = false
    private var dirty = false
    private var saveTask: Task<Void, Never>?
    private var repair: PresetColorIndex.Repair = .none

    /// Index writes since this store was created (tests).
    public private(set) var saveCount = 0

    public init(directory: URL, saveDelay: Duration = PresetColorStore.defaultSaveDelay,
                sleep: @escaping Sleep = { (duration: Duration) in try? await Task.sleep(for: duration) }) {
        self.directory = directory
        self.saveDelay = saveDelay
        self.sleep = sleep
    }

    /// Reads and repairs the index once.
    public func open() {
        guard !opened else { return }
        opened = true
        let result = PresetColorIndex.openRepairing(directory: directory)
        index = result.index
        repair = result.repair
    }

    public var lastRepair: PresetColorIndex.Repair {
        open()
        return repair
    }

    public func snapshot() -> [String: PresetColorIndex.Entry] {
        open()
        return index.entries
    }

    /// Stores a preset's colours for a thumbnail ID; schedules a coalesced save when anything changed.
    public func record(presetID: String, thumbnailID: String, colors: [PresetColorFamily]) {
        open()
        guard !colors.isEmpty else { return }
        let entry = PresetColorIndex.Entry(thumbnailID: thumbnailID, colors: colors)
        guard index.entries[presetID] != entry else { return }
        index.entries[presetID] = entry
        scheduleSave()
    }

    /// Removes the preset's entry unless it belongs to `keepingThumbnailID`. Saves when removed.
    @discardableResult
    public func invalidate(presetID: String, keepingThumbnailID: String?) -> Bool {
        open()
        guard let entry = index.entries[presetID], entry.thumbnailID != keepingThumbnailID else { return false }
        index.entries[presetID] = nil
        writeNow()
        return true
    }

    /// Keeps only entries listed with the same thumbnail ID (preset ID → current thumbnail ID).
    @discardableResult
    public func retainOnly(_ listing: [String: String]) -> Int {
        open()
        let stale: [String] = index.entries.compactMap { (id: String, entry: PresetColorIndex.Entry) -> String? in
            listing[id] == entry.thumbnailID ? nil : id
        }
        for id in stale { index.entries[id] = nil }
        if !stale.isEmpty { writeNow() }
        return stale.count
    }

    /// Writes pending changes at once.
    public func flush() {
        guard dirty else { return }
        writeNow()
    }

    private func scheduleSave() {
        dirty = true
        guard saveTask == nil else { return }
        let delay: Duration = saveDelay
        let sleep: Sleep = self.sleep
        saveTask = Task(priority: .utility) {
            await sleep(delay)
            self.saveScheduled()
        }
    }

    private func saveScheduled() {
        saveTask = nil
        flush()
    }

    private func writeNow() {
        dirty = false
        index.save(in: directory)
        saveCount += 1
    }

    /// Creates the folder and keeps it out of backups.
    static func prepare(_ directory: URL) throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if canImport(Darwin)
        var marked = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? marked.setResourceValues(values)
        #endif
    }
}
