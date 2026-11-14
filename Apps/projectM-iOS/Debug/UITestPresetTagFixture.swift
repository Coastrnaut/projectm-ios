// UITestPresetTagFixture.swift — DEBUG only (PRE-003): `-uitestSeedPresetTags "<tag>:<i>,<j>|<tag>:<k>"`
// tags the Included presets at those positions of the Included list (as the browser lists it), saved
// through the real tag store. It runs only on a fresh launch (`-uitestResetNotice`, which removes the
// PresetCollections folder and so the tags), so a relaunch shows what was saved. PresetTagsUITests
// uses it where tagging through the sheet is not what a test checks (owner rule 7: a UI test under 30 s).
#if DEBUG
import Foundation
import PresetLibrary

@MainActor
enum UITestPresetTagFixture {
    static func seedIfRequested(_ presets: PresetCoordinator, defaults: UserDefaults = .standard) {
        guard ProcessInfo.processInfo.arguments.contains("-uitestResetNotice"),
              let spec = defaults.string(forKey: "uitestSeedPresetTags"), let library = presets.library else { return }
        let included: [IndexedPreset] = library.members(of: .included, unlocked: true, favorites: [], excluded: [])
        for entry in spec.split(separator: "|") {
            let parts = entry.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard let tag = parts.first, parts.count > 1 else { continue }
            for position in parts[1].split(separator: ",").compactMap({ (p: Substring) -> Int? in Int(p) })
            where included.indices.contains(position) {
                presets.addTag(String(tag), to: included[position])
            }
        }
    }
}
#endif
