// QA-011 pass 6 (D2, 2026-11-19): the DEBUG playback analyzer that AUD-003-T22, AUD-004-T19 and AUD-006-T40 read on
// devices. Records are built by hand from the ramp fixtures (channel 0 names the track and the position in it).
#if DEBUG
import CaptureKit
import XCTest
@testable import projectM_iOS

@MainActor
final class PlaybackAnalyzerTests: XCTestCase {
    private let rate: Float = 48_000
    private let frames: Int32 = 4800   // 100 ms, the size the tap delivers on device
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// The ramp's channel-0 value for track `k` at `t` s.
    private func ramp(_ k: Int, _ t: Double) -> Float {
        Float(UITestAudioFixtures.base(k) + UITestAudioFixtures.span * t / UITestAudioFixtures.ramps[k].seconds)
    }

    /// A voiced buffer of track `k` from `t` s (100 ms), optionally with zeros at either end.
    private func buffer(_ k: Int, from t: Double, lead: Int32 = 0, trail: Int32 = 0, cut: Bool = false)
        -> PlaybackDebugProbe.Record {
        let start = t + Double(lead) / Double(rate), end = t + Double(frames - 1 - trail) / Double(rate)
        return PlaybackDebugProbe.Record(first: lead > 0 ? 0 : ramp(k, start), last: trail > 0 ? 0 : ramp(k, end), peak: 0.2,
                                         frames: frames, sampleRate: rate, firstAfterCut: cut, leadingZeros: lead,
                                         voiced: ramp(k, start), trailingZeros: trail, lastVoiced: ramp(k, end))
    }

    private func fields(_ analyzer: UITestPlaybackAnalyzer) -> [String: String] {
        Dictionary(analyzer.summary.split(separator: " ").compactMap { part -> (String, String)? in
            let kv = part.split(separator: "=", maxSplits: 1)
            return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
        }, uniquingKeysWith: { $1 })
    }

    /// The buffer a pause stopped in ends in zeros (74 ms on D2); after the pause the resume cuts. Not a gap.
    func testZerosBeforeAPauseAreNoGap() {
        let analyzer = UITestPlaybackAnalyzer()
        analyzer.feed(buffer(1, from: 3.0), at: t0)
        analyzer.feed(buffer(1, from: 3.1, trail: 3584), at: t0.addingTimeInterval(0.1))
        analyzer.feed(buffer(1, from: 3.12, lead: 200, cut: true), at: t0.addingTimeInterval(1.6))   // resumed 1.5 s later
        analyzer.feed(buffer(1, from: 3.22), at: t0.addingTimeInterval(1.7))
        let f = fields(analyzer)
        XCTAssertEqual(f["maxSilentMs"], "0", analyzer.summary)
        XCTAssertEqual(f["cuts"], "1", analyzer.summary)
        XCTAssertEqual(f["disc"], "0", analyzer.summary)
    }

    /// The same zeros while the stream runs on (the next buffer starts with zeros, no cut) are a gap.
    func testZerosWhilePlayingAreAGap() {
        let analyzer = UITestPlaybackAnalyzer()
        analyzer.feed(buffer(1, from: 3.0, trail: 2400), at: t0)
        analyzer.feed(buffer(1, from: 3.1, lead: 1200), at: t0.addingTimeInterval(0.1))
        let silent = Int(fields(analyzer)["maxSilentMs"] ?? "") ?? -1
        XCTAssertEqual(silent, 75, analyzer.summary)   // 50 ms + 25 ms
    }

    /// Track 1 ends, zeros, track 2 starts, and neither edge of the change names a ramp position (a fade or filter
    /// ringing below the ramp): the change is still counted, at the end of track 1 (D2 passes 4-6: `changes=none`).
    func testChangeAcrossUndecodableEdgesIsCounted() {
        let analyzer = UITestPlaybackAnalyzer()
        analyzer.feed(buffer(1, from: 11.8), at: t0)
        var end = buffer(1, from: 11.9, trail: 1500)
        end.lastVoiced = 0.004
        analyzer.feed(end, at: t0.addingTimeInterval(0.1))
        var start = buffer(2, from: 0, lead: 1500)
        start.voiced = 0.003
        analyzer.feed(start, at: t0.addingTimeInterval(0.2))
        analyzer.feed(buffer(2, from: 0.1), at: t0.addingTimeInterval(0.3))
        let f = fields(analyzer)
        XCTAssertEqual(f["changes"], "1>2", analyzer.summary)
        XCTAssertEqual(f["track"], "2", analyzer.summary)
        XCTAssertEqual(f["wraps"], "0", analyzer.summary)
        XCTAssertEqual(f["rewinds"], "0", analyzer.summary)
        XCTAssertNotEqual(f["undecoded"], "none", analyzer.summary)
    }

    /// With exact edges the change is counted as before, and steady playback counts nothing.
    func testExactChangeAndSteadyPlayback() {
        let analyzer = UITestPlaybackAnalyzer()
        for i in 0..<5 { analyzer.feed(buffer(1, from: 11.5 + 0.1 * Double(i)), at: t0.addingTimeInterval(0.1 * Double(i))) }
        analyzer.feed(buffer(2, from: 0), at: t0.addingTimeInterval(0.5))
        let f = fields(analyzer)
        XCTAssertEqual(f["changes"], "1>2", analyzer.summary)
        XCTAssertEqual(f["disc"], "0", analyzer.summary)
        XCTAssertEqual(f["maxSilentMs"], "0", analyzer.summary)
    }
}
#endif
