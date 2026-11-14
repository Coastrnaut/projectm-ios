// PresetThumbnailModel.swift — roadmap PRE-001: the browser's preset thumbnails (specs/132-pre-001-
// thumbnail-cache; research PRE-001-D1, D6-D8). Glue between the rows, the PresetLibrary cache and the
// renderer:
//
// * The cache (`PresetThumbnailCache`) lives in `Library/Caches/PresetThumbnails`: counted in Storage's
//   "Caches" category, emptied by Clear Caches (FILE-010), excluded from backup, not an erase category.
// * Drawing goes through the visible renderer's `presetThumbnails` (ANGLE's PresetThumbnailRunner); no
//   renderer yet, or one without a second engine (the GLES fallback), means `unavailable` and the row
//   keeps its placeholder until it appears again.
// * Only playable presets are drawn: the row asks only when `PresetCoordinator.isPlayable`, and an
//   imported preset's bytes come from the user library's playable copy (PRE-012), never a waiting or
//   quarantined one.
// * Decoded pictures stay in an NSCache, which the system empties under memory pressure.
// * PRE-004: the same detached decode also learns the picture's dominant colours when the preset has
//   none for this thumbnail ID; they go to a main-actor mirror (`colorEntries`, read by the browser's
//   colour chips) and to the coalescing `PresetColorStore` (`Library/Caches/PresetColors`).
// * PRE-005: the drawing also reads back two earlier frames with a pinned clock; their motion score is
//   written into the PNG (`PresetMotionPNG`). The same decode reads it back when the preset has no score
//   for this thumbnail ID; it goes to `motionEntries` (the energy chips) and `PresetMotionStore`
//   (`Library/Caches/PresetMotion`). Pictures without the field (earlier builds) have no score.
import Foundation
import ImageIO
import PresetLibrary
import Rendering
import UIKit
import UniformTypeIdentifiers

@MainActor
final class PresetThumbnailModel {
    typealias ContentsProvider = @MainActor @Sendable (IndexedPreset) async throws -> Data

    let cache: PresetThumbnailCache
    /// PRE-004: the colour index (nil in tests that do not need colours).
    let colors: PresetColorStore?
    /// PRE-004: preset ID → the thumbnail ID its colours came from and the colours (current ones only).
    private(set) var colorEntries: [String: PresetColorIndex.Entry] = [:]
    /// PRE-004: called on the main actor whenever `colorEntries` changes (the coordinator bumps a version).
    var onColorsChanged: () -> Void = {}
    /// PRE-005: the motion index (nil in tests that do not need it).
    let motion: PresetMotionStore?
    /// PRE-005: preset ID → the thumbnail ID its score came from and the score (current ones only).
    private(set) var motionEntries: [String: PresetMotionIndex.Entry] = [:]
    /// PRE-005: called on the main actor whenever `motionEntries` changes.
    var onMotionChanged: () -> Void = {}
    private let contents: ContentsProvider
    private let images = NSCache<NSString, UIImage>()
    /// PRE-002: the stable IDs put in `images`, per preset ID, so a changed preset's pictures can be evicted.
    private var memoryIDs: [String: Set<String>] = [:]

    /// `Library/Caches/PresetThumbnails` (inside FILE-009's Caches root, `StorageLocations`).
    nonisolated static func defaultDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches", isDirectory: true)
        return caches.appendingPathComponent(PresetThumbnailCache.folderName, isDirectory: true)
    }

    /// `Library/Caches/PresetColors` (PRE-004; FILE-009's Caches root, emptied by Clear Caches).
    nonisolated static func defaultColorDirectory() -> URL {
        defaultDirectory().deletingLastPathComponent().appendingPathComponent(PresetColorStore.folderName, isDirectory: true)
    }

    /// `Library/Caches/PresetMotion` (PRE-005; FILE-009's Caches root, emptied by Clear Caches).
    nonisolated static func defaultMotionDirectory() -> URL {
        defaultDirectory().deletingLastPathComponent().appendingPathComponent(PresetMotionStore.folderName, isDirectory: true)
    }

    init(cache: PresetThumbnailCache, colors: PresetColorStore? = nil, motion: PresetMotionStore? = nil,
         contents: @escaping ContentsProvider) {
        self.cache = cache
        self.colors = colors
        self.motion = motion
        self.contents = contents
        images.countLimit = 300
    }

    /// The decoded picture when it is already in memory (no work, no waiting).
    func memoryImage(for preset: IndexedPreset) -> UIImage? {
        images.object(forKey: PresetThumbnailKey(preset: preset, spec: cache.spec).stableID as NSString)
    }

    /// The preset's picture, generated if needed; nil when it cannot be made now or at all, and at
    /// once for a preset the user cannot play (locked or excluded: nothing is drawn for it). Cancelled
    /// with the calling task (a row that scrolled away).
    func image(for preset: IndexedPreset, playable: Bool) async -> UIImage? {
        guard playable else { return nil }
        let key = PresetThumbnailKey(preset: preset, spec: cache.spec)
        if let image = images.object(forKey: key.stableID as NSString) { return image }
        let provider = contents
        let loader: PresetThumbnailCache.ContentsLoader = { @MainActor in try await provider(preset) }
        guard let url = try? await cache.thumbnail(for: key, contents: loader) else { return nil }
        let wantsColors: Bool = colors != nil && colorEntries[preset.id]?.thumbnailID != key.stableID
        let wantsMotion: Bool = motion != nil && motionEntries[preset.id]?.thumbnailID != key.stableID   // PRE-005
        let decoded: Decoded = await Task.detached(priority: .utility) { () -> Decoded in
            guard let data = try? Data(contentsOf: url) else { return Decoded(image: nil, colors: [], score: nil) }
            let families: [PresetColorFamily] = wantsColors ? PresetColorPNG.dominantFamilies(data) : []
            let score: Int? = wantsMotion ? PresetMotionPNG.score(in: data) : nil
            return Decoded(image: UIImage(data: data)?.preparingForDisplay(), colors: families, score: score)
        }.value
        if !decoded.colors.isEmpty { recordColors(decoded.colors, presetID: preset.id, thumbnailID: key.stableID) }
        if let score = decoded.score { recordMotion(score, presetID: preset.id, thumbnailID: key.stableID) }
        let image: UIImage? = decoded.image
        if let image {
            images.setObject(image, forKey: key.stableID as NSString)
            memoryIDs[preset.id, default: []].insert(key.stableID)
        }
        return image
    }

    // MARK: - Invalidation (PRE-002, contract C3)

    /// A preset's content changed (`keepingContentHash` is its new hash) or it left the library
    /// (nil): its other pictures leave memory and the cache (entries, files); nothing else is touched.
    func invalidate(presetID: String, keepingContentHash: String?) async {
        let keep = keepingContentHash.map { (hash: String) -> String in
            PresetThumbnailKey(presetID: presetID, contentHash: hash, rendererVersion: cache.spec.rendererVersion).stableID
        }
        for id in memoryIDs[presetID] ?? [] where id != keep { images.removeObject(forKey: id as NSString) }
        memoryIDs[presetID] = keep.flatMap { (id: String) -> Set<String>? in memoryIDs[presetID]?.contains(id) == true ? [id] : nil }
        await cache.invalidate(presetID: presetID, keepingContentHash: keepingContentHash)
        if let entry = colorEntries[presetID], entry.thumbnailID != keep {   // PRE-004-R10
            colorEntries[presetID] = nil
            onColorsChanged()
        }
        await colors?.invalidate(presetID: presetID, keepingThumbnailID: keep)
        if let entry = motionEntries[presetID], entry.thumbnailID != keep {   // PRE-005-R11
            motionEntries[presetID] = nil
            onMotionChanged()
        }
        await motion?.invalidate(presetID: presetID, keepingThumbnailID: keep)
    }

    /// What the detached decode found (PRE-004 colours, PRE-005 score).
    private struct Decoded: Sendable {
        let image: UIImage?
        let colors: [PresetColorFamily]
        let score: Int?
    }

    // MARK: - Colours (PRE-004)

    private func recordColors(_ families: [PresetColorFamily], presetID: String, thumbnailID: String) {
        let entry = PresetColorIndex.Entry(thumbnailID: thumbnailID, colors: families)
        guard colorEntries[presetID] != entry else { return }
        colorEntries[presetID] = entry
        onColorsChanged()
        guard let colors else { return }
        Task.detached(priority: .utility) { await colors.record(presetID: presetID, thumbnailID: thumbnailID, colors: families) }
    }

    // MARK: - Motion (PRE-005)

    private func recordMotion(_ score: Int, presetID: String, thumbnailID: String) {
        let entry = PresetMotionIndex.Entry(thumbnailID: thumbnailID, score: score)
        guard motionEntries[presetID] != entry else { return }
        motionEntries[presetID] = entry
        onMotionChanged()
        guard let motion else { return }
        Task.detached(priority: .utility) { await motion.record(presetID: presetID, thumbnailID: thumbnailID, score: score) }
    }

    /// The launch collection for scores (PRE-005-R11): prunes like the colours, then returns what is left.
    nonisolated static func loadMotion(_ store: PresetMotionStore, listing: [String: String]) async -> [String: PresetMotionIndex.Entry] {
        await store.retainOnly(listing)
        return await store.snapshot()
    }

    func mergeLoadedMotion(_ loaded: [String: PresetMotionIndex.Entry]) {
        guard !loaded.isEmpty else { return }
        for (id, entry) in loaded where motionEntries[id] == nil { motionEntries[id] = entry }
        onMotionChanged()
    }

    /// The launch collection (PRE-004-R10): drops stored colours of presets not listed with their
    /// current thumbnail ID, then fills the mirror from what is left. Entries already learned this
    /// session are kept.
    nonisolated static func loadColors(_ store: PresetColorStore, listing: [String: String]) async -> [String: PresetColorIndex.Entry] {
        await store.retainOnly(listing)
        return await store.snapshot()
    }

    func mergeLoadedColors(_ loaded: [String: PresetColorIndex.Entry]) {
        guard !loaded.isEmpty else { return }
        for (id, entry) in loaded where colorEntries[id] == nil { colorEntries[id] = entry }
        onColorsChanged()
    }

    /// The colour listing: every listed preset's ID → its current thumbnail ID.
    nonisolated static func colorListing(_ library: PresetLibrary, spec: PresetThumbnailSpec) -> [String: String] {
        Dictionary(library.presets.map { (preset: IndexedPreset) -> (String, String) in
            (preset.id, PresetThumbnailKey(preset: preset, spec: spec).stableID)
        }, uniquingKeysWith: { (first: String, _: String) -> String in first })
    }

    /// The launch collection's listing (PRE-002-R7): every listed preset's ID → content hash.
    nonisolated static func listing(_ library: PresetLibrary) -> [String: String] {
        Dictionary(library.presets.map { (preset: IndexedPreset) -> (String, String) in (preset.id, preset.hash) },
                   uniquingKeysWith: { (first: String, _: String) -> String in first })
    }
}

/// Draws through the renderer's `presetThumbnails` and encodes PNG (contract C1, C4).
struct RendererThumbnailRenderer: PresetThumbnailRendering {
    /// Long enough for a heavy preset's shader compiles on a simulator; a device needs about 1 s.
    static let timeout: Duration = .seconds(20)

    let drawing: @MainActor @Sendable () -> (any PresetThumbnailDrawing)?

    func render(_ contents: Data, spec: PresetThumbnailSpec) async throws -> Data {
        guard let drawer = await drawing() else { throw PresetThumbnailError.unavailable("No renderer draws thumbnails.") }
        let frames = SyntheticPCM.frames(spec)
        let samples: [Int] = PresetMotionScore.sampleFrames.filter { (index: Int) -> Bool in index < frames.count - 1 }
        let result = await drawer.drawSamples(contents, width: spec.width, height: spec.height, frames: frames,
                                              sampleFrames: samples, timeout: Self.timeout)
        switch result.picture {
        case .pixels(let pixels):
            guard let png = PNGThumbnailEncoder.png(rgba: pixels, width: spec.width, height: spec.height) else {
                throw PresetThumbnailError.failed("The thumbnail could not be encoded.")
            }
            return Self.withMotion(png, samples: result.samples, picture: pixels, spec: spec)
        case .failed(let message): throw PresetThumbnailError.failed(message)
        case .unavailable(let message): throw PresetThumbnailError.unavailable(message)
        }
    }
}

extension RendererThumbnailRenderer {
    /// PRE-005: the PNG with the motion score of the samples and the final picture; unchanged when the
    /// drawer returned no samples (the picture still works, the preset just has no class).
    static func withMotion(_ png: Data, samples: [Data], picture: Data, spec: PresetThumbnailSpec) -> Data {
        guard !samples.isEmpty else { return png }
        let frames: [[UInt8]] = (samples + [picture]).map { (sample: Data) -> [UInt8] in [UInt8](sample) }
        guard let score = PresetMotionScore.score(samples: frames, width: spec.width, height: spec.height),
              let tagged = PresetMotionPNG.embed(score: score, in: png) else { return png }
        return tagged
    }
}

/// RGBA8 rows (top first) to PNG with ImageIO; opaque, since a preset frame has no transparency.
enum PNGThumbnailEncoder {
    static func png(rgba: Data, width: Int, height: Int) -> Data? {
        guard width > 0, height > 0, rgba.count == width * height * 4,
              let provider = CGDataProvider(data: rgba as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

#if DEBUG
/// `-uitestThumbnailFixture` (PresetThumbnailUITests): draws a two-colour picture from the preset's
/// bytes instantly, through the same cache and encoder, so the UI test does not wait seconds per
/// simulator shader compile. The real drawing is tested in ANGLERendering (PresetThumbnailRunnerTests).
struct FixtureThumbnailRenderer: PresetThumbnailRendering {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "uitestThumbnailFixture") }

    func render(_ contents: Data, spec: PresetThumbnailSpec) async throws -> Data {
        let seed = contents.reduce(UInt8(0)) { $0 &+ $1 }
        var pixels = Data(count: spec.width * spec.height * 4)
        for y in 0..<spec.height {
            for x in 0..<spec.width {
                let offset = (y * spec.width + x) * 4
                pixels[offset] = seed &+ UInt8(truncatingIfNeeded: x * 2)
                pixels[offset + 1] = UInt8(truncatingIfNeeded: y * 3)
                pixels[offset + 2] = 200
                pixels[offset + 3] = 255
            }
        }
        guard let png = PNGThumbnailEncoder.png(rgba: pixels, width: spec.width, height: spec.height) else {
            throw PresetThumbnailError.failed("fixture")
        }
        return PresetMotionPNG.embed(score: Self.fixtureScores[Int(seed % 3)], in: png) ?? png   // PRE-005
    }

    /// PRE-005: one score per class, chosen by the preset bytes (Calm, Moderate, Energetic).
    static let fixtureScores: [Int] = [1_000, 8_000, 30_000]
}
#endif
