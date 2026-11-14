// ShowMediaRelink.swift — MED-013 (contract specs/146-med-013-media-relinking/contracts/media-relink.md L4;
// research MED-013-D4): which stored scenes use which media identifiers, and rewriting one identifier to
// another in every stored scene, all or nothing.
//
// Rewrite steps (a test hook can fail each one, per scene):
//   1. read and decode every stored scene; rewrite matching references in memory (SceneFormat
//      `replacingMediaReference`; unreadable scenes are counted and left alone);
//   2. `stage`: write each new scene as `<SCENE-ID>.scene.json.relink-new`;
//   3. `keepOriginal`: SCN-013's original backup of an older-format file (as `saveScene`);
//   4. per scene, `link`: keep the original as `<SCENE-ID>.scene.json.relink-old` (hard link, else a copy),
//      then `commit`: rename the new file over the scene file (rename(2), atomic in the folder);
//   5. remove the kept originals.
// A failure in 2-4 renames the kept originals back and removes the temporary files, so every scene file
// is byte for byte as before. Leftovers of an interrupted run are cleaned at the start of the next one
// (a kept original whose scene file is gone is put back). The temporary names do not end in
// `.scene.json`, so no reader ever takes them for a scene.
import Foundation
import SceneFormat
import ShowControl
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A media identifier in one store.
public struct ShowMediaKey: Sendable, Hashable, Comparable {
    public var store: SceneMediaStore
    public var storeID: String

    public init(store: SceneMediaStore, storeID: String) {
        self.store = store
        self.storeID = storeID
    }

    public static func < (a: ShowMediaKey, b: ShowMediaKey) -> Bool {
        a.store == b.store ? a.storeID < b.storeID : a.store < b.store
    }
}

/// Which stored scenes name each media identifier (read from the files on each call).
public struct ShowMediaUsage: Sendable, Equatable {
    public var scenes: [ShowMediaKey: Set<String>] = [:]
    /// Stored scenes that could not be decoded (their media is unknown).
    public var unreadableScenes: Set<String> = []

    public init() {}
}

public enum ShowMediaRewriteStep: String, Sendable, CaseIterable {
    case stage, keepOriginal, link, commit
}

public enum ShowMediaRewriteError: Error, Sendable, Equatable {
    /// An identifier is not a canonical UUID.
    case invalidIdentifier
    /// A step failed; every scene file is as it was.
    case failed(ShowMediaRewriteStep)
}

public struct ShowMediaRewriteReport: Sendable, Equatable {
    /// Scene IDs rewritten (sorted).
    public var scenes: [String] = []
    /// References replaced across them.
    public var references: Int = 0
    /// Stored scenes that could not be read and were left alone (sorted).
    public var unreadable: [String] = []

    public init() {}
}

extension ShowStore {
    static let relinkNewSuffix = ".relink-new"
    static let relinkOldSuffix = ".relink-old"

    /// Every photo and video identifier named by a readable stored scene, with the scenes naming it.
    public func mediaUsage() -> ShowMediaUsage {
        var usage = ShowMediaUsage()
        for id in storedSceneIDs() {
            guard let document = try? scene(id).document else {
                usage.unreadableScenes.insert(id)
                continue
            }
            for reference in document.mediaReferences {
                usage.scenes[ShowMediaKey(store: reference.store, storeID: reference.storeID), default: []].insert(id)
            }
        }
        return usage
    }

    /// Replaces `old` by `new` in every stored scene, all or nothing (MED-013-R6, R7).
    @discardableResult
    public func rewriteMediaReferences(store: SceneMediaStore, from old: String, to new: String,
                                       fault: ((ShowMediaRewriteStep, String) throws -> Void)? = nil)
        throws(ShowMediaRewriteError) -> ShowMediaRewriteReport {
        guard SceneDocument.isCanonicalUUID(old), SceneDocument.isCanonicalUUID(new) else { throw .invalidIdentifier }
        cleanUpRelinkLeftovers()
        var report = ShowMediaRewriteReport()
        var plan: [(id: String, document: SceneDocument)] = []
        for id in storedSceneIDs().sorted() {
            let document: SceneDocument
            do {
                document = try scene(id).document
            } catch {
                report.unreadable.append(id)
                continue
            }
            let (rewritten, count) = document.replacingMediaReference(store: store, from: old, to: new)
            guard count > 0 else { continue }
            plan.append((id, rewritten))
            report.references += count
        }
        report.scenes = plan.map(\.id)
        guard !plan.isEmpty else { return report }
        try apply(plan, fault: fault)
        return report
    }

    private func newURL(_ id: String) -> URL { URL(fileURLWithPath: sceneFile(id).path + Self.relinkNewSuffix) }
    private func oldURL(_ id: String) -> URL { URL(fileURLWithPath: sceneFile(id).path + Self.relinkOldSuffix) }

    private func apply(_ plan: [(id: String, document: SceneDocument)], fault: ((ShowMediaRewriteStep, String) throws -> Void)?)
        throws(ShowMediaRewriteError) {
        let files = FileManager.default
        func discardStaged() {
            for item in plan { try? files.removeItem(at: newURL(item.id)) }
        }
        // 2. Stage.
        for item in plan {
            do {
                try fault?(.stage, item.id)
                try Data(item.document.encoded()).write(to: newURL(item.id))
            } catch {
                discardStaged()
                throw .failed(.stage)
            }
        }
        // 3. SCN-013 originals.
        for item in plan {
            do {
                try fault?(.keepOriginal, item.id)
                try keepOriginalIfMigrated(sceneFile(item.id))
            } catch {
                discardStaged()
                throw .failed(.keepOriginal)
            }
        }
        // 4. Link and commit, scene by scene.
        var linked: [String] = []
        var committed: [String] = []
        func rollBack() {
            for id in linked {
                if committed.contains(id) {
                    _ = rename(oldURL(id).path, sceneFile(id).path)   // the original back over the new file
                } else {
                    try? files.removeItem(at: oldURL(id))
                }
            }
            discardStaged()
        }
        for item in plan {
            do {
                try fault?(.link, item.id)
                try? files.removeItem(at: oldURL(item.id))
                if (try? files.linkItem(at: sceneFile(item.id), to: oldURL(item.id))) == nil {
                    try files.copyItem(at: sceneFile(item.id), to: oldURL(item.id))
                }
                linked.append(item.id)
            } catch {
                rollBack()
                throw .failed(.link)
            }
            do {
                try fault?(.commit, item.id)
                guard rename(newURL(item.id).path, sceneFile(item.id).path) == 0 else { throw ShowStoreError.writeFailed }
                committed.append(item.id)
            } catch {
                rollBack()
                throw .failed(.commit)
            }
        }
        // 5. Clean up.
        for item in plan { try? files.removeItem(at: oldURL(item.id)) }
    }

    /// An interrupted rewrite: new files are removed; a kept original goes back when its scene file is
    /// gone and is removed otherwise.
    func cleanUpRelinkLeftovers() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: scenesFolder.path)) ?? []
        for name in names {
            let url = scenesFolder.appendingPathComponent(name, isDirectory: false)
            if name.hasSuffix(Self.sceneFileSuffix + Self.relinkNewSuffix) {
                try? FileManager.default.removeItem(at: url)
            } else if name.hasSuffix(Self.sceneFileSuffix + Self.relinkOldSuffix) {
                let main = scenesFolder.appendingPathComponent(String(name.dropLast(Self.relinkOldSuffix.count)), isDirectory: false)
                if FileManager.default.fileExists(atPath: main.path) {
                    try? FileManager.default.removeItem(at: url)
                } else {
                    try? FileManager.default.moveItem(at: url, to: main)
                }
            }
        }
    }
}
