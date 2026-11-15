// ShowKeyframeTrackTests.swift — SHOW-008 keyframe tracks (contract K1 to K4, K6; SHOW-008-S1, S2, S4).
import Foundation
import ParameterGraph
import XCTest
@testable import ShowControl

final class ShowKeyframeTrackTests: XCTestCase {
    private let glow: ParameterID = "effect.bloom.intensity"
    private let colorID: ParameterID = "visual.palette.color"

    private func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> ShowKeyframeColor {
        ShowKeyframeColor(red: r, green: g, blue: b, alpha: a)!
    }

    /// Awkward values on purpose (0.1 + 0.2 style decimals, odd times) so float drift would show.
    private func numericTrack() throws -> ShowKeyframeTrack {
        try ShowKeyframeTrack(id: UUID(), parameter: glow, keyframes: [
            ShowKeyframe(time: 0, value: .number(0.2), interpolation: .linear),
            ShowKeyframe(time: 7_333, value: .number(0.30000000000000004), interpolation: .ease),
            ShowKeyframe(time: 30_000, value: .number(1.5), interpolation: .stepped),
            ShowKeyframe(time: 60_001, value: .number(0.1), interpolation: .linear),
            ShowKeyframe(time: 921_600_000, value: .number(1.9999999), interpolation: .linear),
        ])
    }

    private func colorTrack() throws -> ShowKeyframeTrack {
        try ShowKeyframeTrack(id: UUID(), parameter: colorID, keyframes: [
            ShowKeyframe(time: 0, value: .color(color(0.05, 0.1, 0.6)), interpolation: .linear),
            ShowKeyframe(time: 30_000, value: .color(color(0.9, 0.12345678901234, 0.7, 0.5)), interpolation: .ease),
            ShowKeyframe(time: 45_500, value: .color(color(0.0, 1.0, 0.333, 0.25)), interpolation: .stepped),
        ])
    }

    // K1, S1: the roadmap acceptance — at every keyframe time the value is the stored sample, bit for bit.
    func testEveryKeyframeTimeReturnsTheStoredSampleExactly() throws {
        for track in [try numericTrack(), try colorTrack()] {
            for keyframe in track.keyframes {
                let value = try XCTUnwrap(track.value(at: .milliseconds(keyframe.time)))
                switch (value, keyframe.value) {
                case let (.number(a), .number(b)):
                    XCTAssertEqual(a.bitPattern, b.bitPattern, "number at \(keyframe.time) ms")
                case let (.color(a), .color(b)):
                    XCTAssertEqual(a.components.map(\.bitPattern), b.components.map(\.bitPattern), "colour at \(keyframe.time) ms")
                default:
                    XCTFail("kind changed at \(keyframe.time) ms")
                }
            }
        }
    }

    // K2, S2: interpolation between keys, before and after.
    func testBetweenKeysFollowsTheInterpolation() throws {
        let track = try ShowKeyframeTrack(id: UUID(), parameter: glow, keyframes: [
            ShowKeyframe(time: 10_000, value: .number(0), interpolation: .linear),
            ShowKeyframe(time: 20_000, value: .number(1), interpolation: .ease),
            ShowKeyframe(time: 30_000, value: .number(2), interpolation: .stepped),
            ShowKeyframe(time: 40_000, value: .number(3), interpolation: .linear),
        ])
        XCTAssertEqual(track.value(at: .seconds(0)), .number(0))            // before the first: first value
        XCTAssertEqual(track.value(at: .seconds(15)), .number(0.5))         // linear midpoint
        XCTAssertEqual(track.value(at: .seconds(25)), .number(1.5))         // ease midpoint is halfway
        let easeQuarter = try XCTUnwrap(track.value(at: .milliseconds(22_500))?.number)
        XCTAssertEqual(easeQuarter, 1 + 0.15625, accuracy: 1e-12)            // smoothstep(0.25) below linear 0.25
        XCTAssertEqual(track.value(at: .milliseconds(39_999)), .number(2))  // hold until the next key
        XCTAssertEqual(track.value(at: .seconds(500)), .number(3))          // after the last: last value
    }

    func testColoursMixInLinearLight() throws {
        let black = color(0, 0, 0, 0)
        let white = color(1, 1, 1, 1)
        let track = try ShowKeyframeTrack(id: UUID(), parameter: colorID, keyframes: [
            ShowKeyframe(time: 0, value: .color(black), interpolation: .linear),
            ShowKeyframe(time: 1_000, value: .color(white), interpolation: .linear),
        ])
        let mid = try XCTUnwrap(track.value(at: .milliseconds(500))?.color)
        let expected: Double = ShowKeyframeColor.encode(0.5)   // linear 0.5 → sRGB ≈ 0.735, not 0.5
        XCTAssertEqual(mid.red, expected, accuracy: 1e-12)
        XCTAssertEqual(mid.green, expected, accuracy: 1e-12)
        XCTAssertEqual(mid.alpha, 0.5, accuracy: 1e-12)
        XCTAssertGreaterThan(mid.red, 0.7)
    }

    // K3: pure — the same time gives the same value, in any order of evaluation.
    func testEvaluationIsPure() throws {
        let track = try numericTrack()
        let times: [Duration] = [.milliseconds(12_345), .seconds(3), .milliseconds(59_000), .seconds(3)]
        let forward = times.map { (t: Duration) -> ShowKeyframeValue? in track.value(at: t) }
        let backward = times.reversed().map { (t: Duration) -> ShowKeyframeValue? in track.value(at: t) }
        XCTAssertEqual(forward, Array(backward.reversed()))
        XCTAssertEqual(forward[1], forward[3])
    }

    // K6: edits.
    func testEditsKeepOneKeyPerTimeOneKindAndTheLimits() throws {
        var track = ShowKeyframeTrack(parameter: glow)
        XCTAssertNil(track.value(at: .zero))
        try track.setKeyframe(ShowKeyframe(time: 5_000, value: .number(0.4)))
        XCTAssertEqual(track.value(at: .seconds(99)), .number(0.4))   // one key holds everywhere
        try track.setKeyframe(ShowKeyframe(time: 5_000, value: .number(0.9), interpolation: .stepped))
        XCTAssertEqual(track.keyframes.count, 1)
        XCTAssertEqual(track.keyframes[0].value, .number(0.9))
        try track.setKeyframe(ShowKeyframe(time: 1_000, value: .number(0.1)))
        XCTAssertEqual(track.keyframes.map(\.time), [1_000, 5_000])
        XCTAssertThrowsError(try track.setKeyframe(ShowKeyframe(time: 2_000, value: .color(.white))))
        XCTAssertThrowsError(try track.setKeyframe(ShowKeyframe(time: -1, value: .number(0))))
        XCTAssertThrowsError(try track.setKeyframe(ShowKeyframe(time: 2_000, value: .number(.nan))))
        try track.setInterpolation(.ease, at: 1_000)
        try track.setValue(.number(0.2), at: 1_000)
        XCTAssertEqual(track.keyframes[0], ShowKeyframe(time: 1_000, value: .number(0.2), interpolation: .ease))
        try track.removeKeyframe(at: 5_000)
        XCTAssertEqual(track.keyframes.count, 1)

        var tracks = ShowKeyframeTracks()
        try tracks.addTrack(parameter: glow)
        XCTAssertThrowsError(try tracks.addTrack(parameter: glow))
        XCTAssertThrowsError(try tracks.addTrack(parameter: "bad"))
        for i in 1..<ShowKeyframeTracks.maximumTracks { try tracks.addTrack(parameter: ParameterID("test.p\(i)")) }
        XCTAssertThrowsError(try tracks.addTrack(parameter: "test.extra"))
        XCTAssertEqual(ShowKeyframeColor(red: 1.01, green: 0, blue: 0), nil)
    }

    // K4, S4: round trip (byte-identical) and lenient read.
    func testTracksRoundTripAndOldShowsKeepTheirBytes() throws {
        var list = ShowCueList(id: UUID(), name: "Show")
        let plain: Data = list.encoded()
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("tracks"))
        list.tracks = try ShowKeyframeTracks(tracks: [try numericTrack(), try colorTrack()])
        let bytes: Data = list.encoded()
        let decoded = try ShowCueList.decode(bytes)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.list.tracks, list.tracks)
        XCTAssertEqual(decoded.list.encoded(), bytes)
        for (a, b) in zip(decoded.list.tracks.tracks, list.tracks.tracks) {
            XCTAssertEqual(a.keyframes.map { (k: ShowKeyframe) -> [UInt64] in Self.bits(k.value) },
                           b.keyframes.map { (k: ShowKeyframe) -> [UInt64] in Self.bits(k.value) })
        }
    }

    func testDamagedTracksAndKeyframesAreDroppedWithCountedWarnings() throws {
        let id = UUID().uuidString
        let other = UUID().uuidString
        let json = """
        {"format":"projectm-ios.show","version":1,"id":"\(UUID().uuidString)","name":"Show","cues":[],"position":null,
         "tracks":[
          {"id":"\(id)","parameter":"effect.bloom.intensity","keyframes":[
            {"time":0,"value":0.5,"interpolation":"linear"},
            {"time":0,"value":0.7,"interpolation":"linear"},
            {"time":-5,"value":0.5,"interpolation":"linear"},
            {"time":10,"value":[1,0,0,1],"interpolation":"linear"},
            {"time":20,"value":true,"interpolation":"linear"},
            {"time":30,"value":0.5,"interpolation":"bounce"},
            {"time":40,"value":0.9,"interpolation":"hold"}]},
          {"id":"\(other)","parameter":"effect.bloom.intensity","keyframes":[]},
          {"id":"not-a-uuid","parameter":"effect.bloom.radius","keyframes":[]},
          {"id":"\(UUID().uuidString)","parameter":"Bad ID","keyframes":[]},
          {"id":"\(UUID().uuidString)","parameter":"visual.palette.color","keyframes":[{"time":5,"value":[1,2,0,1],"interpolation":"linear"}]},
          42
         ]}
        """
        let decoded = try ShowCueList.decode(Data(json.utf8))
        XCTAssertEqual(decoded.warnings, [.droppedKeyframeTracks(4), .droppedKeyframes(6)])
        XCTAssertEqual(decoded.list.tracks.tracks.count, 2)
        XCTAssertEqual(decoded.list.tracks.tracks[0].keyframes.map(\.time), [0, 40])
        XCTAssertTrue(decoded.list.tracks.tracks[1].isEmpty)   // its only keyframe had a component above 1

        let unreadable = """
        {"format":"projectm-ios.show","version":1,"id":"\(UUID().uuidString)","name":"Show","cues":[],"position":null,"tracks":7}
        """
        let second = try ShowCueList.decode(Data(unreadable.utf8))
        XCTAssertEqual(second.warnings, [.droppedKeyframeTracks(1)])
        XCTAssertTrue(second.list.tracks.isEmpty)
    }

    private static func bits(_ value: ShowKeyframeValue) -> [UInt64] {
        switch value {
        case let .number(v): [v.bitPattern]
        case let .color(c): c.components.map(\.bitPattern)
        }
    }
}
