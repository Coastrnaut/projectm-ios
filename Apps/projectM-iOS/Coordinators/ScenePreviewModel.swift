// ScenePreviewModel.swift — roadmap SCN-006: scene preview pictures for the scene browser (specs/153-
// scn-006-scene-preview; contract P2; research SCN-006-D2, D4).
//
// * The pictures live in PresetLibrary's `ScenePreviewStore` (`Library/Caches/ScenePreviews`): keyed by
//   scene ID + SHA-256 of the scene file's bytes, so a changed file never shows an old picture. Counted
//   in Storage's "Caches", emptied by Clear Caches, excluded from backup, never in FILE-005 or FILE-001.
// * Capture (injected; REC-001's frame grab in the app, a fixture in tests): Add Current Scene captures
//   at once; an applied cue captures after `settle` (1 s) only when its file has no picture yet, and
//   only when the scene is still the applied one, its file and the live look are unchanged and the
//   output can be captured (SCN-006-R3). A later apply or save cancels a pending capture (token).
// * `scenesChanged` (ShowCoordinator's writes: rename, duplicate, add, cue removal) rehashes the named
//   scenes and removes their stale pictures; `reconcile` (launch) keeps only pictures that match a
//   stored scene's current file.
// * Rows observe `revision` and ask `image(forScene:)`; decoded pictures stay in an NSCache.
import Foundation
import Observation
import PresetLibrary
import UIKit

/// What a capture must still match when it is taken (SCN-006-R3).
struct ScenePreviewContext: Equatable {
    var appliedSceneID: String?
    var look: ShowLook?
    /// The output is live, not paused, a visual is shown and no Save Frame is in progress.
    var canCapture: Bool
}

@MainActor
@Observable
final class ScenePreviewModel {
    typealias Capture = @MainActor () async -> Data?
    typealias Sleep = @Sendable (Duration) async -> Void

    static let settle: Duration = .seconds(1)

    /// Changes after every stored or removed picture; rows reload on it.
    private(set) var revision = 0

    @ObservationIgnored let store: ScenePreviewStore
    @ObservationIgnored private let capture: Capture
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private let settle: Duration
    /// The scene's file (nil when the scene is not stored).
    @ObservationIgnored private let sceneFile: @MainActor (String) -> URL?
    @ObservationIgnored private let context: @MainActor () -> ScenePreviewContext
    @ObservationIgnored private var hashes: [String: String] = [:]
    @ObservationIgnored private let images = NSCache<NSString, UIImage>()
    @ObservationIgnored private var token = 0

    init(store: ScenePreviewStore, capture: @escaping Capture,
         sceneFile: @escaping @MainActor (String) -> URL?,
         context: @escaping @MainActor () -> ScenePreviewContext,
         settle: Duration = ScenePreviewModel.settle,
         sleep: @escaping Sleep = { (duration: Duration) in try? await Task.sleep(for: duration) }) {
        self.store = store
        self.capture = capture
        self.sceneFile = sceneFile
        self.context = context
        self.settle = settle
        self.sleep = sleep
        images.countLimit = 300
    }

    /// `Library/Caches/ScenePreviews`.
    nonisolated static func defaultDirectory() -> URL {
        let caches: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches", isDirectory: true)
        return caches.appendingPathComponent(ScenePreviewStore.folderName, isDirectory: true)
    }

    /// SHA-256 hex of a file's bytes; nil when it cannot be read.
    nonisolated static func hash(of url: URL?) -> String? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return ScenePreviewKey.contentHash(of: data)
    }

    // MARK: - Keys

    /// The key of the scene's current file (hashed once, then remembered until `scenesChanged`).
    func key(forScene sceneID: String) -> ScenePreviewKey? {
        if let hash = hashes[sceneID] { return ScenePreviewKey(sceneID: sceneID, contentHash: hash) }
        guard let hash = Self.hash(of: sceneFile(sceneID)) else { return nil }
        hashes[sceneID] = hash
        return ScenePreviewKey(sceneID: sceneID, contentHash: hash)
    }

    // MARK: - Capture (SCN-006-R1 to R3)

    /// Add Current Scene: the output already shows the scene, so the next frame is its picture.
    @discardableResult
    func sceneSaved(_ sceneID: String) -> Task<Bool, Never> {
        token &+= 1
        let request: Int = token
        return Task { @MainActor () -> Bool in
            guard let key = self.key(forScene: sceneID), self.context().canCapture else { return false }
            return await self.captureAndStore(key, request: request, expected: nil)
        }
    }

    /// A cue's scene reached the live output: after the settle, capture when it has no picture yet.
    @discardableResult
    func sceneApplied(_ sceneID: String) -> Task<Bool, Never> {
        token &+= 1
        let request: Int = token
        return Task { @MainActor () -> Bool in
            guard let key = self.key(forScene: sceneID) else { return false }
            if await self.store.hasPreview(for: key) { return false }
            let start: ScenePreviewContext = self.context()
            guard start.appliedSceneID == sceneID else { return false }
            await self.sleep(self.settle)
            return await self.captureAndStore(key, request: request, expected: start)
        }
    }

    /// Captures once the guard holds, and stores the picture under `key` when it still holds after.
    private func captureAndStore(_ key: ScenePreviewKey, request: Int, expected: ScenePreviewContext?) async -> Bool {
        guard stillValid(key, request: request, expected: expected) else { return false }
        guard let png = await capture() else { return false }
        guard stillValid(key, request: request, expected: expected) else { return false }
        guard (try? await store.store(png, for: key)) != nil else { return false }
        revision &+= 1
        return true
    }

    private func stillValid(_ key: ScenePreviewKey, request: Int, expected: ScenePreviewContext?) -> Bool {
        guard request == token else { return false }   // a later apply or save
        let now: ScenePreviewContext = context()
        guard now.canCapture else { return false }
        if let expected, now != expected { return false }   // another scene, or the look was edited
        return Self.hash(of: sceneFile(key.sceneID)) == key.contentHash   // the file was not rewritten
    }

    // MARK: - Invalidation (SCN-006-R5, R6)

    /// Scene files were written or removed: rehash them and drop their stale pictures. Cancels a
    /// pending capture of one of them.
    @discardableResult
    func scenesChanged(_ sceneIDs: Set<String>) -> Task<Void, Never> {
        guard !sceneIDs.isEmpty else { return Task {} }
        var updates: [(String, String?)] = []
        for id in sceneIDs.sorted() {
            let hash: String? = Self.hash(of: sceneFile(id))
            hashes[id] = hash
            updates.append((id, hash))
        }
        token &+= 1
        let store: ScenePreviewStore = store
        return Task { @MainActor () -> Void in
            for (id, hash) in updates { await store.invalidate(sceneID: id, keepingContentHash: hash) }
            self.revision &+= 1
        }
    }

    /// Launch: keeps only pictures that match a stored scene's current file. Hashing runs off the
    /// main actor.
    @discardableResult
    func reconcile(sceneIDs: [String]) -> Task<Void, Never> {
        let files: [(String, URL?)] = sceneIDs.map { (id: String) -> (String, URL?) in (id, sceneFile(id)) }
        let store: ScenePreviewStore = store
        return Task { @MainActor () -> Void in
            let listing: [String: String] = await Task.detached(priority: .utility) { () -> [String: String] in
                var result: [String: String] = [:]
                for (id, url) in files {
                    if let hash = ScenePreviewModel.hash(of: url) { result[id] = hash }
                }
                return result
            }.value
            for (id, hash) in listing where self.hashes[id] == nil { self.hashes[id] = hash }
            await store.retainOnly(listing)
            self.revision &+= 1
        }
    }

    // MARK: - Pictures (SCN-006-R8)

    /// The decoded picture when it is already in memory.
    func memoryImage(forScene sceneID: String) -> UIImage? {
        guard let key = key(forScene: sceneID) else { return nil }
        return images.object(forKey: key.stableID as NSString)
    }

    /// The scene's current picture; nil when it has none (placeholder).
    func image(forScene sceneID: String) async -> UIImage? {
        guard let key = key(forScene: sceneID) else { return nil }
        if let image = images.object(forKey: key.stableID as NSString) { return image }
        guard let url = await store.cachedURL(for: key) else { return nil }
        let image: UIImage? = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)?.preparingForDisplay()
        }.value
        if let image { images.setObject(image, forKey: key.stableID as NSString) }
        return image
    }
}
