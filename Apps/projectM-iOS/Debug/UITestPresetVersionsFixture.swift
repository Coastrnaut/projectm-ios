// UITestPresetVersionsFixture.swift — DEBUG only: `-uitestPresetVersions` with `-uitestResetNotice` (PRE-017-T09;
// UserPresetVersionsUITests). Seeds one playable user preset "Versioned" whose text was edited once, so it has one
// earlier version. Written in the UI-test reset, before anything opens the user preset store (as the PRE-018
// fixture). The preset text is written for this repository.
#if DEBUG
import Foundation
import PresetLibrary

enum UITestPresetVersionsFixture {
    static let argument = "-uitestPresetVersions"
    static let presetName = "Versioned"

    static func text(zoom: String) -> String {
        let lines: [String] = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.960000", "zoom=" + zoom,
                               "per_frame_1=rot = 0.01*sin(time);"]
        return lines.joined(separator: "\n") + "\n"
    }

    static func record(_ text: String) -> UserPreset {
        let bytes: [UInt8] = Array(text.utf8)
        return UserPreset(id: "user/00000000-0000-4000-8000-000000000170", name: presetName, author: "", originalFileName: "Versioned.milk",
                          sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes), byteCount: bytes.count,
                          importedAt: Date(timeIntervalSince1970: 1_763_078_400), state: .playable, provenOnScreen: true,
                          license: PresetLicenseMetadata(authorFromFileName: false, linesFound: []))
    }

    static func seedIfRequested() {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        guard arguments.contains(argument), arguments.contains("-uitestResetNotice") else { return }
        let store = UserPresetStore(directory: UserPresetStore.defaultDirectory())
        let first: String = text(zoom: "1.017000")
        let second: String = text(zoom: "1.027000")
        let original: UserPreset = record(first)
        try? store.add(original, contents: Data(first.utf8))
        var edited: UserPreset = record(second)
        edited.modifiedAt = Date(timeIntervalSince1970: 1_763_082_000)
        try? store.replaceContents(original.id, with: edited, contents: Data(second.utf8), replacedAt: Date(timeIntervalSince1970: 1_763_082_000))
    }
}
#endif
