// PresetThumbnailCache.swift — roadmap PRE-001: thumbnails for owned presets, generated off the main
// thread and kept in a cache with stable IDs (contract specs/132-pre-001-thumbnail-cache/contracts/
// thumbnail-cache.md C1-C3; research PRE-001-D5-D7).
//
// * A request whose thumbnail is in the index and on disk returns its file at once (no render).
// * Otherwise it waits in a pending list: one entry per stable ID (a repeat adds a waiter and makes
//   the entry newest), at most `maxPending` entries (the oldest is dropped), newest served first.
// * One worker task at utility priority renders one entry at a time, writes the PNG and the index,
//   answers every waiter, then sleeps `pause` (injected, so tests never wait on the clock).
// * A caller's cancellation removes its waiter; an entry left without waiters is removed before its
//   render starts. A render already started finishes and is cached.
// * `unavailable` (no drawing possible now) is passed on and forgotten; any other failure keeps the
//   placeholder for the rest of the session (PRE-001-R11). Nothing about failures is written.
//
// Foundation only, so the cache builds and is tested on Linux; the renderer is a protocol (a fake in
// tests, ANGLE in the app).
import Foundation

/// Draws a preset's text into an encoded picture (PNG) per `spec`.
public protocol PresetThumbnailRendering: Sendable {
    /// Throws `PresetThumbnailError.unavailable` when nothing can be drawn now (not remembered), any
    /// other error when this preset cannot be drawn.
    func render(_ contents: Data, spec: PresetThumbnailSpec) async throws -> Data
}

public enum PresetThumbnailError: Error, Sendable, Equatable {
    /// Nothing can be drawn now (no renderer, the app is not on screen); ask again later.
    case unavailable(String)
    /// This preset could not be drawn or stored; not retried in this session.
    case failed(String)
    /// More than `maxPending` requests waited; this, the oldest, was dropped.
    case dropped
}

public actor PresetThumbnailCache {
    public typealias Sleep = @Sendable (Duration) async -> Void
    public typealias ContentsLoader = @Sendable () async throws -> Data

    /// `Library/Caches/<folderName>` in the app (FILE-009's "Caches" category, FILE-010's Clear Caches).
    public static let folderName = "PresetThumbnails"
    public static let defaultPause: Duration = .milliseconds(150)
    public static let defaultMaxPending = 32

    public nonisolated let directory: URL
    public nonisolated let spec: PresetThumbnailSpec
    private let renderer: any PresetThumbnailRendering
    private let pause: Duration
    private let maxPending: Int
    private let sleep: Sleep

    private struct Pending {
        let key: PresetThumbnailKey
        let contents: ContentsLoader
        var waiters: [UInt64: CheckedContinuation<URL, any Error>] = [:]
    }

    private var index: PresetThumbnailIndex
    private var opened = false
    private var pending: [String: Pending] = [:]
    /// Stable IDs of `pending`, oldest first.
    private var order: [String] = []
    private var inFlight: (id: String, entry: Pending)?
    /// Session failures by stable ID, with the key they belong to (PRE-002 forgets a changed preset's).
    private var failures: [String: (key: PresetThumbnailKey, message: String)] = [:]
    /// PRE-002: the render in flight belongs to an invalidated key; its picture is not stored.
    private var inFlightStale = false
    private var worker: Task<Void, Never>?
    private var suspended = false
    private var nextToken: UInt64 = 0

    /// Renders started since this cache was created (tests and automation).
    public private(set) var renderCount = 0
    private var repair: PresetThumbnailIndex.Repair = .none
    /// What opening repaired (opens first).
    public var lastRepair: PresetThumbnailIndex.Repair {
        open()
        return repair
    }

    public init(directory: URL, renderer: any PresetThumbnailRendering, spec: PresetThumbnailSpec = .standard,
                pause: Duration = PresetThumbnailCache.defaultPause, maxPending: Int = PresetThumbnailCache.defaultMaxPending,
                sleep: @escaping Sleep = { duration in try? await Task.sleep(for: duration) }) {
        self.directory = directory
        self.renderer = renderer
        self.spec = spec
        self.pause = pause
        self.maxPending = max(1, maxPending)
        self.sleep = sleep
        self.index = PresetThumbnailIndex(rendererVersion: spec.rendererVersion)
    }

    // MARK: - Opening (PRE-001-R7, R8)

    /// Reads and repairs the index; later calls do nothing. Never fails.
    public func open() {
        guard !opened else { return }
        opened = true
        let result = PresetThumbnailIndex.openRepairing(directory: directory, rendererVersion: spec.rendererVersion)
        index = result.index
        repair = result.repair
    }

    public var entryCount: Int {
        open()
        return index.entries.count
    }

    public var pendingCount: Int { order.count }

    public var failureCount: Int { failures.count }

    // MARK: - Requests (C2, C3)

    /// The file of a valid cached thumbnail, without queuing anything. An entry whose file has gone
    /// (Clear Caches) is dropped.
    public func cachedURL(for key: PresetThumbnailKey) -> URL? {
        open()
        let id = key.stableID
        guard let entry = index.entries[id] else { return nil }
        let url = directory.appendingPathComponent(entry.file)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        index.entries[id] = nil
        return nil
    }

    /// The thumbnail's file: at once when cached, otherwise after it is rendered (C3).
    public func thumbnail(for key: PresetThumbnailKey, contents: @escaping ContentsLoader) async throws -> URL {
        if let url = cachedURL(for: key) { return url }
        let id = key.stableID
        if let failure = failures[id] { throw PresetThumbnailError.failed(failure.message) }
        try Task.checkCancellation()
        let token = nextToken
        nextToken += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
                enqueue(key: key, contents: contents, token: token, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel(id: id, token: token) }
        }
    }

    /// While suspended no render starts; requests keep waiting (bounded). Resuming restarts the worker.
    public func setSuspended(_ value: Bool) {
        suspended = value
        if !value { startWorkerIfNeeded() }
    }

    // MARK: - Invalidation (PRE-002, contract C1, C2)

    /// Removes every entry of `presetID` whose content hash is not `keepingContentHash` (all of them
    /// when nil) with its file and remembered failure; cancels queued requests for those keys; a
    /// render of one already running stores nothing. Other presets are not touched. The index is
    /// saved only when an entry was removed. Returns the number of entries removed. Never throws.
    @discardableResult
    public func invalidate(presetID: String, keepingContentHash: String?) -> Int {
        open()
        let isStale: (PresetThumbnailKey) -> Bool = { (key: PresetThumbnailKey) -> Bool in
            key.presetID == presetID && key.contentHash != keepingContentHash
        }
        failures = failures.filter { (_: String, failure: (key: PresetThumbnailKey, message: String)) -> Bool in !isStale(failure.key) }
        for (id, entry) in pending where isStale(entry.key) {
            pending[id] = nil
            order.removeAll { (other: String) -> Bool in other == id }
            for waiter in entry.waiters.values { waiter.resume(throwing: CancellationError()) }
        }
        if let current = inFlight, isStale(current.entry.key) { inFlightStale = true }
        let removed = index.removeEntries(index.staleIDs(presetID: presetID, keepingContentHash: keepingContentHash), in: directory)
        if removed > 0 { index.save(in: directory) }
        return removed
    }

    /// Launch collection (PRE-002-R7): removes, with their files and failures, the entries of presets
    /// not in `listing` (preset ID → current content hash) or listed with another hash. Saves the
    /// index only when something was removed. Returns the number removed.
    @discardableResult
    public func retainOnly(_ listing: [String: String]) -> Int {
        open()
        failures = failures.filter { (_: String, failure: (key: PresetThumbnailKey, message: String)) -> Bool in
            listing[failure.key.presetID] == failure.key.contentHash
        }
        let removed = index.removeEntries(index.unlistedIDs(listing), in: directory)
        if removed > 0 { index.save(in: directory) }
        return removed
    }

    // MARK: - Queue

    private func enqueue(key: PresetThumbnailKey, contents: @escaping ContentsLoader, token: UInt64,
                         continuation: CheckedContinuation<URL, any Error>) {
        let id = key.stableID
        if inFlight?.id == id {
            inFlight?.entry.waiters[token] = continuation
            return
        }
        var entry = pending[id] ?? Pending(key: key, contents: contents)
        entry.waiters[token] = continuation
        pending[id] = entry
        order.removeAll { (other: String) -> Bool in other == id }
        order.append(id)
        while order.count > maxPending {
            let oldest = order.removeFirst()
            if let dropped = pending.removeValue(forKey: oldest) {
                for waiter in dropped.waiters.values { waiter.resume(throwing: PresetThumbnailError.dropped) }
            }
        }
        startWorkerIfNeeded()
    }

    private func cancel(id: String, token: UInt64) {
        if inFlight?.id == id, let waiter = inFlight?.entry.waiters.removeValue(forKey: token) {
            waiter.resume(throwing: CancellationError())
            return
        }
        guard var entry = pending[id], let waiter = entry.waiters.removeValue(forKey: token) else { return }
        waiter.resume(throwing: CancellationError())
        if entry.waiters.isEmpty {
            pending[id] = nil
            order.removeAll { (other: String) -> Bool in other == id }
        } else {
            pending[id] = entry
        }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !suspended, !order.isEmpty else { return }
        worker = Task(priority: .utility) { await self.runWorker() }
    }

    private func runWorker() async {
        while !suspended, let id = order.popLast() {
            guard let entry = pending.removeValue(forKey: id) else { continue }
            inFlight = (id, entry)
            inFlightStale = false
            renderCount += 1
            let result = await produce(entry.key, contents: entry.contents)
            let waiters = inFlight?.entry.waiters ?? [:]
            inFlight = nil
            for waiter in waiters.values { waiter.resume(with: result) }
            await sleep(pause)
        }
        worker = nil
    }

    /// Loads, renders and stores one thumbnail.
    private func produce(_ key: PresetThumbnailKey, contents: ContentsLoader) async -> Result<URL, any Error> {
        let id = key.stableID
        do {
            let data = try await contents()
            let png = try await renderer.render(data, spec: spec)
            if inFlightStale { throw PresetThumbnailError.unavailable("The preset changed while it was drawn.") }
            let url = directory.appendingPathComponent(key.fileName)
            do {
                try prepareDirectory()
                try png.write(to: url, options: .atomic)
            } catch {
                throw PresetThumbnailError.failed("The thumbnail could not be stored.")
            }
            index.entries[id] = PresetThumbnailIndex.Entry(presetID: key.presetID, contentHash: key.contentHash,
                                                           rendererVersion: key.rendererVersion, file: key.fileName,
                                                           width: spec.width, height: spec.height)
            index.save(in: directory)   // a failed index write leaves a file the next open removes
            return .success(url)
        } catch let error as PresetThumbnailError {
            if case .unavailable = error { return .failure(error) }
            let message: String
            if case .failed(let text) = error { message = text } else { message = "The thumbnail could not be made." }
            failures[id] = (key, message)
            return .failure(PresetThumbnailError.failed(message))
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch {
            let message = "The preset could not be drawn."
            failures[id] = (key, message)
            return .failure(PresetThumbnailError.failed(message))
        }
    }

    /// Creates the folder (again, after Clear Caches) and keeps it out of backups (PRE-001-R9).
    private func prepareDirectory() throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if canImport(Darwin)
            var marked = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? marked.setResourceValues(values)
            #endif
        }
    }
}
