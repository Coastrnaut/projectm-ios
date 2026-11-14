// UITestBrokenLibraryFixture.swift — DEBUG only: `-uitestBrokenLibrary` with `-uitestResetNotice`
// (PRE-018-T11; LibraryCheckUITests). Seeds one issue of every kind and every reference store:
//   * files (before the user presets load): "Textured" (a warp shader using a texture the app does not
//     have), "Lost" (its stored file deleted), "Broken" (stored without the [preset00] header, playable),
//     and "Clean";
//   * references (after the library is attached): a favorite, a tag, an adjustment, a collection entry
//     and a recently played entry, each naming a preset ID that does not exist.
// The preset text is written for this repository. `-uitestResetNotice` has already removed the folders.
#if DEBUG
import Foundation
import PresetLibrary

@MainActor
enum UITestBrokenLibraryFixture {
    static let argument = "-uitestBrokenLibrary"
    static let goneID = "user/00000000-0000-4000-8000-000000000018"
    static let collectionName = "Broken Party"

    private static var requested: Bool {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        return arguments.contains(argument) && arguments.contains("-uitestResetNotice")
    }

    static func text(header: Bool = true, warp: [String] = [], zoom: String) -> String {
        var lines: [String] = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2"]
        if header { lines.append("[preset00]") }
        lines += ["fDecay=0.960000", "zoom=" + zoom, "per_frame_1=rot = 0.01*sin(time);"]
        for (index, line) in warp.enumerated() { lines.append("warp_\(index + 1)=`" + line) }
        return lines.joined(separator: "\n") + "\n"
    }

    static let textured = text(warp: ["shader_body", "{", "    ret = tex2D(sampler_pre018_absent_texture, uv).xyz * 0.97;", "}"],
                               zoom: "1.011000")
    static let lost = text(zoom: "1.012000")
    static let broken = text(header: false, zoom: "1.013000")
    static let clean = text(zoom: "1.014000")

    static func record(_ name: String, _ text: String, number: Int) -> UserPreset {
        let bytes: [UInt8] = Array(text.utf8)
        return UserPreset(id: "user/00000000-0000-4000-8000-00000000001\(number)", name: name, author: "", originalFileName: name + ".milk",
                          sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes), byteCount: bytes.count,
                          importedAt: Date(timeIntervalSince1970: 1_763_078_400), state: .playable, provenOnScreen: true,
                          license: PresetLicenseMetadata(authorFromFileName: false, linesFound: []))
    }

    /// Before `UserPresetsCoordinator.load()`.
    static func seedFilesIfRequested() {
        guard requested else { return }
        let store = UserPresetStore(directory: UserPresetStore.defaultDirectory())
        let items: [(String, String)] = [("Textured", textured), ("Lost", lost), ("Broken", broken), ("Clean", clean)]
        for (number, item) in items.enumerated() {
            try? store.add(record(item.0, item.1, number: number), contents: Data(item.1.utf8))
        }
        let lostFile: URL = UserPresetStore.defaultDirectory().appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(ContentHash.sha256Hex(Array(lost.utf8)) + ".milk")
        try? FileManager.default.removeItem(at: lostFile)
    }

    /// After `PresetCoordinator.attach` (which drops favorites that no longer exist at launch).
    static func seedReferencesIfRequested(_ presets: PresetCoordinator) {
        guard requested else { return }
        presets.store.toggle(goneID)
        presets.favoritesVersion += 1
        _ = try? presets.tagStore.add("broken", to: goneID)
        _ = try? presets.overrides?.store.set(1.05, for: "zoom", preset: goneID)
        if let collection = presets.createCollection(named: collectionName) {
            presets.changeCollections { _ = try presets.collectionStore.add(goneID, to: collection.id) }
        }
        presets.recent?.replaceForUITests([goneID])
    }
}
#endif
