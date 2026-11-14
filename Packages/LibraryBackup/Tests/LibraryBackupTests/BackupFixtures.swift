// BackupFixtures.swift — FILE-005: libraries in temporary sandboxes holding every record kind. Every
// preset text and scene is written for this repository.
import Foundation
import LocalPortability
import PresetLibrary
import SceneFormat
import ShowControl
import ShowStorage
import XCTest
@testable import LibraryBackup

enum BackupFixtures {
    static let now = Date(timeIntervalSince1970: 1_794_571_200)   // 2026-11-13 12:00:00 UTC

    static func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
    static func sceneID(_ n: Int) -> String { UUID(uuidString: String(format: "5CE7E000-0000-4000-8000-%012d", n))!.uuidString }
    static func presetID(_ n: Int) -> String { "user/00000000-0000-4000-8000-" + String(format: "%012d", n) }
    static func photoName(_ n: Int) -> String { String(format: "0000A000-0000-4000-8000-%012d", n) + ".png" }

    static func scene(_ n: Int, variant: Int = 0, name: String? = nil) -> SceneDocument {
        let content: SceneLayerContent = variant == 0 ? .linearSpectrum : .circularSpectrum
        return SceneDocument(id: sceneID(n), name: name ?? "Scene \(n)",
                             layers: [SceneLayer(instance: 1, content: content, values: variant > 1 ? ["rate": Double(variant)] : [:])])
    }

    static func sceneBytes(_ n: Int, variant: Int = 0) -> Data { Data(scene(n, variant: variant).encoded()) }

    /// A small valid Milkdrop preset, distinct per tag.
    static func presetText(_ tag: String) -> Data {
        let lines: [String] = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fRating=3.000000", "fDecay=0.960000",
                               "zoom=1.0" + String(tag.utf8.count), "wave_r=0.600000",
                               "per_frame_1=wave_r = 0.5 + 0.5*sin(time*1.1);", "per_frame_2=// " + tag,
                               "per_pixel_1=zoom = zoom + 0.02*sin(rad*6 + time);"]
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func record(_ n: Int, name: String, text: Data, state: UserPresetState = .playable, fullLibrary: Bool = false,
                       included: Bool = false) -> UserPreset {
        let bytes = [UInt8](text)
        var origin: PresetDuplicateOrigin?
        if fullLibrary || included {
            origin = PresetDuplicateOrigin(presetID: (fullLibrary ? "cream-of-the-crop/" : "included/") + name + ".milk", name: name,
                                           packID: fullLibrary ? "cream-of-the-crop" : PresetLibrary.includedSource,
                                           packTitle: fullLibrary ? "Cream of the Crop" : "Included",
                                           sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes),
                                           licenseStatement: "Example statement", requiresLibraryUnlock: fullLibrary)
        }
        return UserPreset(id: presetID(n), name: name, author: "Ann", originalFileName: name + ".milk",
                          sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes), byteCount: bytes.count,
                          importedAt: now, state: state, provenOnScreen: state == .playable,
                          quarantine: state == .quarantined ? PresetQuarantineReason(.engineRejected) : nil, warnings: [],
                          license: PresetLicenseMetadata(origin: origin == nil ? .userImport : .bundledDuplicate,
                                                         authorFromFileName: false, linesFound: []),
                          duplicateOf: origin, modifiedAt: n == 2 ? now.addingTimeInterval(60) : nil)
    }

    static func png(_ seed: UInt8) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: seed, count: 32))
    }

    static func sandbox(_ test: XCTestCase, _ label: String = "lib") -> LibraryFolders {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryBackupTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return LibraryFolders(root: root)
    }

    /// Settings as the app hands them over: included keys, plus device keys the backup must drop.
    static let settings: [String: LibrarySettingValue] = [
        "favorites": .strings([presetID(1), "included/Alpha.milk"]),
        "lastPresetID": .string(presetID(2)),
        "settings.visual": .string("circularSpectrum"),
        "settings.camera.zoom": .double(1.75),
        "settings.osc.port": .int(9_000),
        "settings.reduceFlashing": .bool(true),
        "settings.text.overlay": .data(Data("{\"version\":1}".utf8)),
        "settings.latencyOffset.microphone": .double(-12.5),
        "settings.osc.enabled": .bool(true),
        "settings.midi.enabled": .bool(true),
        "settings.video.id": .string("0000B000-0000-4000-8000-000000000001"),
        "notice.photosensitivityAcknowledged": .bool(true),
    ]

    /// Writes a library with every record kind: a three-cue show and its scenes, the current scene,
    /// presets (two imported, one copy of an Included preset, one copy of a full-library preset, one
    /// quarantined), two collections, a photo, and a video and imported audio that must stay out.
    static func populate(_ folders: LibraryFolders) throws {
        let store = ShowStore(directory: folders.url(.show))
        var list = ShowCueList(id: uuid(999), name: "Backup show")
        for n in 1...3 {
            try store.saveScene(scene(n, variant: n - 1))
            try list.append(sceneID: sceneID(n), label: "Cue \(n)", cueID: uuid(n))
        }
        _ = list.next()
        try store.save(list)
        try FileManager.default.createDirectory(at: folders.url(.currentScene), withIntermediateDirectories: true)
        try sceneBytes(9, variant: 2).write(to: folders.currentSceneFile)
        var records: [UserPreset] = []
        let presets: [(Int, String, UserPresetState, Bool, Bool)] = [
            (1, "Alpha", .playable, false, false), (2, "Beta", .pending, false, false), (3, "Gamma", .playable, false, true),
            (4, "Paid", .playable, true, false), (5, "Broken", .quarantined, false, false),
        ]
        let files = folders.presetTextsFolder
        let quarantine = folders.url(.presets).appendingPathComponent("quarantine", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
        for (n, name, state, paid, included) in presets {
            let text = presetText(name)
            let preset = record(n, name: name, text: text, state: state, fullLibrary: paid, included: included)
            records.append(preset)
            try text.write(to: (state == .quarantined ? quarantine : files).appendingPathComponent(preset.fileName))
        }
        try UserPresetsFile(presets: records).encode().write(to: folders.presetIndexFile)
        try FileManager.default.createDirectory(at: folders.url(.collections), withIntermediateDirectories: true)
        let collections = [PresetCollection(id: uuid(50).uuidString, name: "Party", presetIDs: [presetID(1), "included/Alpha.milk"]),
                           PresetCollection(id: uuid(51).uuidString, name: "Calm", presetIDs: [presetID(3)])]
        try PresetCollectionsFile(collections: collections).encode().write(to: folders.collectionsFile)
        try FileManager.default.createDirectory(at: folders.url(.photos), withIntermediateDirectories: true)
        try png(7).write(to: folders.url(.photos).appendingPathComponent(photoName(1)))
        let videos = folders.root.appendingPathComponent("Videos", isDirectory: true)
        let audio = folders.root.appendingPathComponent("AudioLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        try Data("VIDEO-PAYLOAD-MUST-NOT-LEAVE".utf8).write(to: videos.appendingPathComponent("0000B000-0000-4000-8000-000000000001.mov"))
        try Data("AUDIO-PAYLOAD-MUST-NOT-LEAVE".utf8).write(to: audio.appendingPathComponent("track.m4a"))
    }

    /// The backup bytes of a populated library.
    static func backup(of folders: LibraryFolders, settings: [String: LibrarySettingValue] = BackupFixtures.settings) throws -> Data {
        let contents = try LibraryContentsReader.read(folders: folders, settings: settings, videos: 1, importedAudio: 1)
        return try LibraryBackupWriter.write(contents, appVersion: "1.1 (2)", createdAt: now)
    }

    /// A settings sink for `applySettings`.
    final class SettingsSink: @unchecked Sendable {
        var values: [String: LibrarySettingValue]
        init(_ values: [String: LibrarySettingValue] = [:]) { self.values = values }
        func apply(_ changes: [String: LibrarySettingValue]) { for (key, value) in changes { values[key] = value } }
    }

    /// Plans and installs `backup` into `folders`; returns the outcome.
    static func restore(_ backup: Data, into folders: LibraryFolders, sink: SettingsSink, choice: LibraryRestoreChoice = .keepBoth,
                        overrides: [String: LibraryRestoreChoice] = [:],
                        configure: (LibraryRestoreInstaller) -> Void = { (_: LibraryRestoreInstaller) in }) throws -> LibraryRestoreOutcome {
        let contents = try LibraryBackupReader.read(backup).contents
        let library = try LibraryContentsReader.read(folders: folders, settings: sink.values)
        let plan = LibraryRestorePlanner.plan(backup: contents, library: library, choice: choice, overrides: overrides)
        let installer = LibraryRestoreInstaller(folders: folders)
        configure(installer)
        return installer.install(backup: contents, plan: plan, settings: sink.values) { (values: [String: LibrarySettingValue]) in
            sink.apply(values)
        }
    }
}
