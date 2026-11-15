// NativePipelineArchive.swift — PERF-009 (contracts/warm-cache.md W6; research PERF-009-D4-D6): a Metal binary
// archive of the app's own native render pipelines, kept in the warm-start cache between launches.
//
// The archive file is opened only when its key matches exactly: app version, build, OS version, GPU family, format
// and the SHA-256 of every shader source whose pipelines use it. Any change means the file is deleted, never
// opened. As a second guard, Metal itself looks pipelines up by function hash, so a function whose source differs
// from what the archive holds is a miss and compiles normally.
//
// With an archive from disk, a pipeline is first made with `.failOnBinaryArchiveMiss`: success is a hit (served
// from the archive, counted); a miss is made normally. Every pipeline not served from disk is queued, and
// `writeBack()` (called off the main thread when the app leaves the foreground) adds the queued pipelines and
// commits the archive through the store. Nothing here runs per frame.
//
// `shared` is set once by the app; with no shared archive (tests, RendererLab, other devices) pipelines are made
// exactly as before.
import Foundation

#if canImport(Metal) && !VISUAL_NO_METAL
/// The shader sources this module builds pipelines from through the archive (part of the archive's key).
public enum NativeShaderSources {
    public static var visualGenerators: [String] { [FlatShapePass.shaderSource, NoiseFieldGenerator.shaderSource] }   // VIS-013
}

import LocalPortability
import Metal

public final class NativePipelineArchive: @unchecked Sendable {
    public static let entryName = "native-pipelines"
    public static let formatVersion = 1

    public let device: MTLDevice
    /// What the store held at open (`hit`: the archive came from disk).
    public let outcome: WarmCacheOutcome
    public let key: WarmCacheKey
    private let store: WarmCacheStore
    private let lock = NSLock()
    /// nil when the device cannot make binary archives (`unsupported`).
    private var archive: MTLBinaryArchive?
    private var fromDisk: Bool
    private var pending: [MTLRenderPipelineDescriptor] = []
    private var hitCount = 0
    private var missCount = 0

    /// Pipelines served from the archive on disk.
    public var hits: Int { lock.withLock { hitCount } }
    /// Pipelines made normally (no archive from disk, or not in it).
    public var misses: Int { lock.withLock { missCount } }
    /// Pipelines waiting for `writeBack()`.
    public var pendingCount: Int { lock.withLock { pending.count } }

    /// The key for `sources` on `device`.
    public static func key(device: MTLDevice, identity: WarmStartIdentity, sources: [String]) -> WarmCacheKey {
        identity.key(gpuFamily: gpuFamily(of: device), formatVersion: formatVersion, contentHash: WarmCacheHash.sha256Hex(texts: sources))
    }

    /// "<device name>/apple<N>" with the highest Apple GPU family supported, or "/other".
    public static func gpuFamily(of device: MTLDevice) -> String {
        for raw in stride(from: 1020, through: 1001, by: -1) {
            if let family = MTLGPUFamily(rawValue: raw), device.supportsFamily(family) {
                return "\(device.name)/apple\(raw - 1000)"
            }
        }
        return "\(device.name)/other"
    }

    /// Opens the stored archive when its key matches; otherwise starts an empty one (a stale or damaged entry is
    /// deleted by the store, a file Metal refuses is deleted here).
    public static func open(device: MTLDevice, store: WarmCacheStore, identity: WarmStartIdentity,
                            sources: [String]) -> NativePipelineArchive {
        let key = key(device: device, identity: identity, sources: sources)
        let (found, url) = store.lookup(entryName, key: key)
        var outcome = found
        var archive: MTLBinaryArchive?
        if let url {
            let descriptor = MTLBinaryArchiveDescriptor()
            descriptor.url = url
            archive = try? device.makeBinaryArchive(descriptor: descriptor)
            if archive == nil {
                store.remove(entryName)
                outcome = .damaged(.decode)
            }
        }
        let fromDisk = archive != nil
        if archive == nil {
            archive = try? device.makeBinaryArchive(descriptor: MTLBinaryArchiveDescriptor())
            if archive == nil { outcome = .unsupported }
        }
        return NativePipelineArchive(device: device, store: store, key: key, outcome: outcome, archive: archive, fromDisk: fromDisk)
    }

    private init(device: MTLDevice, store: WarmCacheStore, key: WarmCacheKey, outcome: WarmCacheOutcome,
                 archive: MTLBinaryArchive?, fromDisk: Bool) {
        self.device = device
        self.store = store
        self.key = key
        self.outcome = outcome
        self.archive = archive
        self.fromDisk = fromDisk
    }

    /// A pipeline for `descriptor`, from the archive when it holds it (PERF-009-R6).
    public func makeRenderPipeline(_ descriptor: MTLRenderPipelineDescriptor) throws -> MTLRenderPipelineState {
        let (archive, fromDisk) = lock.withLock { (self.archive, self.fromDisk) }
        guard let archive else { return try device.makeRenderPipelineState(descriptor: descriptor) }
        if fromDisk {
            descriptor.binaryArchives = [archive]
            if let served = try? device.makeRenderPipelineState(descriptor: descriptor, options: [.failOnBinaryArchiveMiss]) {
                lock.withLock { hitCount += 1 }
                return served.0
            }
        }
        descriptor.binaryArchives = nil
        let state = try device.makeRenderPipelineState(descriptor: descriptor)
        let queued = descriptor.copy() as? MTLRenderPipelineDescriptor
        lock.withLock {
            missCount += 1
            if let queued { pending.append(queued) }
        }
        return state
    }

    /// Adds the queued pipelines and stores the archive (payload first, key last). Returns how many were added;
    /// 0 when nothing was queued or the archive is unsupported. Never call it on the render path.
    @discardableResult
    public func writeBack() throws -> Int {
        let (archive, queued) = lock.withLock { () -> (MTLBinaryArchive?, [MTLRenderPipelineDescriptor]) in
            let queued = pending
            pending.removeAll()
            return (self.archive, queued)
        }
        guard let archive, !queued.isEmpty else { return 0 }
        do {
            for descriptor in queued { try archive.addRenderPipelineFunctions(descriptor: descriptor) }
            let scratch = try store.temporaryURL(for: Self.entryName)
            try? FileManager.default.removeItem(at: scratch)
            try archive.serialize(to: scratch)
            try store.commit(Self.entryName, key: key, fileAt: scratch)
        } catch {
            lock.withLock { pending.insert(contentsOf: queued, at: 0) }
            throw error
        }
        lock.withLock { fromDisk = true }   // the archive now holds them; later misses queue again
        return queued.count
    }

    // MARK: - The app's shared archive

    private static let slotLock = NSLock()
    nonisolated(unsafe) private static var slot: NativePipelineArchive?

    /// Set once by the app at launch; nil restores plain pipeline creation.
    public static var shared: NativePipelineArchive? {
        get { slotLock.withLock { slot } }
        set { slotLock.withLock { slot = newValue } }
    }

    /// Through `shared` when it was opened for `device`, otherwise `device.makeRenderPipelineState` as before.
    public static func makeRenderPipelineState(device: MTLDevice, descriptor: MTLRenderPipelineDescriptor) throws -> MTLRenderPipelineState {
        if let archive = shared, archive.device === device { return try archive.makeRenderPipeline(descriptor) }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
#endif
