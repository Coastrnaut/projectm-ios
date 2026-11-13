// SceneHistoryCoordinatorTests.swift — SCN-010-T06: the app's scene history over a fake world
// (SCN-010-S1, S2; contract H2). `start(observing: false)`: the tests call `capture()` where the app's
// observation callback would. States are compared by the canonical bytes SCN-002's capture produces,
// so layer order (the visual's fixed stack) and the seven parameters are checked together.
import Foundation
import SceneFormat
import TextLayer
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneHistoryCoordinatorTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures

    /// The app's inputs; `apply` writes into it as AppCoordinator would.
    private final class World {
        var inputs = SceneAutosaveFixtures.inputs(visual: .projectM)
        var applied: [SceneInputs] = []
    }

    private func make(_ world: World) -> SceneHistoryCoordinator {
        let history = SceneHistoryCoordinator()
        history.inputs = { () -> SceneInputs in world.inputs }
        history.carry = { () -> SceneAutosaveCarry in F.carry }
        history.apply = { (inputs: SceneInputs) -> Void in
            world.applied.append(inputs)
            var next = inputs
            next.photoID = world.inputs.photoID   // the stored media is never applied
            next.videoID = world.inputs.videoID
            world.inputs = next
        }
        history.start(observing: false)
        return history
    }

    private func bytes(_ inputs: SceneInputs) -> [UInt8] {
        SceneAutosaveCapture.document(inputs, carry: F.carry, liveBindings: nil).document.encoded()
    }

    private func layerKinds(_ inputs: SceneInputs) -> [String] {
        SceneAutosaveCapture.document(inputs, carry: F.carry, liveBindings: nil).document.layers.map(\.kind)
    }

    /// S1: visual, bars, glow intensity, text, orientation → undo all → redo all.
    func testScriptedEditsUndoAndRedoInOrder() throws {
        let world = World()
        let history = make(world)
        var recorded: [[UInt8]] = [bytes(world.inputs)]
        var labels: [String] = []
        let edits: [(inout SceneInputs) -> Void] = [
            { (i: inout SceneInputs) -> Void in i.visual = .circularSpectrum },
            { (i: inout SceneInputs) -> Void in i.bars = 16 },
            { (i: inout SceneInputs) -> Void in i.glowEnabled = true },
            { (i: inout SceneInputs) -> Void in i.glowIntensity = 0.75 },
            { (i: inout SceneInputs) -> Void in i.visual = .text },
            { (i: inout SceneInputs) -> Void in _ = i.text.setMessage("Night Drive") },
            { (i: inout SceneInputs) -> Void in i.visual = .linearSpectrum },
            { (i: inout SceneInputs) -> Void in i.orientation = .horizontal },
        ]
        for edit in edits {
            edit(&world.inputs)
            history.capture()
            history.endCoalescing()
            recorded.append(bytes(world.inputs))
            labels.append(try XCTUnwrap(history.undoLabel))
        }
        XCTAssertEqual(labels, ["Visual Circular Spectrum", "Bars 16", "Glow On", "Glow Intensity 75%", "Visual Text",
                                "Text Message", "Visual Linear Spectrum", "Orientation \(LinearSpectrumOrientation.horizontal.title)"])
        XCTAssertEqual(history.undoAccessibilityLabel, "Undo Orientation \(LinearSpectrumOrientation.horizontal.title)")
        XCTAssertEqual(layerKinds(world.inputs), ["spectrum.linear"])

        for index in stride(from: edits.count - 1, through: 0, by: -1) {
            history.undo()
            history.capture()   // the observed apply: equal bytes, nothing recorded
            XCTAssertEqual(bytes(world.inputs), recorded[index], "undo \(labels[index])")
        }
        XCTAssertFalse(history.canUndo)
        XCTAssertEqual(world.inputs.visual, .projectM)
        XCTAssertEqual(history.redoAccessibilityLabel, "Redo Visual Circular Spectrum")

        for index in 0..<edits.count {
            history.redo()
            history.capture()
            XCTAssertEqual(bytes(world.inputs), recorded[index + 1], "redo \(labels[index])")
        }
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(world.applied.count, edits.count * 2)
        XCTAssertEqual(layerKinds(world.inputs), ["spectrum.linear"])
    }

    /// S2: a new edit clears redo; a no-op records nothing; a drag is one step.
    func testRedoClearedNoOpsAndDragCoalescing() {
        let world = World()
        world.inputs = F.inputs(visual: .circularSpectrum)
        world.inputs.glowEnabled = true
        let history = make(world)
        let start = bytes(world.inputs)
        for value in [0.55, 0.6, 0.65, 0.7] {
            world.inputs.glowIntensity = value
            history.capture()
        }
        XCTAssertEqual(history.history?.undoSteps.count, 1)
        XCTAssertEqual(history.undoLabel, "Glow Intensity 70%")
        history.endCoalescing()   // the drag ended
        world.inputs.glowIntensity = 0.8
        history.capture()
        XCTAssertEqual(history.history?.undoSteps.count, 2)

        history.capture()   // nothing changed
        XCTAssertEqual(history.history?.undoSteps.count, 2)
        var hidden = world.inputs.text   // the message is not in a circular scene: no change to its bytes
        _ = hidden.setMessage("Not shown")
        world.inputs.text = hidden
        history.capture()
        XCTAssertEqual(history.history?.undoSteps.count, 2)

        history.undo()
        XCTAssertTrue(history.canRedo)
        world.inputs.bars = 128
        history.capture()
        XCTAssertFalse(history.canRedo, "a new edit clears redo")
        history.undo()
        history.undo()
        XCTAssertEqual(bytes(world.inputs), start)
    }

    /// R9: a photo replacement and a restart (cue, Reopen) empty both lists.
    func testNonEditsRestartTheHistory() {
        let world = World()
        world.inputs = F.inputs(visual: .photo)
        let history = make(world)
        world.inputs.bars = 16
        history.capture()
        XCTAssertTrue(history.canUndo)
        world.inputs.photoID = UUID()
        history.capture()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.history?.current.bytes, bytes(world.inputs))

        world.inputs.bars = 32
        history.capture()
        history.undo()
        XCTAssertTrue(history.canRedo)
        world.inputs.visual = .linearSpectrum   // a cue applied it
        history.restart()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.undoAccessibilityLabel, "Undo")
    }

    /// Labels and coalescing keys of single and combined changes (research SCN-010-D7).
    func testLabelsAndKeys() {
        let base = F.inputs(visual: .linearSpectrum)
        func describe(_ change: (inout SceneInputs) -> Void) -> String {
            var next = base
            change(&next)
            let edit = SceneHistoryEdit.describe(from: base, to: next)
            return "\(edit.label)|\(edit.key ?? "-")"
        }
        XCTAssertEqual(describe { (i: inout SceneInputs) -> Void in i.bars = 16 }, "Bars 16|-")
        XCTAssertEqual(describe { (i: inout SceneInputs) -> Void in i.spacing = 0.5 }, "Spacing Wide|-")
        XCTAssertEqual(describe { (i: inout SceneInputs) -> Void in i.glowRadius = 0.035 }, "Glow Radius 3.5%|glow.radius")
        XCTAssertEqual(describe { (i: inout SceneInputs) -> Void in i.glowThreshold = 0.5 }, "Glow Threshold 50%|glow.threshold")
        XCTAssertEqual(describe { (i: inout SceneInputs) -> Void in i.text.size = 0.1 }, "Text Size 10%|text.size")
        XCTAssertEqual(describe { (i: inout SceneInputs) -> Void in i.text.outlineWidth = 0.1 }, "Text Outline 10%|text.outline")
        XCTAssertEqual(describe { (i: inout SceneInputs) -> Void in i.text.showsBox.toggle() }, "Text|-")
        XCTAssertEqual(describe { (i: inout SceneInputs) -> Void in _ = i.text.setMessage("Hi") }, "Text Message|text.message")
        XCTAssertEqual(describe { (i: inout SceneInputs) -> Void in i.bars = 16; i.glowEnabled = true }, "Scene|-")
    }
}
