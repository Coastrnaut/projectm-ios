// UITestShowFixture.swift — DEBUG only: `-uitestShowSeed` replaces the show with five cues over five
// distinct scenes (fixed IDs) standing on cue 1, whose look is set before the visualizer starts
// (SHOW-001-T11; ShowCueUITests). Scenes: Circular 64 bars, Linear vertical, Circular 16 bars with
// glow, Linear horizontal, Text "Finale".
// SCN-012: `-uitestShowRepairSeed` instead seeds three cues for SceneRepairUITests: "Opening" (Circular,
// applied), "Broken" (a photo that is not stored, a Circular layer and a mapping to a parameter this
// version does not know) and "Future" (a scene file of format version 2).
// SHOW-002: `-uitestShowDwellSeed` (with `-uitestShowSeed`) gives cue 2 a 2 s dwell.
// XFADE: `-uitestShowTransitionSeed` seeds two Text cues, "Intro" (applied) and "Outro" with a 2 s linear
// crossfade (CueTransitionUITests: the transition shows on screen).
#if DEBUG
import Foundation
import ParameterGraph
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
        if ProcessInfo.processInfo.arguments.contains(repairArgument) { return seedRepairShow(coordinator) }
        if ProcessInfo.processInfo.arguments.contains(transitionArgument) { return seedTransitionShow(coordinator) }
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
        if ProcessInfo.processInfo.arguments.contains(dwellArgument), let dwell = try? ShowCueDwell(seconds: 2) {
            _ = try? list.setDwell(cueID(2), to: dwell)   // SHOW-002: cue 2 advances by itself after 2 s
        }
        list.go(to: cueID(1))
        coordinator.show.replaceForUITests(list)
        let first = ShowSceneSnapshot.document(looks[0], id: sceneID(1), name: labels[0])
        coordinator.applyShowScene(first, warnings: [], refresh: false)
        coordinator.show.markAppliedForUITests(sceneID(1))
    }

    /// SHOW-002 (with `-uitestShowSeed`): cue 2 gets a 2 s dwell (ShowAutoAdvanceUITests).
    static let dwellArgument = "-uitestShowDwellSeed"

    // MARK: XFADE

    static let transitionArgument = "-uitestShowTransitionSeed"

    private static func seedTransitionShow(_ coordinator: AppCoordinator) {
        guard let store = coordinator.show.store else { return }
        var intro = coordinator.showLook
        intro.photoID = nil
        intro.videoID = nil
        intro.glowEnabled = false
        intro.visual = .text
        intro.text = TextOverlaySpec(message: "Intro")
        var outro = intro
        outro.text = TextOverlaySpec(message: "Outro")
        let documents = [ShowSceneSnapshot.document(intro, id: sceneID(1), name: "Intro"),
                         ShowSceneSnapshot.document(outro, id: sceneID(2), name: "Outro")]
        var list = ShowCueList(id: UUID(uuidString: "5E0E0000-0000-4000-8000-000000000003")!, name: "UI Test Transition Show")
        for (index, document) in documents.enumerated() {
            try? store.saveScene(document)
            _ = try? list.append(sceneID: document.id, label: document.name, cueID: cueID(index + 1))
        }
        if let fade = try? ShowCueTransition(type: .crossfade, durationSeconds: 2, easing: .linear) {
            _ = try? list.setTransition(cueID(2), to: fade)
        }
        list.go(to: cueID(1))
        coordinator.show.replaceForUITests(list)
        coordinator.applyShowScene(documents[0], warnings: [], refresh: false)
        coordinator.show.markAppliedForUITests(sceneID(1))
    }

    // MARK: SCN-012

    static let repairArgument = "-uitestShowRepairSeed"
    static let repairLabels = ["Opening", "Broken", "Future"]
    /// A photo store ID no store holds.
    static let missingPhotoID = "0DDBA11E-0000-4000-8000-000000000001"

    private static func seedRepairShow(_ coordinator: AppCoordinator) {
        guard let store = coordinator.show.store else { return }
        var base = coordinator.showLook
        base.photoID = nil
        base.videoID = nil
        base.glowEnabled = false
        base.visual = .circularSpectrum
        base.bars = 64
        let opening = ShowSceneSnapshot.document(base, id: sceneID(1), name: repairLabels[0])
        var broken = ShowSceneSnapshot.document(base, id: sceneID(2), name: repairLabels[1])
        broken.layers.insert(SceneLayer(instance: 2, content: .photo(asset: ShowSceneSnapshot.photoKey)), at: 0)
        broken.assets[ShowSceneSnapshot.photoKey] = .photo(storeID: missingPhotoID)
        broken.bindings = [SceneBinding(sourceID: "audio.onset", target: "visual.future.thing",
                                        mapping: LinearMapping(outputStart: 0, outputEnd: 1))]
        try? store.saveScene(opening)
        try? store.saveScene(broken)
        // Format version 2: a newer app's scene (SCN-001 refuses it).
        let future = ShowSceneSnapshot.document(base, id: sceneID(3), name: repairLabels[2])
        let text = String(decoding: future.encoded(), as: UTF8.self).replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
        try? Data(text.utf8).write(to: store.sceneFile(sceneID(3)), options: .atomic)

        var list = ShowCueList(id: UUID(uuidString: "5E0E0000-0000-4000-8000-000000000002")!, name: "UI Test Repair Show")
        for n in 1...3 { _ = try? list.append(sceneID: sceneID(n), label: repairLabels[n - 1], cueID: cueID(n)) }
        list.go(to: cueID(1))
        coordinator.show.replaceForUITests(list)
        coordinator.applyShowScene(opening, warnings: [], refresh: false)
        coordinator.show.markAppliedForUITests(sceneID(1))
    }
}
#endif
