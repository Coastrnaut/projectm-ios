// ReferenceAudioFeeder.swift — feeds the bundled reference track into a NormalizedPCMRing in real
// time, looping, so the renderer sees audio the way it will from a capture source (44.1 kHz
// interleaved stereo Float32, research R-05).
import AudioCore
import AVFAudio
import Foundation
import QuartzCore

@MainActor
final class ReferenceAudioFeeder {
    let ring = NormalizedPCMRing()
    private var samples: [Float] = []      // interleaved stereo at 44.1 kHz
    private var position = 0               // frame index into samples
    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0
    private var owed: Double = 0

    /// Loads `reference.wav` (44.1 kHz Int16 stereo) from the bundle.
    init() throws {
        guard let url = Bundle.main.url(forResource: "reference", withExtension: "wav") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
        guard file.processingFormat.sampleRate == NormalizedPCMRing.sampleRate, file.processingFormat.channelCount == 2,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        let frames = Int(buffer.frameLength)
        guard let data = buffer.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
        samples = Array(UnsafeBufferPointer(start: data, count: frames * 2))
    }

    func start() {
        guard timer == nil else { return }
        lastTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        owed += (now - lastTime) * NormalizedPCMRing.sampleRate
        lastTime = now
        var frames = Int(owed)
        owed -= Double(frames)
        let total = samples.count / 2
        guard total > 0 else { return }
        samples.withUnsafeBufferPointer { all in
            while frames > 0 {
                let n = min(frames, total - position)
                ring.write(all.baseAddress! + position * 2, frames: n)
                position = (position + n) % total
                frames -= n
            }
        }
    }
}
