// UITestFakeSource.swift — a scriptable source for StatusUITests (task T093). DEBUG builds only;
// Release builds contain none of this.
//
// Launch arguments:
//   -uitestFake <mode>               replace that mode's real source with this fake
//                                    (systemAppCapture, microphone or inAppPlayback)
//   -uitestFakeStartError <reason>   `start` throws SourceError(reason) (a StopReason code;
//                                    "error" uses the detail "fake failure")
// While the visualizer shows, FakeSourcePanel offers buttons the tests tap to write loud, silent or
// no audio and to emit source events; `fake:starts` shows how often `start` ran (FR-055).
#if DEBUG
import AudioCore
import CaptureKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class UITestFakeSource: AudioSource {
    enum Level { case none, silent, loud }

    let mode: AudioSourceMode
    var availability: SourceAvailability = .available
    private(set) var starts = 0
    @ObservationIgnored private var sink: PCMSink?
    @ObservationIgnored private var continuation: AsyncStream<SourceEvent>.Continuation?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var level: Level = .none
    @ObservationIgnored private let startError: StopReason?

    /// The fake requested by the launch arguments, if any.
    static func fromLaunchArguments() -> UITestFakeSource? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: "uitestFake"), let mode = AudioSourceMode(rawValue: raw) else { return nil }
        let error = defaults.string(forKey: "uitestFakeStartError").flatMap(Self.reason)
        return UITestFakeSource(mode: mode, startError: error)
    }

    init(mode: AudioSourceMode, startError: StopReason?) {
        self.mode = mode
        self.startError = startError
    }

    static func reason(_ code: String) -> StopReason? {
        switch code {
        case "cancelled": return .cancelled
        case "permissionDenied": return .permissionDenied
        case "microphoneUnavailable": return .microphoneUnavailable
        case "inAppPlaybackFailed": return .inAppPlaybackFailed
        case "interrupted": return .interrupted
        case "audioRouteChanged": return .audioRouteChanged
        case "endedBySystem": return .endedBySystem
        case "unsupportedOS": return .unsupportedOS
        case "screenRecordingNotAllowed": return .screenRecordingNotAllowed
        case "error": return .error("fake failure")
        default: return nil
        }
    }

    func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
        starts += 1
        if let startError { throw SourceError(startError) }
        self.sink = sink
        let (stream, continuation) = AsyncStream.makeStream(of: SourceEvent.self)
        self.continuation = continuation
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeAudio() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        return stream
    }

    func stop() async {
        timer?.invalidate()
        timer = nil
        sink = nil
        continuation?.finish()
        continuation = nil
    }

    func suspend() async {}
    func resume() async throws {}

    func set(_ level: Level) { self.level = level }
    func emit(_ event: SourceEvent) { continuation?.yield(event) }

    /// 20 ms of 48 kHz stereo at the current level (none writes nothing).
    private func writeAudio() {
        guard let sink, level != .none else { return }
        let amplitude: Float = level == .loud ? 0.5 : 0.0001
        let frames = 960
        let samples = [Float](repeating: amplitude, count: frames * 2)
        let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)
        samples.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: frames, format: format) }
    }
}

/// Buttons the UI tests tap to drive the fake.
struct FakeSourcePanel: View {
    let fake: UITestFakeSource

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(fake.starts)").accessibilityIdentifier("fake:starts").accessibilityValue("\(fake.starts)")
            HStack(spacing: 2) {
                button("fake:loud") { fake.set(.loud) }
                button("fake:silent") { fake.set(.silent) }
                button("fake:none") { fake.set(.none) }
                button("fake:interrupt") { fake.emit(.interruptionBegan) }
                button("fake:routeLost") { fake.emit(.outputRouteLost) }
                button("fake:ended") { fake.emit(.endedBySystem("fake")) }
            }
            HStack(spacing: 2) {
                button("fake:fail:microphoneUnavailable") { fake.emit(.failed(.microphoneUnavailable)) }
                button("fake:fail:inAppPlaybackFailed") { fake.emit(.failed(.inAppPlaybackFailed)) }
            }
        }
        .font(.system(size: 9))
        .buttonStyle(.bordered)
        .padding(4)
        .background(.black.opacity(0.6))
    }

    private func button(_ id: String, action: @escaping () -> Void) -> some View {
        Button(id, action: action).accessibilityIdentifier(id)
    }
}
#endif
