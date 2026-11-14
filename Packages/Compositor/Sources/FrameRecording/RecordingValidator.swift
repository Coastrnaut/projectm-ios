// RecordingValidator.swift — QA-008 reads a recorded file into a `RecordingMeasurement` and checks it with
// `RecordingValidation` (specs/163-qa-008-recording-validation, QA-008-R1 to R9; research QA-008-D4, D5).
// Codec, size, times, duration and audio format come from REC-003's `RecordedVideoInspector` (no video
// decoding); the audio track is decoded to LPCM for its sample count and breaks; the flash/click marker
// finders are REC-004's (moved here from its test, same thresholds). No GPU needed.
#if canImport(AVFoundation)
import AVFoundation
import CoreVideo
import Foundation

public enum RecordingValidator {
    /// REC-004 marker thresholds: a frame whose centre pixel's green byte is above this is the flash.
    public static let flashThreshold: UInt8 = 128
    /// An audio sample whose magnitude is above this is the click.
    public static let clickThreshold: Float = 0.3

    /// Reads and checks the file.
    public static func validate(_ url: URL, expectation: RecordingExpectation = RecordingExpectation()) async -> RecordingValidationReport {
        guard let measurement = await measure(url, expectation: expectation) else {
            return RecordingValidation.unreadable("no readable video track in \(url.lastPathComponent)")
        }
        return RecordingValidation.evaluate(measurement, against: expectation)
    }

    /// The file's measured values, or nil when it has no readable video track.
    public static func measure(_ url: URL, expectation: RecordingExpectation = RecordingExpectation()) async -> RecordingMeasurement? {
        guard let info = await RecordedVideoInspector.inspect(url) else { return nil }
        let asset = AVURLAsset(url: url)
        var m = RecordingMeasurement(codec: info.codec, width: info.width, height: info.height,
                                     presentationTicks: info.presentationTicks, durationSeconds: info.durationSeconds,
                                     audioTrackCount: info.audioTrackCount, audioSampleRate: info.audioSampleRate,
                                     audioChannels: info.audioChannelCount)
        m.metadataIdentifiers = await metadataIdentifiers(asset)
        if let audio = try? await asset.loadTracks(withMediaType: .audio).first {
            let scan = decodeAudio(asset, track: audio)
            m.audioSampleCount = scan.samples
            m.audioBreaks = scan.breaks
            m.clickSeconds = scan.click
        }
        if expectation.checksSyncMarker {
            m.flashSeconds = await flashTime(asset)
        } else {
            m.clickSeconds = nil
        }
        return m
    }

    /// REC-004's marker pair: the first bright frame and the first loud audio sample (seconds).
    public static func markerTimes(_ url: URL) async -> (flash: Double?, click: Double?) {
        let asset = AVURLAsset(url: url)
        let flash = await flashTime(asset)
        guard let audio = try? await asset.loadTracks(withMediaType: .audio).first else { return (flash, nil) }
        return (flash, decodeAudio(asset, track: audio).click)
    }

    // MARK: - Reading

    private static func metadataIdentifiers(_ asset: AVURLAsset) async -> [String] {
        var items = (try? await asset.load(.metadata)) ?? []
        if let tracks = try? await asset.load(.tracks) {
            for track in tracks { items += (try? await track.load(.metadata)) ?? [] }
        }
        // "uiso/loci common/location": the identifier and, when it has one, the common key (an MP4 writes a
        // QuickTime location item as `uiso/loci`, whose common key is `location`).
        return items.map { (item: AVMetadataItem) -> String in
            let id = item.identifier?.rawValue ?? "unknown"
            guard let common = item.commonKey?.rawValue else { return id }
            return "\(id) common/\(common)"
        }
    }

    /// Decodes the video to 32BGRA until the first frame whose centre is bright.
    private static func flashTime(_ asset: AVURLAsset) async -> Double? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        while let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            if centreGreen(pixels) > flashThreshold { return CMSampleBufferGetPresentationTimeStamp(sample).seconds }
        }
        return nil
    }

    private static func centreGreen(_ pixels: CVPixelBuffer) -> UInt8 {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return 0 }
        let row = CVPixelBufferGetBytesPerRow(pixels)
        let offset = (CVPixelBufferGetHeight(pixels) / 2) * row + (CVPixelBufferGetWidth(pixels) / 2) * 4 + 1
        return base.assumingMemoryBound(to: UInt8.self)[offset]
    }

    private struct AudioScan {
        var samples = 0
        var breaks = 0
        var click: Double?
    }

    /// Decodes the audio to Float32 interleaved LPCM at its own rate and channel count: total frames,
    /// breaks between buffers (a start more than 1 sample from the previous end) and the first loud sample.
    private static func decodeAudio(_ asset: AVURLAsset, track: AVAssetTrack) -> AudioScan {
        var scan = AudioScan()
        guard let reader = try? AVAssetReader(asset: asset) else { return scan }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
                                       AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
                                       AVLinearPCMIsBigEndianKey: false]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return scan }
        reader.add(output)
        guard reader.startReading() else { return scan }
        var expectedStart: Double?
        while let sample = output.copyNextSampleBuffer() {
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0, let block = CMSampleBufferGetDataBuffer(sample),
                  let format = CMSampleBufferGetFormatDescription(sample),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { continue }
            let rate = asbd.mSampleRate
            let channels = max(Int(asbd.mChannelsPerFrame), 1)
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if let expected = expectedStart, abs(start - expected) * rate > 1.0 { scan.breaks += 1 }
            expectedStart = start + Double(frames) / rate
            scan.samples += frames
            if scan.click == nil, let index = firstLoudFrame(block, frames: frames, channels: channels) {
                scan.click = start + Double(index) / rate
            }
        }
        if reader.status != .completed { scan.breaks += 1 }
        return scan
    }

    private static func firstLoudFrame(_ block: CMBlockBuffer, frames: Int, channels: Int) -> Int? {
        var floats = [Float](repeating: 0, count: frames * channels)
        let bytes = min(CMBlockBufferGetDataLength(block), floats.count * MemoryLayout<Float>.size)
        let status = floats.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> OSStatus in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: raw.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { return nil }
        for frame in 0..<frames where abs(floats[frame * channels]) > clickThreshold { return frame }
        return nil
    }
}
#endif
