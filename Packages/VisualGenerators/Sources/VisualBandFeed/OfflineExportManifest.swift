// OfflineExportManifest.swift — REC-013 the checksum sidecar (specs/240-rec-013-deterministic-offline-export; R6, R7;
// data-model.md; research REC-013-D4). Foundation only; builds on Linux.
//
// Written next to the export's MP4 as `<name>.checksums.json` (sorted keys, pretty printed). Two exports are
// compared by `frameChecksums` (one lowercase hex SHA-256 per frame of the rendered BGRA before encoding); `gpu`
// says whether the comparison applies (same GPU class).
import Foundation

public struct OfflineExportManifest: Codable, Sendable, Equatable {
    public struct Glow: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var intensity: Double
        public var radius: Double
        public var threshold: Double

        public init(enabled: Bool, intensity: Double, radius: Double, threshold: Double) {
            self.enabled = enabled
            self.intensity = intensity
            self.radius = radius
            self.threshold = threshold
        }
    }

    public static let currentFormatVersion = 1

    public var formatVersion: Int = OfflineExportManifest.currentFormatVersion
    public var visual: String
    public var options: String
    public var glow: Glow
    public var reduceFlashing: Bool
    public var safetyProfile: String
    public var width: Int
    public var height: Int
    public var fps: Int
    public var seed: UInt32
    /// "fixture" or the audio file's name.
    public var audioSource: String
    public var audioSHA256: String
    /// Stereo frames at 44.1 kHz used by the export.
    public var audioFrames: Int
    public var gpu: String
    public var osVersion: String
    public var appVersion: String
    public var frameCount: Int
    public var frameChecksums: [String]

    public init(visual: String, options: String, glow: Glow, reduceFlashing: Bool, safetyProfile: String, width: Int, height: Int,
                fps: Int, seed: UInt32, audioSource: String, audioSHA256: String, audioFrames: Int, gpu: String,
                osVersion: String, appVersion: String, frameChecksums: [String]) {
        self.visual = visual
        self.options = options
        self.glow = glow
        self.reduceFlashing = reduceFlashing
        self.safetyProfile = safetyProfile
        self.width = width
        self.height = height
        self.fps = fps
        self.seed = seed
        self.audioSource = audioSource
        self.audioSHA256 = audioSHA256
        self.audioFrames = audioFrames
        self.gpu = gpu
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.frameCount = frameChecksums.count
        self.frameChecksums = frameChecksums
    }

    /// True when both exports rendered the same frames (same count, same checksums in order).
    public func sameFrames(as other: OfflineExportManifest) -> Bool {
        frameCount == other.frameCount && frameChecksums == other.frameChecksums
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> OfflineExportManifest {
        try JSONDecoder().decode(OfflineExportManifest.self, from: data)
    }

    /// Lowercase hex of `bytes`.
    public static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        let digits: [Character] = Array("0123456789abcdef")
        var out = ""
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return out
    }
}
