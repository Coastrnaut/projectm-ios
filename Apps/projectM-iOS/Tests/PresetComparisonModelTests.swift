// PRE-009-T10: the comparison model with a fake runner and reader (spec R1-R14; contract C1, C4). The GPU path and
// the lockstep are proven in ANGLERendering's PresetComparisonRunnerTests; here the picks, the shared tick stamping,
// the test signal, the panes and the visual pause/resume.
import AudioCore
import FlashSafety
import PresetLibrary
import Rendering
import XCTest
@testable import projectM_iOS

@MainActor
final class PresetComparisonModelTests: XCTestCase {
    private final class FakeComparing: PresetComparing, @unchecked Sendable {
        private let lock = NSLock()
        private var _ticks: [PresetComparisonTick] = []
        private var _starts = 0
        private var _stops = 0
        var refuseStarts = 0
        var ticks: [PresetComparisonTick] { lock.lock(); defer { lock.unlock() }; return _ticks }
        var starts: Int { lock.lock(); defer { lock.unlock() }; return _starts }
        var stops: Int { lock.lock(); defer { lock.unlock() }; return _stops }
        var configuration: PresetComparisonConfiguration?

        func start(_ a: Data, _ b: Data, configuration: PresetComparisonConfiguration,
                   onEvent: @escaping @Sendable (PresetComparisonEvent) -> Void) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if refuseStarts > 0 {
                refuseStarts -= 1
                return false
            }
            _starts += 1
            self.configuration = configuration
            return true
        }

        func submit(_ tick: PresetComparisonTick) { lock.lock(); _ticks.append(tick); lock.unlock() }
        func stop() { lock.lock(); _stops += 1; lock.unlock() }
    }

    private final class FakeReader: NormalizedPCMReader, @unchecked Sendable {
        private let lock = NSLock()
        var blocks: [[Float]] = []
        func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
            lock.lock(); defer { lock.unlock() }
            guard !blocks.isEmpty else { return 0 }
            let block = blocks.removeFirst()
            let frames = min(block.count / 2, maxFrames)
            for index in 0..<frames * 2 { dst[index] = block[index] }
            return frames
        }
    }

    private func preset(_ name: String) -> IndexedPreset {
        IndexedPreset(id: "included/\(name).milk", name: name, author: "", source: "included", folder: [], path: "\(name).milk", hash: name)
    }

    private var fake = FakeComparing()
    private var reader = FakeReader()
    private var paused = 0
    private var resumed = 0
    private var announced: [String] = []

    private func makeModel(available: Bool = true) -> PresetComparisonModel {
        let fake = self.fake
        let reader = self.reader
        let model = PresetComparisonModel(contents: { (preset: IndexedPreset) async throws -> Data in Data(preset.name.utf8) },
                                          comparing: { available ? fake : nil },
                                          reader: { reader },
                                          configuration: { PresetComparisonConfiguration(rate: 30, flash: .reduceFlashing) })
        model.pauseVisual = { [weak self] in self?.paused += 1 }
        model.resumeVisual = { [weak self] in self?.resumed += 1 }
        model.announce = { [weak self] (text: String) in self?.announced.append(text) }
        model.sleep = { (_: Duration) in try? await Task.sleep(for: .seconds(60)) }   // ticks are driven by the test
        return model
    }

    private func waitForStart(_ count: Int = 1) async {
        for _ in 0..<500 where fake.starts < count || fake.ticks.isEmpty { try? await Task.sleep(for: .milliseconds(2)) }
    }

    func testPicksWaitThenOpenASessionAndClosingTheBrowserClearsThem() {
        let model = makeModel()
        XCTAssertTrue(model.isAvailable)
        XCTAssertEqual(model.menuTitle(), "Compare…")
        model.pick(preset("Aurora"), from: .all)
        XCTAssertEqual(model.pending?.preset.name, "Aurora")
        XCTAssertEqual(model.menuTitle(), "Compare with Aurora")
        model.pick(preset("Aurora"), from: .all)
        XCTAssertNil(model.session, "the same preset twice compares nothing")
        model.cancelPick()
        XCTAssertNil(model.pending)

        model.pick(preset("Aurora"), from: .all)
        model.pick(preset("Nebula"), from: .favorites)
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.session?.a.preset.name, "Aurora")
        XCTAssertEqual(model.session?.b.scope, .favorites)
        XCTAssertEqual(paused, 1, "R10: the shown visual pauses")
        XCTAssertEqual(announced, ["Comparing Aurora and Nebula."])

        model.pick(preset("Comet"), from: .all)
        model.browserClosed()
        XCTAssertNil(model.pending)
        XCTAssertNil(model.session)
        XCTAssertEqual(resumed, 1, "and resumes when the comparison ends")
        XCTAssertFalse(makeModel(available: false).isAvailable)
    }

    func testTicksShareOneTimelineAndSilenceCarriesTheTestSignal() async {
        reader.blocks = [[Float](repeating: 0.25, count: 200)]   // 100 live frames, then silence
        let model = makeModel()
        model.open(.init(preset: preset("Aurora"), scope: .all), .init(preset: preset("Nebula"), scope: .all))
        await waitForStart()
        XCTAssertEqual(fake.configuration?.rate, 30)
        XCTAssertEqual(fake.configuration?.flash, .reduceFlashing, "R9: the clamp's envelope")
        model.tick(fake, rate: 30)
        model.tick(fake, rate: 30)
        let ticks = fake.ticks
        XCTAssertEqual(ticks.map(\.index), [0, 1, 2])
        XCTAssertEqual(ticks[0].frameCount, 100)
        XCTAssertEqual(ticks[0].samples.first, 0.25)
        XCTAssertEqual(ticks[1].frameCount, 1_470, "R7: a 30 fps tick of the test signal")
        XCTAssertEqual(ticks.map(\.firstSample), [0, 100, 1_570])
        XCTAssertEqual(ticks[2].frameTime, 2.0 / 30, accuracy: 1e-12)
        XCTAssertEqual(ticks[2].samples, PresetComparisonModel.testSignal(startFrame: 1_470, count: 1_470), "continued, no restart")
        XCTAssertTrue(model.usingTestSignal)
        model.close()
        XCTAssertGreaterThanOrEqual(fake.stops, 1)
    }

    func testPanesShowFramesFailuresAndTheTwentySecondLimit() async throws {
        let model = makeModel()
        model.open(.init(preset: preset("Aurora"), scope: .all), .init(preset: preset("Nebula"), scope: .all))
        await waitForStart()
        let id = try XCTUnwrap(model.session?.id)
        var timeline = PresetComparisonTimeline(rate: 30)
        let mailbox = PresetComparisonMailbox()
        mailbox.post(timeline.stamp([0, 0]))
        let delivery = PresetComparisonDelivery(try XCTUnwrap(mailbox.take()))
        let pixels = Data(repeating: 200, count: 4 * 2 * 4)
        model.handle(.frame(PresetComparisonFrame(width: 4, height: 2, a: pixels, b: nil, delivery: delivery)), session: id)
        XCTAssertEqual(model.states, [.showing, .loading])
        XCTAssertNotNil(model.images[0])
        model.handle(.failed(.a, "boom"), session: id + 1)   // another session's event changes nothing
        XCTAssertEqual(model.states[0], .showing)
        for _ in 0..<600 { model.tick(fake, rate: 30) }   // 20 s of timeline without a frame for B
        XCTAssertEqual(model.states, [.showing, .failed("Nebula could not be shown.")], "R14")
        model.handle(.stopped("The app left the screen."), session: id)
        XCTAssertEqual(model.notice, "The app left the screen.")
    }

    func testPlayBEndsTheSessionAndReturnsItsPickAndARefusedStartIsRetried() async {
        fake.refuseStarts = 2   // a previous worker still finishing
        let model = makeModel()
        model.sleep = { (duration: Duration) in
            if duration == .milliseconds(100) { return }   // retries pass at once
            try? await Task.sleep(for: .seconds(60))
        }
        model.open(.init(preset: preset("Aurora"), scope: .all), .init(preset: preset("Nebula"), scope: .favorites))
        await waitForStart()
        XCTAssertEqual(fake.starts, 1, "started after two refusals")
        let pick = model.choose(.b)
        XCTAssertEqual(pick?.preset.name, "Nebula")
        XCTAssertEqual(pick?.scope, .favorites)
        XCTAssertNil(model.session)
        XCTAssertEqual(resumed, 1)
        XCTAssertNil(model.choose(.a), "nothing to choose without a session")
    }

    func testTheRateHalvesUnderLowPowerOrSeriousThermalState() {
        XCTAssertEqual(PresetComparisonModel.rate(lowPower: false, thermal: .nominal), 30)
        XCTAssertEqual(PresetComparisonModel.rate(lowPower: true, thermal: .nominal), 15)
        XCTAssertEqual(PresetComparisonModel.rate(lowPower: false, thermal: .serious), 15)
        XCTAssertEqual(PresetComparisonModel.rate(lowPower: false, thermal: .fair), 30)
    }
}
