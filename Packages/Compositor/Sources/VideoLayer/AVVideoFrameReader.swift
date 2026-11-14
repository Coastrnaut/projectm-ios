// AVVideoFrameReader.swift — reads a stored copy's pictures as Metal textures (MED-002-R12, R15;
// research MED-002-D1, D2).
//
// A `VideoFrameReading` for the decode thread: an `AVAssetReader` with one track output asking for
// 32BGRA (the system converts the video's Y′CbCr, video or full range, to R′G′B′), started at the
// requested time; each picture is wrapped without a copy by a `CVMetalTextureCache` as
// `.bgra8Unorm_srgb`, so the shader's sample is linear light. Timestamps are made relative to the
// track's start. The asset's track facts are loaded once (async API, bridged on the decode thread,
// never the main thread). Nothing but the facts in `VideoTrackInfo` is read. Before every open (start,
// loop, seek) the container is checked again (`VideoContainerCheck`, MED-014-R12), so a stored copy
// damaged or replaced while playing fails as `.damaged` at the next open instead of reaching
// AVFoundation.
// MED-003 (research MED-003-D3): an open may end at a time (`timeRange = [start, end)`), and
// `prepare` creates and starts one standby `AVAssetReader` for the next open, which AVFoundation
// starts decoding at once; the next open with the same start and end takes it over instead of
// building a new one (the container check still runs first). At most one standby exists; any other
// open, `close` at the end of the session, or deinit drops it.
#if canImport(AVFoundation) && canImport(Metal) && !COMPOSITOR_NO_METAL
import AVFoundation
import CameraLayer
import CoreMedia
import CoreVideo
import Foundation
import Metal

/// One decoded picture: the texture and the Core Video object that keeps its pixels alive (with the
/// reader's cache, which the picture may outlive: `CVMetalTextureHold`).
public struct VideoTextureFrame: @unchecked Sendable {
    public let texture: MTLTexture
    let wrapper: CVMetalTextureHold
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
    /// MED-003: the prepared next pass (start, end, reader, output).
    private var standby: (start: Int64, end: Int64?, reader: AVAssetReader, output: AVAssetReaderTrackOutput)?
    /// MED-003: opens served by the standby reader (diagnostics, tests).
    public private(set) var standbyHits = 0

    /// Runs on the decode thread (the pipeline's `makeReader`).
    public init(url: URL, device: MTLDevice) {
        self.url = url
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.cache = cache
    }

    deinit {
        close()
        dropStandby()
    }

    public func open(startNanoseconds: Int64) throws(VideoImportError) -> VideoTrackInfo {
        try open(startNanoseconds: startNanoseconds, endNanoseconds: nil)
    }

    public func open(startNanoseconds: Int64, endNanoseconds: Int64?) throws(VideoImportError) -> VideoTrackInfo {
        close()
        guard cache != nil else { dropStandby(); throw .damaged }
        try VideoContainerCheck.check(url, limits: .standard)
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
        if let ready = standby, ready.start == startNanoseconds, ready.end == endNanoseconds, ready.reader.status == .reading {
            standby = nil
            reader = ready.reader
            output = ready.output
            standbyHits += 1
            return loaded.info
        }
        dropStandby()
        let (reader, output) = try Self.makeReader(asset: asset, track: loaded.track, trackStart: loaded.start,
                                                   start: startNanoseconds, end: endNanoseconds)
        self.reader = reader
        self.output = output
        return loaded.info
    }

    /// MED-003 pre-roll: starts the reader for the next open now (one at a time; failures ignored).
    public func prepare(startNanoseconds: Int64, endNanoseconds: Int64?) {
        guard let asset, let loaded else { return }
        if let ready = standby, ready.start == startNanoseconds, ready.end == endNanoseconds { return }
        dropStandby()
        guard let (reader, output) = try? Self.makeReader(asset: asset, track: loaded.track, trackStart: loaded.start,
                                                          start: startNanoseconds, end: endNanoseconds) else { return }
        standby = (startNanoseconds, endNanoseconds, reader, output)
    }

    private func dropStandby() {
        standby?.reader.cancelReading()
        standby = nil
    }

    private static func makeReader(asset: AVURLAsset, track: AVAssetTrack, trackStart: CMTime, start: Int64,
                                   end: Int64?) throws(VideoImportError) -> (AVAssetReader, AVAssetReaderTrackOutput) {
        guard let reader = try? AVAssetReader(asset: asset) else { throw .damaged }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: AVVideoFrameReaderSettings.output)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw .damaged }
        reader.add(output)
        let startTime = CMTimeAdd(trackStart, CMTime(value: max(start, 0), timescale: 1_000_000_000))
        let duration: CMTime
        if let end, end > start {
            duration = CMTime(value: end - max(start, 0), timescale: 1_000_000_000)
        } else {
            duration = .positiveInfinity
        }
        reader.timeRange = CMTimeRange(start: startTime, duration: duration)
        guard reader.startReading() else { throw .damaged }
        return (reader, output)
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
            let hold = CVMetalTextureHold(texture: wrapper, cache: cache)
            return (VideoProbe.nanoseconds(time), VideoTextureFrame(texture: texture, wrapper: hold, rotation: loaded.info.rotation))
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
