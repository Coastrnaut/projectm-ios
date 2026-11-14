// RecordingLibraryInspector.swift — REC-010 (contract C3; research REC-010-D4, D5): a saved recording's facts from a
// quick header read and its thumbnail, both off the main actor.
//
// * Facts: duration, the first video track's size, nominal frame rate and codec. No video track, no duration or a
//   failed load → nil (the row is "Incomplete"). Unlike REC-003's `RecordedVideoInspector` (every sample) and
//   QA-008's validator (decodes audio), nothing is read beyond the header.
// * Thumbnail: the frame at min(1 s, duration / 2), at most 240 px, cached in memory and as a JPEG in
//   `Caches/RecordingThumbnails/<name>.<bytes>.jpg` (regenerable, so FILE-010 Clear Caches may remove it).
import AVFoundation
import CoreMedia
import Foundation
import UIKit

/// What a row shows for a readable recording (data model: RecordingFacts).
struct RecordingFacts: Sendable, Equatable {
    let durationSeconds: Double
    let width: Int
    let height: Int
    let framesPerSecond: Double
    /// The sample description's four-character code ("hvc1", "avc1").
    let codec: String

    /// "1:05" (minutes and seconds).
    var durationText: String {
        let total = Int(durationSeconds.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    var resolutionText: String { "\(width)×\(height)" }

    var frameRateText: String { "\(Int(framesPerSecond.rounded())) fps" }

    /// "HEVC", "H.264" or the code itself.
    var codecText: String {
        switch codec {
        case "hvc1", "hev1": "HEVC"
        case "avc1", "avc3": "H.264"
        default: codec.trimmingCharacters(in: .whitespaces)
        }
    }
}

actor RecordingLibraryInspector {
    static let thumbnailFolderName = "RecordingThumbnails"
    static let thumbnailMaxSide: CGFloat = 240

    nonisolated let thumbnailDirectory: URL
    private var memory: [String: Data] = [:]
    /// Thumbnails made by decoding (tests: a cached request does not add one).
    private(set) var generatedCount = 0

    init(thumbnailDirectory: URL) {
        self.thumbnailDirectory = thumbnailDirectory
    }

    static var defaultThumbnailDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches", isDirectory: true)
        return caches.appendingPathComponent(thumbnailFolderName, isDirectory: true)
    }

    /// The header facts, or nil when the file cannot be read as a video.
    nonisolated static func facts(of url: URL) async -> RecordingFacts? {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first,
              let duration = try? await asset.load(.duration), duration.isValid, duration.seconds > 0,
              let (size, rate, descriptions) = try? await track.load(.naturalSize, .nominalFrameRate, .formatDescriptions)
        else { return nil }
        let codec: String = descriptions.first.map { (d: CMFormatDescription) -> String in
            fourCC(CMFormatDescriptionGetMediaSubType(d))
        } ?? "?"
        return RecordingFacts(durationSeconds: duration.seconds, width: Int(size.width.rounded()), height: Int(size.height.rounded()),
                              framesPerSecond: Double(rate), codec: codec)
    }

    /// The thumbnail's JPEG bytes: memory, then the cache folder, then a decoded frame (stored in both).
    func thumbnail(for file: RecordingLibraryFile, durationSeconds: Double) async -> Data? {
        let key = file.cacheKey
        if let data = memory[key] { return data }
        let cached = cacheURL(for: key)
        if let data = try? Data(contentsOf: cached) {
            memory[key] = data
            return data
        }
        guard let data = await Self.makeThumbnail(file.url, durationSeconds: durationSeconds) else { return nil }
        generatedCount += 1
        memory[key] = data
        try? FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try? data.write(to: cached, options: .atomic)
        return data
    }

    /// Drops a file's entry from memory and the cache folder (delete, rename).
    func removeThumbnail(for file: RecordingLibraryFile) {
        memory[file.cacheKey] = nil
        try? FileManager.default.removeItem(at: cacheURL(for: file.cacheKey))
    }

    func hasCachedThumbnail(for file: RecordingLibraryFile) -> Bool {
        memory[file.cacheKey] != nil || FileManager.default.fileExists(atPath: cacheURL(for: file.cacheKey).path)
    }

    nonisolated func cacheURL(for key: String) -> URL {
        thumbnailDirectory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".jpg", isDirectory: false)
    }

    /// min(1 s, duration / 2).
    nonisolated static func thumbnailTime(durationSeconds: Double) -> Double { min(1, max(0, durationSeconds / 2)) }

    nonisolated static func makeThumbnail(_ url: URL, durationSeconds: Double) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbnailMaxSide, height: thumbnailMaxSide)
        let time = CMTime(seconds: thumbnailTime(durationSeconds: durationSeconds), preferredTimescale: 600)
        guard let (image, _) = try? await generator.image(at: time) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
    }

    nonisolated static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }
}
