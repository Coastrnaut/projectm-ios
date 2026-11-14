// PresetComparisonModel.swift — roadmap PRE-009 preset comparison (specs/235-pre-009-preset-comparison; contract
// C1, C4; research PRE-009-D1, D7-D10).
//
// * Picks: "Compare…" on a browser row makes it A (`pending`); "Compare with <A>" on another row makes it B and
//   opens the session (the Compare sheet). The picks keep the list they came from, so Play A/B chooses exactly as a
//   tap on that row would (R4).
// * The tick driver runs on the main actor: each tick reads the renderer's attached reader once (its only consumer,
//   D1), stamps the block on one shared timeline and submits it to the renderer's `presetComparison`, which feeds
//   the identical block and frame time to both engines (R5, R6). With no live audio the tick carries a
//   deterministic test signal (D9, R7). The rate is fixed at the start: 30, or 15 under Low Power Mode or a serious
//   thermal state (R8).
// * The shown visual pauses while a session runs and the app's normal visual switch restores it (R10).
// * A pane without a frame after 20 s of ticks, or whose preset failed, says so; the other keeps drawing (R11, R14).
// * Memory pressure stops the previews (R12). Nothing is stored (R13). Announcements use the library lane.
import AudioCore
import Foundation
import PresetLibrary
import Rendering
import UIKit

@MainActor
@Observable
final class PresetComparisonModel {
    /// A preset and the list it was picked from.
    struct Pick: Equatable {
        let preset: IndexedPreset
        let scope: PresetScope
    }

    /// The Compare sheet's two picks (fixed for the sheet).
    struct Session: Identifiable, Equatable {
        let id: Int
        let a: Pick
        let b: Pick

        func pick(_ side: PresetComparisonSide) -> Pick { side == .a ? a : b }
    }

    enum PaneState: Equatable {
        case loading
        case showing
        case failed(String)
    }

    /// R14: a pane with no frame after this much timeline time says it could not be shown.
    nonisolated static let firstFrameLimit: Double = 20
    /// Most frames read from the live input per tick (0.1 s at 44.1 kHz; the ring keeps at most 50 ms).
    nonisolated static let maxReadFrames = 4_410
    nonisolated static let testSignalText = "No audio playing: showing a test signal."
    nonisolated static func comparingText(_ a: String, _ b: String) -> String { "Comparing \(a) and \(b)." }
    nonisolated static func failedText(_ name: String) -> String { "\(name) could not be shown." }
    nonisolated static let memoryText = "The previews stopped to free memory."
    nonisolated static let busyText = "The previews could not start. Close and try again."

    private(set) var pending: Pick?
    /// The open Compare sheet (its `item`).
    var session: Session?
    private(set) var images: [UIImage?] = [nil, nil]
    private(set) var states: [PaneState] = [.loading, .loading]
    /// R7: the last tick carried the test signal.
    private(set) var usingTestSignal = false
    /// Why the previews stopped (the app left the screen, memory, a refused start).
    private(set) var notice: String?
    /// Frame pairs shown in this session (tests).
    private(set) var framesShown = 0
    /// Ticks submitted in this session (tests).
    private(set) var ticksSubmitted = 0

    @ObservationIgnored private let contents: @MainActor (IndexedPreset) async throws -> Data
    @ObservationIgnored private let comparing: @MainActor () -> (any PresetComparing)?
    @ObservationIgnored private let reader: @MainActor () -> (any NormalizedPCMReader)?
    @ObservationIgnored private let configuration: @MainActor () -> PresetComparisonConfiguration
    @ObservationIgnored var pauseVisual: () -> Void = {}
    @ObservationIgnored var resumeVisual: () -> Void = {}
    @ObservationIgnored var announce: (String) -> Void = { (_: String) in }
    /// The pause between ticks (tests replace it).
    @ObservationIgnored var sleep: @MainActor (Duration) async -> Void = { (duration: Duration) in try? await Task.sleep(for: duration) }
    @ObservationIgnored private var timeline = PresetComparisonTimeline(rate: PresetComparisonConfiguration.standardRate)
    @ObservationIgnored private var driver: Task<Void, Never>?
    @ObservationIgnored private var runner: (any PresetComparing)?
    @ObservationIgnored private var nextSessionID = 0
    @ObservationIgnored private var visualPaused = false
    @ObservationIgnored private var testSignalFrame = 0
    @ObservationIgnored private let buffer: UnsafeMutablePointer<Float>
    @ObservationIgnored private var memoryObserver: NSObjectProtocol?

    init(contents: @escaping @MainActor (IndexedPreset) async throws -> Data,
         comparing: @escaping @MainActor () -> (any PresetComparing)?,
         reader: @escaping @MainActor () -> (any NormalizedPCMReader)?,
         configuration: @escaping @MainActor () -> PresetComparisonConfiguration) {
        self.contents = contents
        self.comparing = comparing
        self.reader = reader
        self.configuration = configuration
        buffer = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxReadFrames * 2)
        buffer.initialize(repeating: 0, count: Self.maxReadFrames * 2)
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                object: nil, queue: .main) { [weak self] (_: Notification) in
            MainActor.assumeIsolated { self?.stopForMemory() }
        }
    }

    isolated deinit {
        if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
        driver?.cancel()
        runner?.stop()
        buffer.deinitialize(count: Self.maxReadFrames * 2)
        buffer.deallocate()
    }

    /// The renderer can run the previews (the GLES fallback cannot).
    var isAvailable: Bool { comparing() != nil }

    // MARK: - Picks (R1, R2)

    /// "Compare…" (no pick waiting) or "Compare with <A>".
    func menuTitle() -> String {
        guard let pending else { return "Compare…" }
        return "Compare with \(pending.preset.name)"
    }

    /// The row's Compare action: the first pick waits as A, a different second one opens the session.
    func pick(_ preset: IndexedPreset, from scope: PresetScope) {
        guard let first = pending else {
            pending = Pick(preset: preset, scope: scope)
            return
        }
        guard first.preset != preset else { return }   // the same preset twice compares nothing
        open(first, Pick(preset: preset, scope: scope))
    }

    func cancelPick() { pending = nil }

    /// Closing the browser: no pick waits and no session runs (spec Clarifications).
    func browserClosed() {
        pending = nil
        close()
    }

    // MARK: - Session (R3-R12)

    func open(_ a: Pick, _ b: Pick) {
        close()
        pending = nil
        nextSessionID += 1
        let session = Session(id: nextSessionID, a: a, b: b)
        self.session = session
        images = [nil, nil]
        states = [.loading, .loading]
        notice = nil
        usingTestSignal = false
        framesShown = 0
        ticksSubmitted = 0
        announce(Self.comparingText(a.preset.name, b.preset.name))
        pauseVisual()
        visualPaused = true
        driver = Task { @MainActor [weak self] in await self?.run(session) }
    }

    /// Close, a swipe down, Play A/B: stops the previews and restores the shown visual.
    func close() {
        driver?.cancel()
        driver = nil
        runner?.stop()
        runner = nil
        session = nil
        images = [nil, nil]
        if visualPaused {
            visualPaused = false
            resumeVisual()
        }
    }

    /// Play A or B (R4): ends the session and returns the pick for the browser's choose.
    func choose(_ side: PresetComparisonSide) -> Pick? {
        guard let pick = session?.pick(side) else { return nil }
        close()
        return pick
    }

    private func run(_ session: Session) async {
        var data: [Data] = []
        for side in PresetComparisonSide.allCases {
            do {
                data.append(try await contents(session.pick(side).preset))
            } catch {
                data.append(Data())   // the runner reports it as failed; the other side still draws
            }
        }
        guard !Task.isCancelled, self.session?.id == session.id else { return }
        guard let comparing = comparing() else {
            notice = Self.busyText
            return
        }
        let settings = configuration()
        timeline = PresetComparisonTimeline(rate: settings.rate)
        testSignalFrame = 0
        let id = session.id
        let handler: @Sendable (PresetComparisonEvent) -> Void = { [weak self] (event: PresetComparisonEvent) in
            Task { @MainActor in self?.handle(event, session: id) }
        }
        var started = comparing.start(data[0], data[1], configuration: settings, onEvent: handler)
        var attempts = 0
        while !started && attempts < 20 && !Task.isCancelled {   // a previous worker may still be finishing (edge case)
            attempts += 1
            await sleep(.milliseconds(100))
            started = comparing.start(data[0], data[1], configuration: settings, onEvent: handler)
        }
        guard started, !Task.isCancelled, self.session?.id == id else {
            if started { comparing.stop() } else { notice = Self.busyText }
            return
        }
        runner = comparing
        let period: Duration = .microseconds(Int64(1_000_000 / settings.rate))
        while !Task.isCancelled && self.session?.id == id {
            tick(comparing, rate: settings.rate)
            await sleep(period)
        }
    }

    /// One tick: one read of the live input (or the test signal), stamped once, submitted once for both engines.
    func tick(_ comparing: any PresetComparing, rate: Double) {
        let read = reader()?.read(into: buffer, maxFrames: Self.maxReadFrames) ?? 0
        let samples: [Float]
        if read > 0 {
            samples = Array(UnsafeBufferPointer(start: buffer, count: read * 2))
            usingTestSignalIfChanged(false)
        } else {
            let count = Int(NormalizedPCMRing.sampleRate / rate)
            samples = Self.testSignal(startFrame: testSignalFrame, count: count)
            testSignalFrame += count
            usingTestSignalIfChanged(true)
        }
        comparing.submit(timeline.stamp(samples))
        ticksSubmitted += 1
        let elapsed = Double(ticksSubmitted) / rate
        if elapsed >= Self.firstFrameLimit, let session {
            for side in PresetComparisonSide.allCases where states[side.rawValue] == .loading {
                states[side.rawValue] = .failed(Self.failedText(session.pick(side).preset.name))
            }
        }
    }

    private func usingTestSignalIfChanged(_ value: Bool) {
        if usingTestSignal != value { usingTestSignal = value }
    }

    func handle(_ event: PresetComparisonEvent, session id: Int) {
        guard let session, session.id == id else { return }
        switch event {
        case .loaded:
            break
        case .failed(let side, _):
            states[side.rawValue] = .failed(Self.failedText(session.pick(side).preset.name))
        case .frame(let frame):
            framesShown += 1
            for side in PresetComparisonSide.allCases {
                let pixels: Data? = side == .a ? frame.a : frame.b
                guard let pixels, states[side.rawValue] != .failed(Self.failedText(session.pick(side).preset.name)) else { continue }
                images[side.rawValue] = Self.image(rgba: pixels, width: frame.width, height: frame.height)
                states[side.rawValue] = .showing
            }
        case .stopped(let reason):
            notice = reason
        }
    }

    private func stopForMemory() {
        guard session != nil, runner != nil else { return }
        driver?.cancel()
        driver = nil
        runner?.stop()
        runner = nil
        notice = Self.memoryText
    }

    // MARK: - Helpers

    /// R7: the PRE-001 thumbnail signal's shape (110 Hz bass on a beat every 15 thumbnail frames, a quieter 440 Hz
    /// tone), without its noise, continued across ticks so it has no clicks.
    nonisolated static func testSignal(startFrame: Int, count: Int) -> [Float] {
        let rate: Double = NormalizedPCMRing.sampleRate
        let beatLength: Double = 15 * 735
        var samples = [Float](repeating: 0, count: max(0, count) * 2)
        for index in 0..<max(0, count) {
            let n = Double(startFrame + index)
            let t: Double = n / rate
            let sinceBeat: Double = n.truncatingRemainder(dividingBy: beatLength) / beatLength
            let envelope: Double = 0.3 + 0.7 * (1 - sinceBeat) * (1 - sinceBeat)
            let bass: Double = 0.5 * sin(2 * Double.pi * 110 * t) * envelope
            let tone: Double = 0.2 * sin(2 * Double.pi * 440 * t)
            samples[index * 2] = Float(bass + tone)
            samples[index * 2 + 1] = Float(bass - tone)
        }
        return samples
    }

    /// RGBA8 rows (top first) as an opaque image.
    nonisolated static func image(rgba: Data, width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0, rgba.count == width * height * 4,
              let provider = CGDataProvider(data: rgba as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image)
    }

    /// R8: 15 ticks per second under Low Power Mode or a serious thermal state, else 30.
    nonisolated static func rate(lowPower: Bool, thermal: ProcessInfo.ThermalState) -> Double {
        lowPower || thermal == .serious || thermal == .critical ? PresetComparisonConfiguration.reducedRate
            : PresetComparisonConfiguration.standardRate
    }
}
