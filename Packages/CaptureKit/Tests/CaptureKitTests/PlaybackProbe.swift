// PlaybackProbe.swift — plays a file through the production playback graph, rendered offline, and
// returns what reached the sink per output channel (AUD-002-T06). Test support only.
#if canImport(AVFAudio)
import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
enum PlaybackProbe {
    struct Capture {
        var left: [Float] = []
        var right: [Float] = []
        var outputRate: Double

        /// Samples from the first one above `threshold` on, at most `seconds` long.
        func audible(_ channel: [Float], seconds: Double, threshold: Float = 0.02) -> ArraySlice<Float> {
            guard let start = channel.firstIndex(where: { abs($0) > threshold }) else { return [] }
            return channel[start..<min(channel.count, start + Int(seconds * outputRate))]
        }

        /// Frequency by zero crossings over the audible part.
        func frequency(_ channel: [Float], seconds: Double) -> Double {
            let samples = audible(channel, seconds: seconds)
            guard samples.count > 1 else { return 0 }
            var crossings = 0
            var previous = samples[samples.startIndex]
            for sample in samples.dropFirst() {
                if (previous < 0) != (sample < 0) { crossings += 1 }
                previous = sample
            }
            return Double(crossings) / 2 / (Double(samples.count) / outputRate)
        }

        func peak(_ channel: [Float]) -> Float { channel.reduce(0) { max($0, abs($1)) } }
    }

    /// Loads `url` as a library track, renders until `seconds` of audio followed the first audible
    /// sample (or `budgetSeconds` of output were rendered), and returns the sink's content.
    static func play(_ url: URL, outputRate: Double = 48_000, seconds: Double = 0.3, budgetSeconds: Double = 20) async throws -> Capture {
        let graph = InAppPlaybackGraph(content: try InAppPlaybackGraph.load(.file(url), bundle: .main))
        try graph.enableOfflineRendering(sampleRate: outputRate, maximumFrameCount: 1024)
        let sink = PCMSink()
        try graph.installTap(into: sink)
        try graph.start()
        defer { graph.stop() }
        return try await capture(graph, sink: sink, outputRate: outputRate, seconds: seconds, budgetSeconds: budgetSeconds)
    }

    /// Renders an already started graph; see `play`.
    static func capture(_ graph: InAppPlaybackGraph, sink: PCMSink, outputRate: Double, seconds: Double,
                        budgetSeconds: Double = 20) async throws -> Capture {
        var capture = Capture(outputRate: outputRate)
        var scratch = [Float](repeating: 0, count: 8192)
        var rendered = 0
        var onset: Int?
        let wanted = Int(seconds * outputRate)
        // The offline output is always stereo (`enableOfflineRendering`). The tap delivers on its
        // own thread, so the sink's channel count may not be published yet when samples arrive;
        // it is not consulted. An odd sample left by a read is carried into the next one.
        var carry: Float?
        while rendered < Int(outputRate * budgetSeconds) {
            rendered += try graph.renderOffline(frames: 1024)
            var gotAudio = false
            while true {
                let count = scratch.withUnsafeMutableBufferPointer { sink.ring.read(into: $0.baseAddress!, maxCount: $0.count) }
                if count == 0 { break }
                var index = 0
                while index < count {
                    let left: Float
                    if let pending = carry {
                        left = pending
                        carry = nil
                    } else {
                        left = scratch[index]
                        index += 1
                        guard index < count else { carry = left; break }
                    }
                    let right = scratch[index]
                    index += 1
                    if abs(left) > 0.02 || abs(right) > 0.02 {
                        gotAudio = true
                        if onset == nil { onset = capture.left.count }
                    }
                    capture.left.append(left)
                    capture.right.append(right)
                }
            }
            if let onset, capture.left.count - onset >= wanted { break }
            // The loop is rescheduled by a main-actor task; let it run between render calls.
            if gotAudio { await Task.yield() } else { try await Task.sleep(nanoseconds: 2_000_000) }
        }
        return capture
    }
}
#endif
