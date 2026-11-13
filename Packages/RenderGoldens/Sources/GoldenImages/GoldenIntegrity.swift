// GoldenIntegrity.swift — the golden set's consistency and size check (QA-002-R14; contract G5).
// Reads files and hashes only (no PNG decoding), so it runs on Linux and on CI hosts without a GPU.
import Foundation

public enum GoldenIntegrityIssue: Sendable, Equatable, CustomStringConvertible {
    case unreadableManifest(platform: String)
    case platformMismatch(folder: String, manifest: String)
    case missingFile(platform: String, file: String)
    case fileHashMismatch(platform: String, file: String)
    case badFileName(platform: String, file: String)
    case duplicateEntry(platform: String, file: String)
    case unknownScene(platform: String, scene: String)
    case missingEntry(platform: String, file: String)
    case unlistedFile(platform: String, file: String)
    case overBudget(bytes: Int, limit: Int)

    public var description: String {
        switch self {
        case let .unreadableManifest(p): "\(p): manifest.json missing or unreadable"
        case let .platformMismatch(folder, manifest): "folder \(folder) holds a manifest for \(manifest)"
        case let .missingFile(p, f): "\(p): \(f) is listed but missing"
        case let .fileHashMismatch(p, f): "\(p): \(f) does not match its fileSHA256"
        case let .badFileName(p, f): "\(p): \(f) does not follow <scene>-<w>x<h>-f<frame>.png"
        case let .duplicateEntry(p, f): "\(p): \(f) is listed twice"
        case let .unknownScene(p, s): "\(p): \(s) is not a catalog scene"
        case let .missingEntry(p, f): "\(p): no golden \(f) (record it with GOLDEN_RECORD=1)"
        case let .unlistedFile(p, f): "\(p): \(f) is not in the manifest"
        case let .overBudget(bytes, limit): "the golden set is \(bytes) bytes (limit \(limit))"
        }
    }
}

public enum GoldenIntegrity {
    /// QA-002-R14: every class's PNGs and manifests together.
    public static let budgetBytes = 2_000_000

    /// Checks every class folder under `goldensRoot` (`Goldens/<class>/`). A class folder that exists
    /// must be complete for the catalog.
    public static func check(goldensRoot: URL, runs: [GoldenSceneRun] = GoldenSceneCatalog.runs,
                             resolutions: [GoldenResolution] = GoldenResolution.all) -> [GoldenIntegrityIssue] {
        var issues: [GoldenIntegrityIssue] = []
        var totalBytes = 0
        let fm = FileManager.default
        for platform in GoldenPlatformClass.allCases {
            let folder = goldensRoot.appendingPathComponent(platform.rawValue, isDirectory: true)
            guard fm.fileExists(atPath: folder.path) else { continue }
            let manifestURL = folder.appendingPathComponent(GoldenManifest.fileName)
            guard let data = try? Data(contentsOf: manifestURL), let manifest = try? GoldenManifest.decode(data) else {
                issues.append(.unreadableManifest(platform: platform.rawValue))
                continue
            }
            totalBytes += data.count
            if manifest.platform != platform.rawValue {
                issues.append(.platformMismatch(folder: platform.rawValue, manifest: manifest.platform))
            }
            var listed: Set<String> = []
            for entry in manifest.entries {
                if listed.contains(entry.file) { issues.append(.duplicateEntry(platform: platform.rawValue, file: entry.file)) }
                listed.insert(entry.file)
                let resolution = GoldenResolution(width: entry.width, height: entry.height)
                if entry.file != GoldenSceneCatalog.goldenFileName(scene: entry.scene, resolution: resolution, frame: entry.frame) {
                    issues.append(.badFileName(platform: platform.rawValue, file: entry.file))
                }
                if !runs.contains(where: { (r: GoldenSceneRun) -> Bool in r.name == entry.scene }) {
                    issues.append(.unknownScene(platform: platform.rawValue, scene: entry.scene))
                }
                guard let bytes = try? Data(contentsOf: folder.appendingPathComponent(entry.file)) else {
                    issues.append(.missingFile(platform: platform.rawValue, file: entry.file))
                    continue
                }
                if GoldenSHA256.hex([UInt8](bytes)) != entry.fileSHA256 {
                    issues.append(.fileHashMismatch(platform: platform.rawValue, file: entry.file))
                }
            }
            for run in runs {
                for resolution in resolutions {
                    for frame in run.capturedFrames {
                        let file = GoldenSceneCatalog.goldenFileName(scene: run.name, resolution: resolution, frame: frame)
                        if !listed.contains(file) { issues.append(.missingEntry(platform: platform.rawValue, file: file)) }
                    }
                }
            }
            let names = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
            for name in names where name.hasSuffix(".png") {
                let size = fileSize(folder.appendingPathComponent(name))
                totalBytes += size
                if !listed.contains(name) { issues.append(.unlistedFile(platform: platform.rawValue, file: name)) }
            }
        }
        if totalBytes > budgetBytes { issues.append(.overBudget(bytes: totalBytes, limit: budgetBytes)) }
        return issues
    }

    /// Total bytes of every class's PNGs and manifests (for the report).
    public static func totalBytes(goldensRoot: URL) -> Int {
        let fm = FileManager.default
        var total = 0
        for platform in GoldenPlatformClass.allCases {
            let folder = goldensRoot.appendingPathComponent(platform.rawValue, isDirectory: true)
            for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".png") || name == GoldenManifest.fileName {
                total += fileSize(folder.appendingPathComponent(name))
            }
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int { (try? Data(contentsOf: url))?.count ?? 0 }
}
