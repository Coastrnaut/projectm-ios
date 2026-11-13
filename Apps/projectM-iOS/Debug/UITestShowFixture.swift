// UITestShowFixture.swift — DEBUG only: `-uitestShowSeed` replaces the show with five cues over five
// distinct scenes (fixed IDs) standing on cue 1, whose look is set before the visualizer starts
// (SHOW-001-T11; ShowCueUITests). Scenes: Circular 64 bars, Linear vertical, Circular 16 bars with
// glow, Linear horizontal, Text "Finale".
#if DEBUG
import Foundation
import SceneFormat
import ShowControl
import TextLayer

@MainActor
enum UITestShowFixture {
    static let argument = "-uitestShowSeed"
    static let labels = ["Opening", "Build", "Drop", "Break", "Finale"]

    static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }
    static func cueID(_ n: Int) -> UUID { UUID(uuidString: "C0E00000-0000-4000-8000-00000000000\(n)")! }

    static func seedIfRequested(_ coordinator: AppCoordinator) {
        guard ProcessInfo.processInfo.arguments.contains(argument), let store = coordinator.show.store else { return }
        var looks: [ShowLook] = []
        var base = coordinator.showLook
        base.photoID = nil
        base.videoID = nil
        base.glowEnabled = false
        base.visual = .circularSpectrum
        base.bars = 64
        looks.append(base)
        var linear = base
        linear.visual = .linearSpectrum
        linear.orientation = .vertical
        looks.append(linear)
        var drop = base
        drop.bars = 16
        drop.glowEnabled = true
        looks.append(drop)
        var breakLook = linear
        breakLook.orientation = .horizontal
        looks.append(breakLook)
        var finale = base
        finale.visual = .text
        finale.text = TextOverlaySpec(message: "Finale")
        looks.append(finale)

        var list = ShowCueList(id: UUID(uuidString: "5E0E0000-0000-4000-8000-000000000001")!, name: "UI Test Show")
        for (index, look) in looks.enumerated() {
            let n = index + 1
            let document = ShowSceneSnapshot.document(look, id: sceneID(n), name: labels[index])
            try? store.saveScene(document)
            try? list.append(sceneID: sceneID(n), label: labels[index], cueID: cueID(n))
        }
        list.go(to: cueID(1))
        coordinator.show.replaceForUITests(list)
        let first = ShowSceneSnapshot.document(looks[0], id: sceneID(1), name: labels[0])
        coordinator.applyShowScene(first, warnings: [], refresh: false)
        coordinator.show.markAppliedForUITests(sceneID(1))
    }
}
#endif
