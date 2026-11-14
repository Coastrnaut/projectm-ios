// WarmStartCache.swift — PERF-009 (specs/229-perf-009-startup-warm-cache, contracts/warm-cache.md): the app's
// startup warm cache in `Library/Caches/WarmStart` (inside FILE-010's Caches root, so Clear Caches empties it).
//
// * The preset library loads through it (`PresetLibrary.load(from:store:identity:)`): a valid snapshot skips the
//   index decode, sort and search-key folding; anything stale or damaged is deleted and rebuilt.
// * The native pipeline archive (`NativePipelineArchive.shared`) is opened at launch off the main actor and written
//   back when the scene leaves the foreground (only if new pipelines were made).
// * Each step is a Points of Interest signpost interval ("WarmStart library", "WarmStart pipeline archive") whose
//   outcome label is private like every dynamic value (PERF-009-R9).
//
// Only bundle-derived data is stored (PERF-009-R1): no user presets, settings or identifiers, and no UserDefaults key.
import Diagnostics
import Foundation
import LocalPortability
import Metal
import PresetLibrary
import VisualGenerators
import Compositor

@MainActor
final class WarmStartCache {
    static let folderName = "WarmStart"

    let store: WarmCacheStore?
    let identity: WarmStartIdentity
    /// The library step's outcome and duration (AutomationRunner perf009).
    private(set) var libraryOutcome: WarmCacheOutcome?
    private(set) var libraryLoadMs: Double?
    private(set) var archiveOutcome: WarmCacheOutcome?
    private var writeBackRunning = false

    init(store: WarmCacheStore?, identity: WarmStartIdentity) {
        self.store = store
        self.identity = identity
    }

    /// The real cache folder, or nil when the Caches folder cannot be found (the launch then works without one).
    static func standard(bundle: Bundle = .main) -> WarmStartCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let store = caches.map { (url: URL) -> WarmCacheStore in
            WarmCacheStore(directory: url.appendingPathComponent(folderName, isDirectory: true))
        }
        return WarmStartCache(store: store, identity: identity(bundle: bundle))
    }

    static func identity(bundle: Bundle) -> WarmStartIdentity {
        WarmStartIdentity(infoDictionary: bundle.infoDictionary, osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
    }

    /// The archived shader sources: the native spectra and the compositor (their hash is part of the key).
    static var archivedShaderSources: [String] { NativeShaderSources.visualGenerators + CompositorShaderSources.archived }

    /// PERF-009-D9 cold launches: empties the folder before anything reads it.
    func clear() { store?.clear() }

    /// The preset library through the warm cache (signpost "WarmStart library").
    func loadLibrary(bundle: Bundle = .main) async throws -> PresetLibrary {
        let signposter = DiagnosticsLog.signposter
        let state = signposter.beginInterval("WarmStart library")
        let clock = UptimeWarmStartClock()
        let start = clock.nowNanoseconds()
        do {
            let result = try await PresetLibrary.load(from: bundle, store: store, identity: identity)
            libraryOutcome = result.outcome
            libraryLoadMs = Double(clock.nowNanoseconds() - start) / 1_000_000
            signposter.endInterval("WarmStart library", state, "\(result.outcome.label, privacy: .private)")
            return result.value
        } catch {
            signposter.endInterval("WarmStart library", state, "failed")
            throw error
        }
    }

    /// Opens the pipeline archive off the main actor and installs it as the shared one (signpost "WarmStart pipeline
    /// archive"). Without Metal or a store nothing changes.
    func openPipelineArchive() {
        guard let store, NativePipelineArchive.shared == nil, let device = MTLCreateSystemDefaultDevice() else { return }
        let identity = identity
        let sources = Self.archivedShaderSources
        Task.detached(priority: .utility) { [weak self] in
            let signposter = DiagnosticsLog.signposter
            let state = signposter.beginInterval("WarmStart pipeline archive")
            let archive = NativePipelineArchive.open(device: device, store: store, identity: identity, sources: sources)
            signposter.endInterval("WarmStart pipeline archive", state, "\(archive.outcome.label, privacy: .private)")
            if NativePipelineArchive.shared == nil { NativePipelineArchive.shared = archive }
            await MainActor.run { self?.archiveOutcome = archive.outcome }
        }
    }

    /// Writes the archive back when the scene leaves the foreground (PERF-009-R6), off the main actor.
    func sceneBecame(active: Bool) {
        guard !active, !writeBackRunning, let archive = NativePipelineArchive.shared, archive.pendingCount > 0 else { return }
        writeBackRunning = true
        Task.detached(priority: .utility) { [weak self] in
            _ = try? archive.writeBack()   // a failure only means the next launch compiles again (R7)
            await MainActor.run { self?.writeBackRunning = false }
        }
    }
}
