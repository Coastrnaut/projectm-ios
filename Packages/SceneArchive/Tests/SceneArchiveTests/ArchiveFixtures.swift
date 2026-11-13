// ArchiveFixtures.swift — the FILE-001 fixture scene, its media and a hand builder for hostile
// archives (FILE-001-T09, T13).
import Foundation
import GeneratorGraph
import LocalPortability
import MediaSniffing
import ParameterGraph
import ProceduralMaterials
@testable import SceneArchive
@testable import SceneFormat
import TextLayer
import VisualParameters

enum ArchiveFixtures {
    static let sceneID = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
    static let photoID = "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"
    static let videoID = "F0E1D2C3-B4A5-9687-7869-5A4B3C2D1E0F"
    static let date = Date(timeIntervalSince1970: 1_794_571_200)   // 2026-11-13T12:00:00Z

    static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: VisualParameterCatalog.descriptors + ProceduralMaterialCatalog.descriptors)
    }

    static func json(_ data: Data) throws -> SceneJSON { try SceneJSONParser.parse(Array(data), maximumDepth: 32) }

    static let pngBytes = Data(MediaFixtureBytes.png(width: 4, height: 3))
    static let movieBytes = Data(MediaFixtureBytes.movie())

    /// Photo, video, text and generator graph layers; an unknown asset type and unknown fields.
    static func scene(unusedPhoto: Bool = false) throws -> SceneDocument {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var assets: [String: SceneAsset] = [
            "photo1": .photo(storeID: photoID),
            "clip": SceneAsset(.video(storeID: videoID), extra: ["futureNote": .string("kept")]),
            "caption": SceneAsset(.text(spec: try json(TextOverlaySpec(message: "Night Drive").encodedForStorage()))),
            "graph1": SceneAsset(.generatorGraph(document: try json(try encoder.encode(GeneratorGraphExamples.emberDrift)))),
            "future": SceneAsset(.unknown(type: "hologram"), extra: ["beam": .string("blue")]),
        ]
        var layers: [SceneLayer] = [
            SceneLayer(instance: 1, content: .camera),
            SceneLayer(instance: 2, content: .video(asset: "clip"), composite: SceneComposite(opacity: 0.5)),
            SceneLayer(instance: 3, content: .text(asset: "caption")),
            SceneLayer(instance: 7, content: .generatorGraph(asset: "graph1")),
        ]
        if !unusedPhoto { layers.insert(SceneLayer(instance: 5, content: .photo(asset: "photo1")), at: 1) }
        if unusedPhoto { assets["photo1"] = .photo(storeID: photoID) }
        return SceneDocument(id: sceneID, name: "Night Drive", layers: layers,
                             parameters: [VisualParameterIDs.circularSpectrumGap: .continuous(0.1)],
                             assets: assets, extra: ["futureTopLevel": .bool(true)])
    }

    static func media() -> [SceneArchiveMedia] {
        [SceneArchiveMedia(key: "clip", type: .video, fileExtension: "mov", data: movieBytes),
         SceneArchiveMedia(key: "photo1", type: .photo, fileExtension: "png", data: pngBytes)]
    }

    static func archive() throws -> Data {
        try SceneArchiveWriter.data(document: try scene(), media: media(), registry: try registry(), modified: date)
    }

    /// A scene with only the camera (no media).
    static func plainScene() -> SceneDocument {
        SceneDocument(id: sceneID, name: "Plain", layers: [SceneLayer(instance: 1, content: .camera)])
    }

    /// A hand-built archive: `files` are written and listed with their checksums (unless in
    /// `unlisted`), then the manifest with `records` and the header fields given.
    static func handBuilt(files: [(String, Data)], records: [SceneArchiveAssetRecord], unlisted: Set<String> = [],
                          listedButAbsent: [String] = [], format: String = SceneArchiveFormat.formatName, version: Int = 1,
                          scene: String = SceneArchiveFormat.scenePath) throws -> Data {
        var out = Data()
        let zip = StoredZipWriter(modified: date) { (chunk: Data) in out.append(chunk) }
        var listed: [[String: Any]] = []
        for (path, data) in files {
            try zip.add(path: path, data: data)
            if !unlisted.contains(path) {
                listed.append(["path": path, "sha256": PortableSHA256.hex(data), "byteCount": data.count])
            }
        }
        for path in listedButAbsent {
            listed.append(["path": path, "sha256": PortableSHA256.hex(Data()), "byteCount": 0])
        }
        let manifest: [String: Any] = [
            "format": format, "formatVersion": version, "files": listed, "scene": scene,
            "assets": records.map { (r: SceneArchiveAssetRecord) -> [String: Any] in ["key": r.key, "type": r.type, "path": r.path] },
        ]
        try zip.add(path: "manifest.json", data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]))
        try zip.finish()
        return out
    }

    static var photoRecord: SceneArchiveAssetRecord { SceneArchiveAssetRecord(key: "photo1", type: "photo", path: "assets/photo1.png") }
    static var videoRecord: SceneArchiveAssetRecord { SceneArchiveAssetRecord(key: "clip", type: "video", path: "assets/clip.mov") }

    static func sceneBytes(_ document: SceneDocument) -> Data { Data(document.encoded()) }

    /// The fixture's files and records, for hostile variants.
    static func standardFiles() throws -> [(String, Data)] {
        [("scene.json", sceneBytes(try scene())), ("assets/clip.mov", movieBytes), ("assets/photo1.png", pngBytes)]
    }

    /// Replaces every occurrence of `from` with `to` (same length) in the ZIP headers' bytes.
    static func patch(_ data: Data, _ from: String, _ to: String) -> Data {
        precondition(from.utf8.count == to.utf8.count)
        var bytes = [UInt8](data)
        let f = Array(from.utf8), t = Array(to.utf8)
        var i = 0
        while i + f.count <= bytes.count {
            if Array(bytes[i..<(i + f.count)]) == f {
                bytes.replaceSubrange(i..<(i + f.count), with: t)
                i += f.count
            } else {
                i += 1
            }
        }
        return Data(bytes)
    }
}
