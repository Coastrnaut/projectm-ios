// MED-002-T11: generated fixture videos (no media is checked in). `AVAssetWriter`, H.264 tagged
// BT.709, solid grey pictures whose level encodes their index modulo 30 (8 + 8 × (index % 30)), so a
// decoded picture names its index after the codec's rounding (grey has no chroma; ± 3 codes allowed).
// The exact global index over loops is the pure pipeline test's job (VideoPipelineTests).
// Options: a silent AAC soundtrack, location / creation date / device metadata, a 90° rotation.
#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum VideoFixtures {
    static let width = 64
    static let height = 48
    /// Location, date and device strings that must never reach a stored copy (MED-002-S5).
    static let location = "+48.8584+002.2945/"
    static let creationDate = "2019-05-04T03:02:01+0000"
    static let device = "FixtureCam9000"

    struct Options {
        var frames = 60
        var fps: Int32 = 30
        var audio = false
        var metadata = false
        var rotated = false
        var solid: (r: UInt8, g: UInt8, b: UInt8)?
    }

    /// Distinct grey levels (index modulo this).
    static let levels = 30

    /// The color of picture `index` (grey).
    static func color(_ index: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let v = UInt8(8 + 8 * (index % levels))
        return (v, v, v)
    }

    /// The index modulo `levels` a decoded grey level stands for (nil when it is not a fixture level).
    static func index(level: Int) -> Int? {
        let i = Int((Double(level - 8) / 8).rounded())
        guard (0..<levels).contains(i), abs(level - (8 + 8 * i)) <= 3 else { return nil }
        return i
    }

    static func write(to url: URL, _ options: Options = Options()) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000, AVVideoMaxKeyFrameIntervalKey: 15,
                                              AVVideoAllowFrameReorderingKey: false],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        ])
        video.expectsMediaDataInRealTime = false
        if options.rotated { video.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(video)
        var audio: AVAssetWriterInput?
        if options.audio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audio = input
        }
        if options.metadata { writer.metadata = metadataItems() }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        // The writer interleaves the tracks: while video is not taken, feed the soundtrack (silence).
        let audioTotal = audio == nil ? 0 : options.frames * 44_100 / Int(options.fps)
        var audioWritten = 0
        func feedAudio() throws -> Bool {
            guard let audio, audioWritten < audioTotal, audio.isReadyForMoreMediaData else { return false }
            let count = min(1024, audioTotal - audioWritten)
            guard let sample = silentAudio(frames: count, at: audioWritten), audio.append(sample) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
            audioWritten += count
            if audioWritten == audioTotal { audio.markAsFinished() }   // or the video waits for more sound
            return true
        }
        // A ceiling in 1 ms steps, not a cost: the iOS 27 simulator on CI stalled the encoder for more
        // than 5 s once (run 43551499825, "video 3 stalled") although it usually takes milliseconds.
        let stallLimit: Int = 20_000
        func stalled(_ what: String) -> NSError {
            NSError(domain: "VideoFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "\(what) stalled: audio \(audioWritten)/\(audioTotal), audio ready \(audio?.isReadyForMoreMediaData ?? false), writer \(writer.status.rawValue)"])
        }
        for i in 0..<options.frames {
            var waited = 0
            while !video.isReadyForMoreMediaData {
                if try feedAudio() { continue }
                if writer.status == .failed { throw writer.error ?? stalled("writer") }
                guard waited < stallLimit else { throw stalled("video \(i)") }
                usleep(1000)
                waited += 1
            }
            let c = options.solid ?? color(i)
            guard let buffer = makeBuffer(color: c) else { throw CocoaError(.fileWriteUnknown) }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: options.fps)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        video.markAsFinished()
        var waited = 0
        while audioWritten < audioTotal {
            if try feedAudio() { continue }
            if writer.status == .failed { throw writer.error ?? stalled("writer") }
            guard waited < stallLimit else { throw stalled("audio") }
            usleep(1000)
            waited += 1
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    private static func metadataItems() -> [AVMetadataItem] {
        func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            return item
        }
        return [item(.quickTimeMetadataLocationISO6709, location), item(.quickTimeMetadataCreationDate, creationDate),
                item(.quickTimeMetadataModel, device)]
    }

    /// Each frame gets its own buffer, not one from `adaptor.pixelBufferPool`: creating a buffer from the
    /// writer's pool crashed the test process with a null dictionary inside CoreVideo
    /// (`CVPixelBufferPool::createPixelBuffer`, SIGSEGV, 2026-11-14), intermittently, on the Mac host.
    private static func makeBuffer(color: (r: UInt8, g: UInt8, b: UInt8)) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<CVPixelBufferGetHeight(buffer) {
            for x in 0..<CVPixelBufferGetWidth(buffer) {
                let p = pixels + y * rowBytes + x * 4
                p[0] = color.b; p[1] = color.g; p[2] = color.r; p[3] = 255
            }
        }
        return buffer
    }

    private static func silentAudio(frames: Int, at start: Int) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                                               mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                             magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr, let format else { return nil }
        var block: CMBlockBuffer?
        let length = frames * 2
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: length,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr, let block else { return nil }
        guard CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) == noErr else { return nil }
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                                                   sampleCount: frames,
                                                                   presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 44_100),
                                                                   packetDescriptions: nil, sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }
}
#endif
