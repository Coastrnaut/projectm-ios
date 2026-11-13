// SceneHistoryTests.swift — SCN-010-T03: the bounded undo/redo history (SCN-010-S1 to S4; contract
// H1). States are SceneDocuments compared by canonical bytes (ADR-0028), so every check covers the
// ordered layer stack, instance IDs, parameters and assets at once.
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneHistoryTests: XCTestCase {
    typealias IDs = VisualParameterIDs
    typealias State = SceneHistoryState<SceneDocument>

    /// An app-shaped scene: the visual's fixed layer stack and the seven app-held values.
    private struct Look {
        var visual = "projectM"
        var bars = 64
        var orientation = "vertical"
        var spacing = 0.2
        var glowEnabled = false
        var glowIntensity = 0.5
        var message = "Hello"

        func document() -> SceneDocument {
            var layers: [SceneLayer] = []
            var assets: [String: SceneAsset] = [:]
            switch visual {
            case "circular":
                layers = [SceneLayer(instance: 1, content: .circularSpectrum)]
            case "linear":
                layers = [SceneLayer(instance: 1, content: .linearSpectrum)]
            case "text":
                layers = [SceneLayer(instance: 1, content: .circularSpectrum), SceneLayer(instance: 2, content: .text(asset: "text"))]
                let spec: SceneJSON = .object(["message": .string(message)])
                assets["text"] = SceneAsset(.text(spec: spec))
            case "photo":
                layers = [SceneLayer(instance: 2, content: .photo(asset: "photo")), SceneLayer(instance: 1, content: .circularSpectrum)]
                assets["photo"] = .photo(storeID: SceneFixtures.photoID)
            default:
                break
            }
            let parameters: [ParameterID: ParameterValue] = [
                IDs.circularSpectrumBarCount: .enumeration(String(bars)),
                IDs.linearSpectrumOrientation: .enumeration(orientation),
                IDs.linearSpectrumSpacing: .continuous(spacing),
                IDs.bloomEnabled: .boolean(glowEnabled),
                IDs.bloomIntensity: .continuous(glowIntensity),
            ]
            return SceneDocument(id: SceneFixtures.sceneID, name: "Current Scene", layers: layers, parameters: parameters, assets: assets)
        }

        var state: State { State(document()) }
    }

    private func layerKinds(_ state: State) throws -> [String] {
        try SceneDocument.decode(state.bytes).document.layers.map { (l: SceneLayer) -> String in l.kind }
    }

    // MARK: S1 — the row's acceptance

    func testUndoAllRestoresEveryRecordedStateInOrderAndRedoAllReturns() throws {
        var look = Look()
        var history = SceneHistory(current: look.state)
        var recorded: [[UInt8]] = [look.state.bytes]
        let edits: [(String, (inout Look) -> Void)] = [
            ("Visual Circular Spectrum", { (l: inout Look) -> Void in l.visual = "circular" }),
            ("Bars 16", { (l: inout Look) -> Void in l.bars = 16 }),
            ("Glow On", { (l: inout Look) -> Void in l.glowEnabled = true }),
            ("Glow Intensity 75%", { (l: inout Look) -> Void in l.glowIntensity = 0.75 }),
            ("Visual Text", { (l: inout Look) -> Void in l.visual = "text" }),
            ("Text Message", { (l: inout Look) -> Void in l.message = "Night Drive" }),
            ("Visual Linear Spectrum", { (l: inout Look) -> Void in l.visual = "linear" }),
            ("Orientation Horizontal", { (l: inout Look) -> Void in l.orientation = "horizontal" }),
        ]
        for (label, edit) in edits {
            edit(&look)
            XCTAssertEqual(history.record(look.state, label: label), .recorded, label)
            recorded.append(look.state.bytes)
        }
        XCTAssertEqual(history.undoLabel, "Orientation Horizontal")

        // Undo all: each state equals the one recorded before the matching edit, newest first.
        for index in stride(from: edits.count - 1, through: 0, by: -1) {
            XCTAssertEqual(history.undoLabel, edits[index].0)
            let restored = try XCTUnwrap(history.undo())
            XCTAssertEqual(restored.bytes, recorded[index], "undo of \(edits[index].0)")
            XCTAssertEqual(restored.value.encoded(), recorded[index])
        }
        XCTAssertNil(history.undo())
        XCTAssertFalse(history.canUndo)
        XCTAssertEqual(try layerKinds(history.current), [])

        // Redo all: each state equals the one recorded after the matching edit, in order.
        for index in 0..<edits.count {
            XCTAssertEqual(history.redoLabel, edits[index].0)
            let restored = try XCTUnwrap(history.redo())
            XCTAssertEqual(restored.bytes, recorded[index + 1], "redo of \(edits[index].0)")
        }
        XCTAssertNil(history.redo())
        XCTAssertEqual(history.current.bytes, look.state.bytes)
    }

    func testUndoRestoresTheOrderedLayerTreeAndParameters() throws {
        var look = Look(visual: "photo")
        var history = SceneHistory(current: look.state)
        look.visual = "text"
        look.bars = 128
        history.record(look.state, label: "Scene")
        XCTAssertEqual(try layerKinds(history.current), ["spectrum.circular", "text"])
        let back = try XCTUnwrap(history.undo())
        let document = try SceneDocument.decode(back.bytes).document
        XCTAssertEqual(document.layers.map { (l: SceneLayer) -> UInt64 in l.instance }, [2, 1], "order and instance IDs")
        XCTAssertEqual(document.layers.map(\.kind), ["photo", "spectrum.circular"])
        XCTAssertEqual(document.parameters[IDs.circularSpectrumBarCount], .enumeration("64"))
        XCTAssertEqual(document, Look(visual: "photo").document())
    }

    // MARK: S2 — redo cleared, no-ops, coalescing

    func testANewEditAfterAnUndoClearsRedo() {
        var look = Look()
        var history = SceneHistory(current: look.state)
        look.bars = 16
        history.record(look.state, label: "Bars 16")
        look.bars = 32
        history.record(look.state, label: "Bars 32")
        _ = history.undo()
        XCTAssertTrue(history.canRedo)
        look.bars = 128
        XCTAssertEqual(history.record(look.state, label: "Bars 128"), .recorded)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.undoSteps.map(\.label), ["Bars 16", "Bars 128"])
    }

    func testAnEditWithEqualBytesIsNotRecorded() {
        let look = Look(visual: "circular", bars: 32)
        var history = SceneHistory(current: look.state)
        XCTAssertEqual(history.record(Look(visual: "circular", bars: 32).state, label: "Bars 32"), .unchanged)
        // The message is not in a circular scene: no change to its bytes.
        XCTAssertEqual(history.record(Look(visual: "circular", bars: 32, message: "Other").state, label: "Text Message"), .unchanged)
        XCTAssertFalse(history.canUndo)
        XCTAssertEqual(history.current.value.encoded(), look.state.bytes)
    }

    func testASliderDragCoalescesIntoOneStepUntilABoundary() throws {
        var look = Look(glowEnabled: true)
        var history = SceneHistory(current: look.state)
        let start = look.state.bytes
        for value in [0.55, 0.6, 0.7, 0.8] {
            look.glowIntensity = value
            history.record(look.state, label: "Glow Intensity \(Int(value * 100))%", coalescingKey: "glow.intensity")
        }
        XCTAssertEqual(history.undoSteps.count, 1)
        XCTAssertEqual(history.undoLabel, "Glow Intensity 80%")
        history.endCoalescing()
        look.glowIntensity = 0.9
        XCTAssertEqual(history.record(look.state, label: "Glow Intensity 90%", coalescingKey: "glow.intensity"), .recorded)
        XCTAssertEqual(history.undoSteps.count, 2, "a drag after the boundary is its own step")
        // Another key is a boundary too.
        look.bars = 16
        history.record(look.state, label: "Bars 16")
        look.glowIntensity = 0.95
        XCTAssertEqual(history.record(look.state, label: "Glow Intensity 95%", coalescingKey: "glow.intensity"), .recorded)
        XCTAssertEqual(history.undoSteps.count, 4)
        _ = history.undo(); _ = history.undo(); _ = history.undo()
        XCTAssertEqual(try XCTUnwrap(history.undo()).bytes, start, "one undo per drag")
    }

    func testADragBackToItsStartLeavesNoStep() {
        var look = Look(glowEnabled: true)
        var history = SceneHistory(current: look.state)
        look.glowIntensity = 0.7
        history.record(look.state, label: "Glow Intensity 70%", coalescingKey: "glow.intensity")
        look.glowIntensity = 0.5
        XCTAssertEqual(history.record(look.state, label: "Glow Intensity 50%", coalescingKey: "glow.intensity"), .coalesced)
        XCTAssertFalse(history.canUndo)
        look.glowIntensity = 0.6
        XCTAssertEqual(history.record(look.state, label: "Glow Intensity 60%", coalescingKey: "glow.intensity"), .recorded)
        XCTAssertEqual(history.undoSteps.count, 1)
    }

    func testUndoAndRedoCloseCoalescing() {
        var look = Look(glowEnabled: true)
        var history = SceneHistory(current: look.state)
        look.glowIntensity = 0.7
        history.record(look.state, label: "a", coalescingKey: "k")
        _ = history.undo()
        _ = history.redo()
        look.glowIntensity = 0.8
        XCTAssertEqual(history.record(look.state, label: "b", coalescingKey: "k"), .recorded)
        XCTAssertEqual(history.undoSteps.count, 2)
    }

    func testResetEmptiesBothLists() {
        var look = Look()
        var history = SceneHistory(current: look.state)
        look.bars = 16
        history.record(look.state, label: "Bars 16")
        look.bars = 32
        history.record(look.state, label: "Bars 32")
        _ = history.undo()
        let cue = Look(visual: "linear")
        history.reset(to: cue.state)
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.current.bytes, cue.state.bytes)
    }

    // MARK: S3 — bounds

    func testTwoHundredEditsKeepFiftyStepsOldestForgotten() throws {
        var history = SceneHistory(current: Look(glowIntensity: 0).state)
        for index in 1...200 {
            history.record(Look(glowIntensity: Double(index) / 1000).state, label: "Edit \(index)")
        }
        XCTAssertEqual(history.undoSteps.count, 50)
        XCTAssertEqual(history.undoSteps.first?.label, "Edit 151")
        XCTAssertLessThanOrEqual(history.storedBytes, SceneHistoryLimits.standard.maximumBytes)
        var last: State?
        while let state = history.undo() { last = state }
        XCTAssertEqual(try XCTUnwrap(last).bytes, Look(glowIntensity: 0.15).state.bytes, "the oldest kept before-state")
    }

    func testTheByteBudgetEvictsOldestUndoThenFarthestRedo() throws {
        let size = Look().state.bytes.count
        // Room for the current state and three steps.
        var history = SceneHistory(current: Look(glowIntensity: 0).state,
                                   limits: SceneHistoryLimits(maximumSteps: 50, maximumBytes: size * 4 + size / 2))
        for index in 1...6 {
            history.record(Look(glowIntensity: Double(index) / 10).state, label: "Edit \(index)")
            XCTAssertLessThanOrEqual(history.storedBytes, history.limits.maximumBytes)
        }
        XCTAssertEqual(history.undoSteps.map(\.label), ["Edit 4", "Edit 5", "Edit 6"])
        // Undo moves steps to redo; the total is unchanged and stays within the budget.
        _ = history.undo(); _ = history.undo()
        XCTAssertEqual(history.redoSteps.map(\.label), ["Edit 6", "Edit 5"])
        XCTAssertLessThanOrEqual(history.storedBytes, history.limits.maximumBytes)

        // A current state larger than the budget leaves only itself.
        var big = Look(visual: "text")
        big.message = String(repeating: "x", count: size * 8)
        history.record(big.state, label: "Text Message")
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.current.bytes, big.state.bytes)
    }

    // MARK: S4 — fixed-seed property test against a reference model

    func testRandomEditsUndosAndRedosMatchAReferenceModel() {
        var rng = SplitMix64(state: 0x5C1_0010)
        let limits = SceneHistoryLimits(maximumSteps: 12, maximumBytes: 1 << 30)
        var look = Look()
        var history = SceneHistory(current: look.state, limits: limits)
        // Reference: plain arrays of byte states, no coalescing (keys are never repeated here).
        var past: [[UInt8]] = []
        var present = look.state.bytes
        var future: [[UInt8]] = []
        for step in 0..<600 {
            let roll = rng.next() % 10
            if roll < 5 {
                switch rng.next() % 4 {
                case 0: look.bars = [16, 32, 64, 128][Int(rng.next() % 4)]
                case 1: look.visual = ["projectM", "circular", "linear", "text", "photo"][Int(rng.next() % 5)]
                case 2: look.glowIntensity = Double(rng.next() % 5) / 4
                default: look.orientation = rng.next() % 2 == 0 ? "vertical" : "horizontal"
                }
                let state = look.state
                let result = history.record(state, label: "Edit \(step)")
                if state.bytes == present {
                    XCTAssertEqual(result, .unchanged)
                } else {
                    XCTAssertEqual(result, .recorded)
                    past.append(present)
                    present = state.bytes
                    future.removeAll()
                    if past.count > limits.maximumSteps { past.removeFirst() }
                }
            } else if roll < 8 {
                let restored = history.undo()
                if let previous = past.popLast() {
                    future.append(present)
                    present = previous
                    XCTAssertEqual(restored?.bytes, previous)
                } else {
                    XCTAssertNil(restored)
                }
            } else {
                let restored = history.redo()
                if let next = future.popLast() {
                    past.append(present)
                    present = next
                    if past.count > limits.maximumSteps { past.removeFirst() }
                    XCTAssertEqual(restored?.bytes, next)
                } else {
                    XCTAssertNil(restored)
                }
            }
            look = Self.look(from: history.current.value)
            XCTAssertEqual(history.current.bytes, present, "step \(step)")
            XCTAssertEqual(history.undoSteps.map(\.state.bytes), past, "step \(step)")
            XCTAssertEqual(history.redoSteps.map(\.state.bytes).count, future.count, "step \(step)")
        }
    }

    /// The look a document came from (the property test edits from the restored state).
    private static func look(from document: SceneDocument) -> Look {
        var look = Look()
        let kinds = document.layers.map(\.kind)
        switch kinds {
        case ["spectrum.circular"]: look.visual = "circular"
        case ["spectrum.linear"]: look.visual = "linear"
        case ["spectrum.circular", "text"]: look.visual = "text"
        case ["photo", "spectrum.circular"]: look.visual = "photo"
        default: look.visual = "projectM"
        }
        if case let .enumeration(bars)? = document.parameters[IDs.circularSpectrumBarCount] { look.bars = Int(bars) ?? 64 }
        if case let .enumeration(o)? = document.parameters[IDs.linearSpectrumOrientation] { look.orientation = o }
        if case let .continuous(v)? = document.parameters[IDs.bloomIntensity] { look.glowIntensity = v }
        return look
    }
}
