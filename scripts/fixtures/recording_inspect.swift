// recording_inspect.swift — QA-011 Batch 6: reads a recording (or a still) pulled off a device, for
// scripts/recording_frame_check.py. Compiled once with `swiftc -O` into Build/tools/recording_inspect. Every command
// prints one JSON object on stdout; the checks themselves (thresholds, onsets, correlation, atoms) are in Python.
//
//   info <file>                       duration, the video track (codec FourCC, size, frames, nominal fps), the audio track
//   ocr <file> <t,t,…>                Vision text recognition (accurate) of the frames at those times
//   grid <file> <t> <cols> <rows>     block-mean luma (0…255) of the frame at t, row-major
//   luma <file>                       every decoded frame's presentation time and mean luma (0…1)
//   envelope <file> <binMs>           the audio track's peak |sample| per bin (mono mix, 0…1) and the first sample's time
//   frame <file> <t> <out.png>        the frame at t as a PNG (for the report)
//
// Mac only (AVFoundation, Vision, ImageIO). Never reads anything but the given file.
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

func emit(_ object: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func fail(_ message: String) -> Never {
    emit(["error": message])
    exit(1)
}

func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xff) }
    return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
}

func videoTrack(_ asset: AVURLAsset) async -> AVAssetTrack? {
    try? await asset.loadTracks(withMediaType: .video).first
}

func image(_ asset: AVURLAsset, at seconds: Double) async -> CGImage? {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = true
    return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
}

/// Grey values of `cg` drawn into a `width` × `height` bitmap (area-averaged by Core Graphics' high-quality scaling).
func grey(_ cg: CGImage, width: Int, height: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: width * height)
    data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Void in
        guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return data
}

func info(_ url: URL) async {
    let asset = AVURLAsset(url: url)
    let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? -1
    var result: [String: Any] = ["duration": duration]
    if let track = await videoTrack(asset) {
        var video: [String: Any] = [:]
        if let size = try? await track.load(.naturalSize) { video["width"] = Int(size.width); video["height"] = Int(size.height) }
        if let rate = try? await track.load(.nominalFrameRate) { video["fps"] = Double(rate) }
        if let formats = try? await track.load(.formatDescriptions), let first = formats.first {
            video["codec"] = fourCC(CMFormatDescriptionGetMediaSubType(first))
        }
        // Frames: count the compressed samples (no decoding).
        if let reader = try? AVAssetReader(asset: asset) {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            reader.add(output)
            var frames = 0
            var first: Double?
            if reader.startReading() {
                while let sample = output.copyNextSampleBuffer() {
                    if CMSampleBufferGetNumSamples(sample) > 0 {
                        frames += 1
                        if first == nil { first = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) }
                    }
                }
            }
            video["frames"] = frames
            video["firstPTS"] = first ?? -1
        }
        result["video"] = video
    }
    if let track = try? await asset.loadTracks(withMediaType: .audio).first {
        var audio: [String: Any] = [:]
        if let formats = try? await track.load(.formatDescriptions), let first = formats.first {
            audio["codec"] = fourCC(CMFormatDescriptionGetMediaSubType(first))
            if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(first)?.pointee {
                audio["channels"] = Int(basic.mChannelsPerFrame)
                audio["sampleRate"] = basic.mSampleRate
            }
        }
        result["audio"] = audio
    }
    emit(result)
}

func ocr(_ url: URL, times: [Double]) async {
    let asset = AVURLAsset(url: url)
    var frames: [[String: Any]] = []
    for t in times {
        guard let cg = await image(asset, at: t) else {
            frames.append(["t": t, "error": "no frame"])
            continue
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        let texts: [String] = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        frames.append(["t": t, "texts": texts])
    }
    emit(["frames": frames])
}

func grid(_ url: URL, at t: Double, cols: Int, rows: Int) async {
    let asset = AVURLAsset(url: url)
    guard let cg = await image(asset, at: t) else { fail("no frame at \(t)") }
    emit(["t": t, "cols": cols, "rows": rows, "width": cg.width, "height": cg.height,
          "values": grey(cg, width: cols, height: rows).map(Int.init)])
}

func luma(_ url: URL) async {
    let asset = AVURLAsset(url: url)
    guard let track = await videoTrack(asset), let reader = try? AVAssetReader(asset: asset) else { fail("no video track") }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { fail("cannot read: \(String(describing: reader.error))") }
    var samples: [[Double]] = []
    while let sample = output.copyNextSampleBuffer() {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { continue }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0, n = 0
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                let p = bytes + y * row + x * 4   // BGRA
                sum += 0.0722 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.2126 * Double(p[2])
                n += 1
            }
        }
        samples.append([t, n > 0 ? sum / Double(n) / 255 : 0])
    }
    emit(["frames": samples])
}

func envelope(_ url: URL, binMs: Double) async {
    let asset = AVURLAsset(url: url)
    guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
          let reader = try? AVAssetReader(asset: asset) else { fail("no audio track") }
    let rate = 48_000.0
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: rate,
        AVNumberOfChannelsKey: 1])
    reader.add(output)
    guard reader.startReading() else { fail("cannot read audio: \(String(describing: reader.error))") }
    let perBin = max(1, Int(rate * binMs / 1000))
    var peaks: [Double] = []
    var current = 0.0, inBin = 0
    var start: Double?
    while let sample = output.copyNextSampleBuffer() {
        if start == nil { start = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) }
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                          dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer else { continue }
        let count = length / MemoryLayout<Float>.size
        pointer.withMemoryRebound(to: Float.self, capacity: count) { (floats: UnsafeMutablePointer<Float>) -> Void in
            for i in 0..<count {
                current = max(current, Double(abs(floats[i])))
                inBin += 1
                if inBin == perBin { peaks.append((current * 10_000).rounded() / 10_000); current = 0; inBin = 0 }
            }
        }
    }
    emit(["binMs": binMs, "start": start ?? 0, "peaks": peaks])
}

func frame(_ url: URL, at t: Double, out: URL) async {
    let asset = AVURLAsset(url: url)
    guard let cg = await image(asset, at: t),
          let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("no frame at \(t)")
    }
    CGImageDestinationAddImage(destination, cg, nil)
    emit(["written": CGImageDestinationFinalize(destination), "path": out.path])
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail("usage: recording_inspect info|ocr|grid|luma|envelope|frame <file> …") }
let url = URL(fileURLWithPath: arguments[2])
func number(_ i: Int) -> Double {
    guard i < arguments.count, let value = Double(arguments[i]) else { fail("argument \(i) is not a number") }
    return value
}
switch arguments[1] {
case "info": await info(url)
case "ocr":
    let times = arguments.count > 3 ? arguments[3].split(separator: ",").compactMap { Double($0) } : [0.5]
    await ocr(url, times: times)
case "grid": await grid(url, at: number(3), cols: Int(number(4)), rows: Int(number(5)))
case "luma": await luma(url)
case "envelope": await envelope(url, binMs: arguments.count > 3 ? number(3) : 1)
case "frame":
    guard arguments.count > 4 else { fail("frame <file> <t> <out.png>") }
    await frame(url, at: number(3), out: URL(fileURLWithPath: arguments[4]))
default: fail("unknown command \(arguments[1])")
}
