// RecordingLibraryModel.swift — REC-010 (contract C4, C5; REC-010-R2 to R6, R9): the Recordings screen's state.
//
// * `refresh()` scans the folder (no index) and keeps the facts and thumbnails already read for unchanged files
//   (same name and size); new files get their facts and thumbnail off the main actor.
// * Delete asks first (`pendingDelete`); `confirmDelete()` removes the file, then the row in the same main-actor
//   update, so the count and total drop at once, removes the thumbnail entry and announces "Recording deleted."
//   Cancel removes nothing.
// * Rename validates (RecordingLibraryStore) and announces "Recording renamed."; every announcement goes to the
//   shared announcer's library lane (`announce`).
import Foundation
import Observation

/// One row (data model: RecordingLibraryItem).
struct RecordingLibraryItem: Identifiable, Equatable {
    enum State: Equatable {
        case loading
        case ready(RecordingFacts)
        case incomplete
    }

    var file: RecordingLibraryFile
    var state: State
    var thumbnail: Data?

    var id: String { file.id }
    var facts: RecordingFacts? {
        if case let .ready(facts) = state { return facts }
        return nil
    }
    var isIncomplete: Bool { state == .incomplete }
}

@MainActor
@Observable
final class RecordingLibraryModel {
    static let deletedText = "Recording deleted."
    static let renamedText = "Recording renamed."
    static let deleteFailedText = "The recording couldn't be deleted."
    static let renameFailedText = "The recording couldn't be renamed."
    static let emptyText = "No saved recordings"

    private(set) var items: [RecordingLibraryItem] = []
    /// The row waiting for the delete confirmation.
    private(set) var pendingDelete: RecordingLibraryItem?
    /// The last failure, shown under the list.
    private(set) var message: String?
    /// The row whose player or share sheet is shown.
    var playing: RecordingLibraryItem?

    @ObservationIgnored let store: RecordingLibraryStore
    @ObservationIgnored let inspector: RecordingLibraryInspector
    /// The shared announcer's library lane (AppCoordinator).
    @ObservationIgnored var announce: (@MainActor (String) -> Void)?
    /// REC-011: Save to Photos on a row (AppCoordinator); nil hides the button (previews, tests).
    @ObservationIgnored var photos: PhotosSaveCoordinator?
    /// The running facts and thumbnail loads (tests await them).
    @ObservationIgnored private(set) var loads: [Task<Void, Never>] = []

    init(store: RecordingLibraryStore = RecordingLibraryModel.storeForCurrentLaunch(),
         inspector: RecordingLibraryInspector = RecordingLibraryInspector(thumbnailDirectory: RecordingLibraryInspector.defaultThumbnailDirectory)) {
        self.store = store
        self.inspector = inspector
    }

    /// The real library; DEBUG `-uitestRecordingLibrarySeed <n>` seeds it first (once per launch).
    static func storeForCurrentLaunch() -> RecordingLibraryStore {
        let store = RecordingLibraryStore.standard()
        #if DEBUG
        RecordingLibraryFixture.seedFromArgumentsOnce(into: store)
        #endif
        return store
    }

    var count: Int { items.count }
    var totalBytes: Int64 { items.reduce(Int64(0)) { (sum: Int64, item: RecordingLibraryItem) -> Int64 in sum + item.file.bytes } }

    /// "3 recordings, 12 MB" or "No saved recordings".
    var summaryText: String {
        guard !items.isEmpty else { return Self.emptyText }
        let noun = items.count == 1 ? "recording" : "recordings"
        return "\(items.count) \(noun), \(Self.format(totalBytes))"
    }

    static func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    /// Rescans the folder; unchanged files keep what was read.
    func refresh() {
        let previous: [String: RecordingLibraryItem] = Dictionary(items.map { (item: RecordingLibraryItem) -> (String, RecordingLibraryItem) in
            (item.file.cacheKey, item)
        }, uniquingKeysWith: { (first: RecordingLibraryItem, _: RecordingLibraryItem) -> RecordingLibraryItem in first })
        var next: [RecordingLibraryItem] = []
        var toLoad: [RecordingLibraryFile] = []
        for file in store.scan() {
            if var known = previous[file.cacheKey] {
                known.file = file
                next.append(known)
            } else {
                next.append(RecordingLibraryItem(file: file, state: .loading, thumbnail: nil))
                toLoad.append(file)
            }
        }
        items = next
        for file in toLoad { load(file) }
    }

    private func load(_ file: RecordingLibraryFile) {
        let inspector = inspector
        let task = Task { @MainActor [weak self] in
            let facts: RecordingFacts? = await RecordingLibraryInspector.facts(of: file.url)
            guard let facts else {
                self?.update(file, state: .incomplete, thumbnail: nil)
                return
            }
            self?.update(file, state: .ready(facts), thumbnail: nil)
            let data: Data? = await inspector.thumbnail(for: file, durationSeconds: facts.durationSeconds)
            self?.update(file, state: .ready(facts), thumbnail: data)
        }
        loads.append(task)
    }

    private func update(_ file: RecordingLibraryFile, state: RecordingLibraryItem.State, thumbnail: Data?) {
        guard let index = items.firstIndex(where: { (item: RecordingLibraryItem) -> Bool in item.file.cacheKey == file.cacheKey }) else { return }
        items[index].state = state
        if let thumbnail { items[index].thumbnail = thumbnail }
    }

    /// Awaits every load started so far (tests).
    func waitForLoads() async {
        while !loads.isEmpty {
            let running = loads
            loads.removeAll()
            for task in running { await task.value }
        }
    }

    // MARK: - Delete (contract C4)

    func requestDelete(_ item: RecordingLibraryItem) {
        message = nil
        pendingDelete = item
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    /// Removes the confirmed file and its row now; a file already gone still loses its row.
    func confirmDelete() {
        guard let item = pendingDelete else { return }
        pendingDelete = nil
        do {
            try store.delete(item.file)
        } catch {
            message = Self.deleteFailedText
            announce?(Self.deleteFailedText)
            return
        }
        items.removeAll { (row: RecordingLibraryItem) -> Bool in row.id == item.id }
        if playing?.id == item.id { playing = nil }
        let inspector = inspector
        let file = item.file
        loads.append(Task { await inspector.removeThumbnail(for: file) })
        announce?(Self.deletedText)
    }

    /// The confirmation's message (contract C4).
    static func deleteMessage(_ item: RecordingLibraryItem) -> String {
        "“\(item.file.name)” will be deleted from this device. This can't be undone."
    }

    // MARK: - Rename (contract C5)

    /// Renames, or returns the refusal's text (nothing changes).
    @discardableResult
    func rename(_ item: RecordingLibraryItem, to proposed: String) -> String? {
        if case let .failure(error) = store.validate(name: proposed, excluding: item.file) { return error.message }
        do {
            _ = try store.rename(item.file, to: proposed)
        } catch {
            return Self.renameFailedText
        }
        let inspector = inspector
        let old = item.file
        loads.append(Task { await inspector.removeThumbnail(for: old) })
        refresh()
        announce?(Self.renamedText)
        return nil
    }

    func clearMessage() { message = nil }

    /// "Name, 0:02, 12 KB, 14 Nov 2026 at 10:00, 64×64, 10 fps, H.264" or "Name, Incomplete, 12 KB".
    static func accessibilityLabel(_ item: RecordingLibraryItem) -> String {
        let size = format(item.file.bytes)
        let stem = RecordingLibraryStore.stem(of: item.file.name)
        switch item.state {
        case .incomplete: return "\(stem), Incomplete, \(size)"
        case .loading: return "\(stem), \(size), \(dateText(item.file.date))"
        case let .ready(f):
            let parts: [String] = [stem, f.durationText, size, dateText(item.file.date), f.resolutionText, f.frameRateText, f.codecText]
            return parts.joined(separator: ", ")
        }
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
