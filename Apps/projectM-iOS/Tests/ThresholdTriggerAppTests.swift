// ThresholdTriggerAppTests.swift — MOD-006-T09 (US3; MOD-006-R11, S5): in the app, a kick-driven threshold trigger on
// Next cue performs the cue step exactly once per kick, through `NativeSpectrumHost`'s frame evaluation and MIDI-006's
// `MIDINoteActionPerformer` (actions recorded). Deterministic: kick values, seeded noise and frame times are passed
// in. Needs a Metal device (the simulator renders with the host GPU); skips without one. Also: the scene carry writes
// the stored `triggers` list back unchanged.
import Foundation
import Metal
import ParameterGraph
import SceneFormat
import VisualEffects
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class ThresholdTriggerAppTests: XCTestCase {
    private static let frame: UInt64 = 16_666_667   // 60 fps

    @MainActor private final class Log {
        var actions: [String] = []
        var blackedOut = false
    }

    private func performer(_ log: Log) -> MIDINoteActionPerformer {
        MIDINoteActionPerformer(actions: MIDINoteActionPerformer.Actions(
            nextCue: { () -> Void in log.actions.append("next") },
            previousCue: { () -> Void in log.actions.append("previous") },
            isBlackoutRequested: { () -> Bool in log.blackedOut },
            setBlackout: { (on: Bool) -> Void in
                log.blackedOut = on
                log.actions.append(on ? "blackout" : "restore")
            }))
    }

    func testKickTriggerPerformsNextCueOncePerKick() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.5))
        try host.setTriggers([ThresholdTriggerBinding(source: .kick, action: .cueNext,
                                                      settings: ThresholdTriggerSettings(high: 0.6, low: 0.3))])
        XCTAssertEqual(host.triggers.count, 1)
        let log = Log()
        let actions = performer(log)
        host.onTrigger = { (action: ThresholdTriggerAction) -> Void in AppCoordinator.perform(action, with: actions) }

        // Four kicks 500 ms apart: the ANL-007 envelope jumps to 1 and decays (τ 120 ms), with ±0.05 seeded noise.
        var state: UInt64 = 0x6006
        let bands: [Float] = [0.1, 0.1, 0.1]
        var time: UInt64 = 1_000_000_000
        for index in 0..<(4 * 30 + 30) {
            let sinceKick: Double = Double(index % 30) / 60
            let kicking: Bool = index < 4 * 30
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise: Double = (Double(state >> 11) / Double(1 << 53) - 0.5) * 0.1
            let envelope: Double = kicking ? exp(-sinceKick / 0.12) : 0
            let kick = Float(min(max(envelope + noise, 0), 1))
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                host.applyModulation(bands: buffer, kick: kick, timeNanoseconds: time)
            }
            time += Self.frame
        }
        XCTAssertEqual(log.actions, ["next", "next", "next", "next"], "Next cue once per kick")
        XCTAssertEqual(host.glow.intensity, 0.5, "triggers leave the glow alone")

        // Black out (toggle) goes through the same performer path.
        AppCoordinator.perform(.blackout, with: actions)
        XCTAssertEqual(log.actions.last, "blackout")
    }

    func testSceneCarryWritesTriggersBackUnchanged() throws {
        let entry = SceneTriggerEntry(fields: ["source": .string("audio.kick"), "action": .string("cue.next"),
                                               "high": .double(0.6), "low": .double(0.3), "note": .string("kept")])
        var carry = SceneAutosaveFixtures.carry
        carry.triggers = [entry]
        let document = SceneAutosaveCapture.document(SceneAutosaveFixtures.inputs(), carry: carry, liveBindings: nil).document
        XCTAssertEqual(document.triggers, [entry])
        XCTAssertEqual(document.triggerBindings.map(\.action), [.cueNext])
        let plain = SceneAutosaveCapture.document(SceneAutosaveFixtures.inputs(), carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertNil(plain.triggers, "a scene without triggers stays without the field")
    }
}
