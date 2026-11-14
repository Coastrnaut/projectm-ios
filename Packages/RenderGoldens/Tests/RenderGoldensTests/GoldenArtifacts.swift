// GoldenArtifacts.swift — golden files and failure artifacts for the GPU tests (QA-002-R6, R8, R10;
// data-model "Diff artifact set"). PNG coding is REC-001's, so this file needs ImageIO.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Foundation
import GoldenImages
import SceneRenderHarness
import XCTest

/// One platform class's golden folder.
struct GoldenStore {
    let folder: URL
    let platform: GoldenPlatformClass

    var manifestURL: URL { folder.appendingPathComponent(GoldenManifest.fileName) }

    func manifest() -> GoldenManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? GoldenManifest.decode(data)
    }

    /// The decoded golden of `entry`, or nil when its file is missing or unreadable.
    func image(_ entry: GoldenManifestEntry) -> GoldenImage? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(entry.file)) else { return nil }
        return GoldenPNG.decode(data)
    }

    /// QA-002-R10: writes `image` and its entry unless the listed golden already has these pixels.
    /// Returns true when something was written.
    @discardableResult
    func record(_ image: GoldenImage, scene: String, resolution: GoldenResolution, frame: Int, osSensitive: Bool,
                gpu: String) throws -> Bool {
        var manifest = manifest() ?? GoldenManifest(platform: platform.rawValue, recordedOS: GoldenOS.currentVersion, recordedGPU: gpu)
        let pixelHash = image.pixelSHA256
        if let existing = manifest.entry(scene: scene, width: resolution.width, frame: frame), existing.pixelSHA256 == pixelHash,
           FileManager.default.fileExists(atPath: folder.appendingPathComponent(existing.file).path) {
            return false
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = GoldenSceneCatalog.goldenFileName(scene: scene, resolution: resolution, frame: frame)
        let png = try GoldenPNG.encode(image)
        // The golden must read back to exactly these pixels, or its pixel hash would never match.
        guard GoldenPNG.decode(png) == image else { throw GoldenRenderError.captureFailed("\(file): PNG does not round-trip") }
        try png.write(to: folder.appendingPathComponent(file), options: .atomic)
        manifest.recordedOS = GoldenOS.currentVersion
        manifest.recordedGPU = gpu
        manifest.upsert(GoldenManifestEntry(scene: scene, frame: frame, width: resolution.width, height: resolution.height, file: file,
                                            pixelSHA256: pixelHash, fileSHA256: GoldenSHA256.hex([UInt8](png)), osSensitive: osSensitive))
        try manifest.encoded().write(to: manifestURL, options: .atomic)
        return true
    }
}

/// Expected, actual and diff images plus a summary for one capture (QA-002-R8).
enum GoldenArtifacts {
    struct Written {
        var folder: URL
        var files: [URL] = []
        var problem: String?
    }

    /// Attaches the images to `test` (kept always, so they are in the .xcresult) and writes them to
    /// `<root>/<class>/<capture>/`, appending one line to `<root>/<class>/summary.txt`.
    @discardableResult
    static func write(capture: String, expected: GoldenImage?, actual: GoldenImage, comparison: GoldenComparisonResult?,
                      root: URL, platform: GoldenPlatformClass, test: XCTestCase?) -> Written {
        let classFolder = root.appendingPathComponent(platform.rawValue, isDirectory: true)
        var written = Written(folder: classFolder.appendingPathComponent(capture, isDirectory: true))
        var images: [(String, GoldenImage)] = [("actual.png", actual)]
        if let expected {
            images.insert(("expected.png", expected), at: 0)
            // QA-003: the diff image uses the comparison's own tolerance (forgiven pixels, bounding box).
            let tolerance: GoldenTolerance = comparison?.report?.tolerance ?? .golden
            images.append(("diff.png", GoldenDiffImage.make(expected: expected, actual: actual, tolerance: tolerance)))
        }
        let summary = "\(capture) [\(platform.rawValue)]: " + (comparison?.summary ?? "no golden")
        do {
            try FileManager.default.createDirectory(at: written.folder, withIntermediateDirectories: true)
        } catch {
            written.problem = "diff folder \(written.folder.path) not writable: \(error)"
        }
        for (name, image) in images {
            guard let png = try? GoldenPNG.encode(image) else { continue }
            if let test {
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = "\(capture) \(name)"
                attachment.lifetime = .keepAlways
                test.add(attachment)
            }
            guard written.problem == nil else { continue }
            let url = written.folder.appendingPathComponent(name)
            if (try? png.write(to: url, options: .atomic)) != nil { written.files.append(url) }
        }
        if let test {
            let attachment = XCTAttachment(string: summary)
            attachment.name = "\(capture) summary"
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }
        if written.problem == nil {
            let url = written.folder.appendingPathComponent("summary.txt")
            if (try? Data((summary + "\n").utf8).write(to: url, options: .atomic)) != nil { written.files.append(url) }
            appendLine(summary, to: classFolder.appendingPathComponent("summary.txt"))
        }
        return written
    }

    private static func appendLine(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
#endif
