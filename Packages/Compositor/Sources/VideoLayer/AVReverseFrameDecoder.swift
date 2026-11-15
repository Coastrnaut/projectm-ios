// AVReverseFrameDecoder.swift — reads a stored copy once for the reverse cache (MED-005-R2, R3; research MED-005-D2).
//
// A `VideoReverseDecoding` for the build thread: the MED-014 container check first (a damaged or replaced copy fails as
// undecodable before AVFoundation sees it), the MED-002 probe's track facts, then one `AVAssetReader` over the whole
// video track asking for 32BGRA (the playback settings, so colours match forward playback). Each accepted picture is
// downsampled on the CPU (nearest sample at the centre of each output pixel) into a reused scratch buffer and copied
// into a new shared `.bgra8Unorm_srgb` texture of the plan's size; the decoded pixel buffer is released at once.
// Pictures the builder does not accept (above 30 a second) are skipped without conversion. Any reader failure is
// `.undecodable`. Runs only on the build thread; never on the render path.
#if canImport(AVFoundation) && canImport(Metal) && !COMPOSITOR_NO_METAL
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Metal

public final class AVReverseFrameDecoder: VideoReverseDecoding {
    public typealias Picture = MTLTexture

    private let url: URL
    private let device: MTLDevice
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var trackStart: CMTime = .zero
    private var scratch: [UInt8] = []

    public init(url: URL, device: MTLDevice) {
        self.url = url
        self.device = device
    }

    deinit { reader?.cancelReading() }

    public func open() throws(VideoReverseUnsupported) -> VideoTrackInfo {
        do {
            _ = try VideoContainerCheck.check(url, limits: .standard)
        } catch {
            throw .undecodable
        }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let loaded = ReverseLoadBox.blocking(asset)
        guard let (track, info, range) = loaded else { throw .undecodable }
        guard let reader = try? AVAssetReader(asset: asset) else { throw .undecodable }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: AVVideoFrameReaderSettings.output)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw .undecodable }
        reader.add(output)
        reader.timeRange = range
        guard reader.startReading() else { throw .undecodable }
        self.reader = reader
        self.output = output
        trackStart = range.start
        return info
    }

    public func next(width: Int, height: Int, accept: (Int64) -> Bool) throws(VideoReverseUnsupported) -> (pts: Int64, picture: MTLTexture?)? {
        guard let reader, let output else { return nil }
        while true {
            guard let sample = output.copyNextSampleBuffer() else {
                if reader.status == .failed { throw .undecodable }
                return nil
            }
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }   // e.g. an empty edit
            let pts: Int64 = VideoProbe.nanoseconds(CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sample), trackStart))
            guard accept(pts) else { return (pts, nil) }
            return (pts, try texture(from: pixels, width: width, height: height))
        }
    }

    /// Nearest-sample downsampling of a 32BGRA buffer into a new `width` × `height` sRGB texture.
    private func texture(from pixels: CVPixelBuffer, width: Int, height: Int) throws(VideoReverseUnsupported) -> MTLTexture {
        guard CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA else { throw .undecodable }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { throw .undecodable }
        let sourceWidth: Int = CVPixelBufferGetWidth(pixels), sourceHeight: Int = CVPixelBufferGetHeight(pixels)
        let rowBytes: Int = CVPixelBufferGetBytesPerRow(pixels)
        guard sourceWidth > 0, sourceHeight > 0, width > 0, height > 0 else { throw .undecodable }
        let count: Int = width * height * 4
        if scratch.count != count { scratch = [UInt8](repeating: 0, count: count) }
        let source = base.assumingMemoryBound(to: UInt8.self)
        scratch.withUnsafeMutableBufferPointer { (out: inout UnsafeMutableBufferPointer<UInt8>) -> Void in
            for y in 0..<height {
                let sy: Int = min((2 * y + 1) * sourceHeight / (2 * height), sourceHeight - 1)
                let row = source + sy * rowBytes
                for x in 0..<width {
                    let sx: Int = min((2 * x + 1) * sourceWidth / (2 * width), sourceWidth - 1)
                    let p = row + sx * 4
                    let o: Int = (y * width + x) * 4
                    out[o] = p[0]; out[o + 1] = p[1]; out[o + 2] = p[2]; out[o + 3] = 255
                }
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height,
                                                                  mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw .undecodable }
        scratch.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Void in
            guard let address = bytes.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: address, bytesPerRow: width * 4)
        }
        return texture
    }
}

/// Runs the probe's async track load to completion on the (non-main, non-cooperative) build thread.
private final class ReverseLoadBox: @unchecked Sendable {
    var value: (AVAssetTrack, VideoTrackInfo, CMTimeRange)?

    static func blocking(_ asset: AVURLAsset) -> (AVAssetTrack, VideoTrackInfo, CMTimeRange)? {
        let box = ReverseLoadBox()
        let done = DispatchSemaphore(value: 0)
        let sendable = ReverseAssetBox(asset: asset)
        Task.detached(priority: .utility) {
            box.value = try? await VideoProbe.load(sendable.asset)
            done.signal()
        }
        done.wait()
        return box.value
    }
}

/// `AVURLAsset` handed to the load task and back (the build thread waits for it; never shared).
private struct ReverseAssetBox: @unchecked Sendable {
    let asset: AVURLAsset
}
#endif
