// RecordingCountdownAppTests.swift — REC-007-T08, T10 (specs/175-rec-007-countdown; contract C1, C2).
// The countdown runs on a manual clock that also drives the status router, so no test waits or reads the
// wall clock (owner rule 7). The recording source is a 64 × 48 offscreen fake on the simulator GPU; a writer
// is created only when a recording really starts. Simulator results are never device evidence (Constitution X).
import Metal
import XCTest
@testable import projectM_iOS

/// A clock the test advances by hand; it serves the countdown and the status router.
@MainActor
private final class ManualClock: RecordingCountdownClock {
    final class Step: RecordingCountdownTimer {
        let deadline: Double
        let action: @MainActor () -> Void
        var cancelled = false
        init(deadline: Double, action: @escaping @MainActor () -> Void) {
            self.deadline = deadline
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    var now: Double = 100
    private var steps: [Step] = []

    func schedule(at deadline: Double, _ action: @escaping @MainActor () -> Void) -> any RecordingCountdownTimer {
        let step = Step(deadline: deadline, action: action)
        steps.append(step)
        return step
    }

    /// Runs every due step in time order, then sets the clock to `time`.
    func advance(to time: Double) {
        while let next = steps.filter({ (s: Step) -> Bool in !s.cancelled && s.deadline <= time })
            .min(by: { (a: Step, b: Step) -> Bool in a.deadline < b.deadline }) {
            steps.removeAll { (s: Step) -> Bool in s === next }
            now = max(now, next.deadline)
            next.action()
        }
        now = time
    }

    var pendingSteps: Int { steps.filter { (s: Step) -> Bool in !s.cancelled }.count }
}

@MainActor
private final class CountdownSource: VideoRecordingSource {
    let recordingDevice: MTLDevice
    var recordingDrawableSize = CGSize(width: 64, height: 48)
    var isPresentingFrames = true
    var videoRecording: VideoRecordingTap?
    init(device: MTLDevice) { recordingDevice = device }
}

@MainActor
private final class ContextBox {
    var value: VideoRecordingCoordinator.Context
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

@MainActor
final class RecordingCountdownAppTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() async throws {
        let folders = await MainActor.run { () -> [URL] in self.folders }
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
    }

    private struct Rig {
        let recording: VideoRecordingCoordinator
        let clock: ManualClock
        let context: ContextBox
        let source: CountdownSource
        let folder: URL
    }

    private func rig(_ length: RecordingCountdownLength = .three) throws -> Rig {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let source = CountdownSource(device: device)
        var c = VideoRecordingCoordinator.Context(source: source, visualShown: true, outputLive: true, paused: false)
        c.countdown = length
        let box = ContextBox(c)
        let clock = ManualClock()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rec007-\(UUID().uuidString)", isDirectory: true)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("rec007-out-\(UUID().uuidString)", isDirectory: true)
        folders += [folder, out]
        let recording = VideoRecordingCoordinator(directory: folder, debugDirectory: out, checkInterval: nil,
                                                  storageCheckInterval: nil, countdownClock: clock) { () -> VideoRecordingCoordinator.Context in
            box.value
        }
        return Rig(recording: recording, clock: clock, context: box, source: source, folder: folder)
    }

    private func files(in folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    /// Stops a running recording and waits for its finish (the fake source drew no frames: it fails, nothing kept).
    private func finish(_ r: Rig) {
        r.clock.advance(to: r.clock.now + 1)   // past the 0.5 s start guard
        r.recording.toggle()
        let done = expectation(description: "finished")
        Task { @MainActor in
            while r.recording.state != .idle { try? await Task.sleep(for: .milliseconds(10)) }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    // MARK: - Acceptance (REC-007-S1, S2)

    /// S1: a 3 s countdown cancelled at 1.5 s creates no writer and no file, and nothing starts later.
    func testCancelAtOneAndAHalfSecondsCreatesNoFile() throws {
        let r = try rig()
        r.recording.toggle()
        XCTAssertEqual(r.recording.state, .countingDown(3))
        XCTAssertEqual(r.recording.writerCreations, 0, "no writer while counting")
        r.clock.advance(to: 101)
        XCTAssertEqual(r.recording.state, .countingDown(2))
        r.clock.advance(to: 101.5)
        r.recording.toggle()   // Record again cancels
        XCTAssertEqual(r.recording.state, .idle)
        XCTAssertEqual(r.recording.lastCountdownCancel, .user)
        r.clock.advance(to: 110)
        XCTAssertEqual(r.recording.state, .idle, "a cancelled countdown never completes")
        XCTAssertEqual(r.recording.writerCreations, 0)
        XCTAssertEqual(files(in: r.folder), [], "no file in the recordings folder")
        XCTAssertNil(r.source.videoRecording, "no frame tap attached")
        XCTAssertEqual(r.clock.pendingSteps, 0, "nothing left scheduled")
        XCTAssertEqual(r.recording.probe, "none")
    }

    /// S2: a completed countdown starts exactly once; Record at 2.99 s neither cancels nor starts twice, and
    /// Record at 3.0 s (before or after the completing tick) neither starts a second recording nor stops it.
    func testCompletedCountdownStartsOnceDespiteLateTaps() throws {
        let r = try rig()
        r.recording.toggle()
        r.clock.advance(to: 102.99)
        XCTAssertEqual(r.recording.state, .countingDown(1))
        r.recording.toggle()   // 2.99 s: inside the last 0.25 s, ignored
        XCTAssertEqual(r.recording.state, .countingDown(1))
        r.clock.now = 103   // 3.0 s, the tap arrives before the tick runs
        r.recording.toggle()
        XCTAssertEqual(r.recording.state, .countingDown(1))
        r.clock.advance(to: 103)   // the completing tick
        XCTAssertEqual(r.recording.state, .recording)
        XCTAssertEqual(r.recording.writerCreations, 1)
        XCTAssertNotNil(r.source.videoRecording)
        r.recording.toggle()   // 3.0 s, after the tick: inside the 0.5 s start guard
        XCTAssertEqual(r.recording.state, .recording, "no stop")
        r.clock.advance(to: 103.4)
        r.recording.toggle()
        XCTAssertEqual(r.recording.state, .recording, "still inside the start guard")
        r.clock.advance(to: 120)
        XCTAssertEqual(r.recording.writerCreations, 1, "exactly one writer start")
        XCTAssertNil(r.recording.lastStopReason)
        finish(r)
        XCTAssertEqual(r.recording.lastStopReason, .user, "after the guard Record stops as usual")
        XCTAssertEqual(r.recording.writerCreations, 1)
    }

    /// Off: Record starts in the same call (S3); a 5 s countdown starts at 5 s.
    func testOffStartsImmediately() throws {
        let r = try rig(.off)
        r.recording.toggle()
        XCTAssertEqual(r.recording.state, .recording)
        XCTAssertEqual(r.recording.writerCreations, 1)
        XCTAssertEqual(r.clock.pendingSteps, 0)
        finish(r)
    }

    /// The length is read at Record: a change during a countdown applies to the next one.
    func testSettingChangeDuringACountdownKeepsItsLength() throws {
        let r = try rig(.three)
        r.recording.toggle()
        r.context.value.countdown = .ten
        r.clock.advance(to: 103)
        XCTAssertEqual(r.recording.state, .recording)
        finish(r)
    }

    // MARK: - Automatic cancellation (REC-007-S4, R5)

    func testBackgroundingCancels() throws {
        let r = try rig()
        r.recording.toggle()
        r.clock.advance(to: 101.2)
        r.recording.appEnteredBackground()
        XCTAssertEqual(r.recording.state, .idle)
        XCTAssertEqual(r.recording.lastCountdownCancel, .background)
        r.clock.advance(to: 110)
        XCTAssertEqual(r.recording.writerCreations, 0)
        XCTAssertEqual(files(in: r.folder), [])
    }

    func testLeavingTheVisualizerAndALostSourceCancel() throws {
        let r = try rig()
        r.recording.toggle()
        r.context.value.visualShown = false
        r.recording.checkContext()
        XCTAssertEqual(r.recording.lastCountdownCancel, .leftVisualizer)
        XCTAssertEqual(r.recording.state, .idle)

        r.context.value.visualShown = true
        r.recording.toggle()
        XCTAssertEqual(r.recording.state, .countingDown(3))
        r.context.value.source = nil
        r.recording.checkContext()
        XCTAssertEqual(r.recording.lastCountdownCancel, .visualLost)
        r.clock.advance(to: 110)
        XCTAssertEqual(r.recording.writerCreations, 0)
    }

    /// A refusal at the tap starts no countdown; the explicit Cancel works at the last instant.
    func testRefusalStartsNoCountdownAndCancelIsAlwaysHonored() throws {
        let r = try rig()
        r.context.value.paused = true
        r.recording.toggle()
        XCTAssertEqual(r.recording.state, .idle)
        XCTAssertEqual(r.recording.probe, "refused: paused")
        r.context.value.paused = false
        r.recording.toggle()
        r.clock.advance(to: 102.95)
        r.recording.cancelCountdown()
        XCTAssertEqual(r.recording.state, .idle)
        r.clock.advance(to: 110)
        XCTAssertEqual(r.recording.writerCreations, 0)
    }

    // MARK: - Setting (REC-007-R8)

    func testSettingDefaultsToOffAndPersists() {
        let defaults = UserDefaults(suiteName: "rec007-\(UUID().uuidString)")!
        XCTAssertEqual(RecordingCountdownSetting(defaults: defaults).length, .off)
        RecordingCountdownSetting(defaults: defaults).length = .five
        XCTAssertEqual(defaults.string(forKey: RecordingCountdownSetting.key), "5")
        XCTAssertEqual(RecordingCountdownSetting(defaults: defaults).length, .five)
        defaults.set("7", forKey: RecordingCountdownSetting.key)
        XCTAssertEqual(RecordingCountdownSetting(defaults: defaults).length, .off, "unknown reads as Off")
        XCTAssertEqual(RecordingCountdownLength.allCases.map(\.seconds), [0, 3, 5, 10])
    }

    // MARK: - Announcements (REC-007-S5, contract C2)

    func testAnnouncementsCountDownThenSayRecordingStarted() throws {
        let r = try rig()
        var posted: [String] = []
        let announcer = AccessibilityAnnouncer(post: { (text: String) in posted.append(text) },
                                               now: { () -> Double in r.clock.now },
                                               schedule: { (delay: Double, action: @escaping @MainActor () -> Void) in
                                                   _ = r.clock.schedule(at: r.clock.now + delay, action)
                                               })
        let router = StatusEventRouter(announcer: announcer,
                                       schedule: { (delay: Double, action: @escaping @MainActor () -> Void) in
                                           _ = r.clock.schedule(at: r.clock.now + delay, action)
                                       })
        var previous: VideoRecordingCoordinator.State = r.recording.state
        r.recording.onStateChange = { [unowned recording = r.recording] (state: VideoRecordingCoordinator.State) -> Void in
            if let event = StatusEventCatalog.recordingTransition(from: previous, to: state, elapsed: recording.elapsedText,
                                                                  countdownCancel: recording.lastCountdownCancel) {
                router.post(event)
            }
            previous = state
        }
        r.recording.toggle()
        r.clock.advance(to: 103.5)
        XCTAssertEqual(posted, ["Recording in 3", "2", "1", "Recording started"])
        XCTAssertTrue(announcer.spoken.allSatisfy { (s: String) -> Bool in s.hasPrefix("recording|") }, "the recording lane")
        finish(r)

        r.clock.advance(to: r.clock.now + 3)   // the lane's window after "Recording stopped" has closed
        posted.removeAll()
        r.recording.toggle()
        r.clock.advance(to: r.clock.now + 1.5)
        r.recording.toggle()
        r.clock.advance(to: r.clock.now + 2)
        XCTAssertEqual(posted, ["Recording in 3", "2", "Countdown cancelled"])
    }

    func testCountdownRows() {
        let tick = StatusEventCatalog.recordingCountdown(remaining: 2, first: false)
        XCTAssertEqual(tick.id, "X9d")
        XCTAssertEqual(tick.visibleText, "Recording in 2")
        XCTAssertEqual(tick.announcement, "2")
        let cancelled = StatusEventCatalog.countdownCancelled(.background)
        XCTAssertEqual(cancelled.id, "X9e")
        XCTAssertEqual(cancelled.presentation, .caption)
        XCTAssertEqual(cancelled.cause, .system)
        XCTAssertEqual(cancelled.announcement, "Countdown cancelled: the app went to the background.")
        XCTAssertEqual(StatusEventCatalog.countdownCancelled(.user).cause, .user)
        XCTAssertNil(StatusEventCatalog.recordingTransition(from: .countingDown(1), to: .idle, elapsed: "0:00", countdownCancel: nil),
                     "a refusal at completion posts only its notice")
    }
}
