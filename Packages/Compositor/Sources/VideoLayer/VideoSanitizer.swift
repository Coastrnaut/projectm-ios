// VideoSanitizer.swift — the stored copy of a picked video: its video pictures and timing only
// (MED-002-R3, R4, R16; research MED-002-D6; spec Clarifications).
//
// The picked file is checked (`VideoProbe`), then its first video track is inserted into an empty
// `AVMutableComposition` (the composition carries none of the source's asset or track metadata and
// no soundtrack), its rotation copied, and the composition exported with the passthrough preset, so
// no picture is re-compressed. The export gets no metadata (`metadata = []`) and the sharing filter.
// FILE-008: the copy's movie-header times are then zeroed (MovieHeaderTimes). The copy is probed again; any failure removes it and throws `.saveFailed` (or the probe's reason).
#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import Foundation

public enum VideoSanitizer {
    /// Writes the sanitized copy of `source` to `destination` (a new `.mov` path) and returns its facts.
    public static func copy(_ source: URL, to destination: URL, limits: VideoImportLimits) async throws(VideoImportError) -> VideoTrackInfo {
        _ = try await VideoProbe.check(source, limits: limits)
        let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let (track, _, range) = try await VideoProbe.load(asset)
        let transform: CGAffineTransform
        do {
            transform = try await track.load(.preferredTransform)
        } catch {
            throw .damaged
        }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw .saveFailed
        }
        do {
            try video.insertTimeRange(range, of: track, at: .zero)
        } catch {
            throw .damaged
        }
        video.preferredTransform = transform
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw .saveFailed }
        export.metadata = []
        export.metadataItemFilter = .forSharing()
        export.shouldOptimizeForNetworkUse = false
        try? FileManager.default.removeItem(at: destination)
        do {
            try await export.export(to: destination, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw .saveFailed
        }
        // FILE-008-R6: zero the header times so equal sources give equal copies (content-hash dedup).
        do {
            try MovieHeaderTimes.zero(fileAt: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw .saveFailed
        }
        do throws(VideoImportError) {
            return try await VideoProbe.check(destination, limits: limits)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw .saveFailed
        }
    }
}
#endif
