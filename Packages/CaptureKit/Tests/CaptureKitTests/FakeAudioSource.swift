// Test double for AudioSource: records calls, emits events on demand, writes synthetic audio.
import AudioCore
@testable import CaptureKit

@MainActor
final class FakeAudioSource: AudioSource, ContentIdentifying {
    let mode: AudioSourceMode
    var availability: SourceAvailability = .available
    var startError: SourceError?
    var resumeError: SourceError?
    var contentIdentity: String?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var suspendCount = 0
    private(set) var resumeCount = 0
    private(set) var isRunning = false
    private(set) var log: [String]
    private var continuation: AsyncStream<SourceEvent>.Continuation?
    private var sink: PCMSink?

    init(mode: AudioSourceMode, sharedLog: [String] = []) {
        self.mode = mode
        log = sharedLog
    }

    func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
        startCount += 1
        log.append("start \(mode)")
        if let startError { throw startError }
        precondition(!isRunning, "duplicate session")
        isRunning = true
        self.sink = sink
        let (stream, continuation) = AsyncStream.makeStream(of: SourceEvent.self)
        self.continuation = continuation
        return stream
    }

    func stop() async {
        stopCount += 1
        log.append("stop \(mode)")
        isRunning = false
        sink = nil
        continuation?.finish()
        continuation = nil
    }

    func suspend() async { suspendCount += 1 }

    func resume() async throws {
        resumeCount += 1
        if let resumeError { throw resumeError }
    }

    func emit(_ event: SourceEvent) { continuation?.yield(event) }

    /// Writes `seconds` of constant-amplitude stereo audio at 48 kHz.
    func pushAudio(amplitude: Float, seconds: Double) {
        guard let sink else { return }
        let frames = Int(48_000 * seconds)
        let samples = [Float](repeating: amplitude, count: frames * 2)
        let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)
        samples.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: frames, format: format) }
    }
}
