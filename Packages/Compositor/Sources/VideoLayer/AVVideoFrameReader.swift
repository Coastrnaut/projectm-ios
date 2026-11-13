// AVVideoFrameReader.swift — reads a stored copy's pictures as Metal textures (MED-002-R12, R15;
// research MED-002-D1, D2).
//
// A `VideoFrameReading` for the decode thread: an `AVAssetReader` with one track output asking for
// 32BGRA (the system converts the video's Y′CbCr, video or full range, to R′G′B′), started at the
// requested time; each picture is wrapped without a copy by a `CVMetalTextureCache` as
// `.bgra8Unorm_srgb`, so the shader's sample is linear light. Timestamps are made relative to the
// track's start. The asset's track facts are loaded once (async API, bridged on the decode thread,
// never the main thread). Nothing but the facts in `VideoTrackInfo` is read.
#if canImport(AVFoundation) && canImport(Metal) && !COMPOSITOR_NO_METAL
import AVFoundation
import CameraLayer
import CoreMedia
import CoreVideo
import Foundation
import Metal

/// One decoded picture: the texture and the Core Video object that keeps its pixels alive.
public struct VideoTextureFrame: @unchecked Sendable {
    public let texture: MTLTexture
    let wrapper: CVMetalTexture
    /// Quarter turns clockwise to upright (the track's transform).
    public let rotation: CameraRotation
}

public final class AVVideoFrameReader: VideoFrameReading {
    public typealias Frame = VideoTextureFrame

    private let url: URL
    private let cache: CVMetalTextureCache?
    private var loaded: (track: AVAssetTrack, info: VideoTrackInfo, start: CMTime)?
    private var asset: AVURLAsset?
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?

    /// Runs on the decode thread (the pipeline's `makeReader`).
    public init(url: URL, device: MTLDevice) {
        self.url = url
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.cache = cache
    }

    deinit { close() }

    public func open(startNanoseconds: Int64) throws(VideoImportError) -> VideoTrackInfo {
        close()
        guard cache != nil else { throw .damaged }
        let asset = self.asset ?? AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        self.asset = asset
        if loaded == nil {
            let result = Self.blocking { () async -> LoadedTrack in
                do throws(VideoImportError) {
                    return LoadedTrack(result: .success(try await VideoProbe.load(asset)))
                } catch {
                    return LoadedTrack(result: .failure(error))
                }
            }
            let (track, info, range) = try result.result.get()
            loaded = (track, info, range.start)
        }
        guard let loaded else { throw .damaged }
        guard let reader = try? AVAssetReader(asset: asset) else { throw .damaged }
        let output = AVAssetReaderTrackOutput(track: loaded.track, outputSettings: AVVideoFrameReaderSettings.output)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw .damaged }
        reader.add(output)
        let start = CMTimeAdd(loaded.start, CMTime(value: max(startNanoseconds, 0), timescale: 1_000_000_000))
        reader.timeRange = CMTimeRange(start: start, duration: .positiveInfinity)
        guard reader.startReading() else { throw .damaged }
        self.reader = reader
        self.output = output
        return loaded.info
    }

    public func next() throws(VideoImportError) -> (pts: Int64, frame: VideoTextureFrame)? {
        guard let reader, let output, let cache, let loaded else { return nil }
        while true {
            guard let sample = output.copyNextSampleBuffer() else {
                if reader.status == .failed { throw .damaged }
                return nil
            }
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }   // e.g. an empty edit
            let time = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sample), loaded.start)
            let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
            var wrapper: CVMetalTexture?
            guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixels, nil, .bgra8Unorm_srgb, width, height, 0,
                                                            &wrapper) == kCVReturnSuccess,
                  let wrapper, let texture = CVMetalTextureGetTexture(wrapper) else { throw .damaged }
            return (VideoProbe.nanoseconds(time), VideoTextureFrame(texture: texture, wrapper: wrapper, rotation: loaded.info.rotation))
        }
    }

    public func close() {
        reader?.cancelReading()
        reader = nil
        output = nil
        if let cache { CVMetalTextureCacheFlush(cache, 0) }
    }

    /// Runs an async load to completion on this (non-main, non-cooperative) decode thread.
    private static func blocking<T>(_ work: @escaping @Sendable () async -> T) -> T {
        let box = BlockingResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            box.value = await work()
            done.signal()
        }
        done.wait()
        return box.value!
    }
}

/// `AVAssetTrack` is not Sendable; it is created by the load task and then used only on the decode
/// thread, which waits for that task (a hand-over, never shared).
private struct LoadedTrack: @unchecked Sendable {
    let result: Result<(AVAssetTrack, VideoTrackInfo, CMTimeRange), VideoImportError>
}

/// Written once by the task before the semaphore is signalled, read after the wait.
private final class BlockingResultBox<T>: @unchecked Sendable {
    var value: T?
}
#endif
