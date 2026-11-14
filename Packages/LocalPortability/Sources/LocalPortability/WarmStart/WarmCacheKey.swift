// WarmCacheKey.swift — PERF-009 (specs/229-perf-009-startup-warm-cache, contracts/warm-cache.md): the identity
// of a warm-start cache entry. An entry made by another app version or build, on another OS version or GPU, in
// another format, or from other input bytes is stale and never used (PERF-009-R2, R3; research PERF-009-D2).
import Foundation
#if canImport(CryptoKit) && !LOCALPORTABILITY_NO_CRYPTOKIT
import CryptoKit
#endif

public struct WarmCacheKey: Sendable, Equatable, Codable {
    /// The key fields in the order `firstMismatch` checks them.
    public enum Field: String, Sendable, Equatable, CaseIterable, Codable {
        case appVersion, build, osVersion, gpuFamily, formatVersion, contentHash
    }

    /// `gpuFamily` of an entry that does not depend on the GPU (the preset library).
    public static let noGPU = "none"

    public var appVersion: String
    public var build: String
    public var osVersion: String
    public var gpuFamily: String
    public var formatVersion: Int
    /// 64 lowercase hex characters: SHA-256 of the entry's inputs.
    public var contentHash: String

    public init(appVersion: String, build: String, osVersion: String, gpuFamily: String, formatVersion: Int, contentHash: String) {
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.gpuFamily = gpuFamily
        self.formatVersion = formatVersion
        self.contentHash = contentHash
    }

    /// The first field that differs from `other`, or nil when the keys are equal.
    public func firstMismatch(_ other: WarmCacheKey) -> Field? {
        if appVersion != other.appVersion { return .appVersion }
        if build != other.build { return .build }
        if osVersion != other.osVersion { return .osVersion }
        if gpuFamily != other.gpuFamily { return .gpuFamily }
        if formatVersion != other.formatVersion { return .formatVersion }
        if contentHash != other.contentHash { return .contentHash }
        return nil
    }
}

/// The app and system part of every key (no user or device identifiers; PERF-009-R1).
public struct WarmStartIdentity: Sendable, Equatable {
    public var appVersion: String
    public var build: String
    public var osVersion: String

    public init(appVersion: String, build: String, osVersion: String) {
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
    }

    /// From a bundle's Info.plist values and the running OS's version string.
    public init(infoDictionary: [String: Any]?, osVersion: String) {
        appVersion = infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        build = infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        self.osVersion = osVersion
    }

    public func key(gpuFamily: String, formatVersion: Int, contentHash: String) -> WarmCacheKey {
        WarmCacheKey(appVersion: appVersion, build: build, osVersion: osVersion, gpuFamily: gpuFamily,
                     formatVersion: formatVersion, contentHash: contentHash)
    }
}

/// SHA-256 of byte sequences, hardware-backed CryptoKit on Apple platforms and `PortableSHA256` elsewhere (same
/// lowercase hex digest; research PERF-009-D3).
public enum WarmCacheHash {
    /// The digest of `parts` concatenated in order.
    public static func sha256Hex(_ parts: [Data]) -> String {
        #if canImport(CryptoKit) && !LOCALPORTABILITY_NO_CRYPTOKIT
        var hasher = SHA256()
        for part in parts { hasher.update(data: part) }
        let digits: [UInt8] = Array("0123456789abcdef".utf8)
        var hex: [UInt8] = []
        hex.reserveCapacity(64)
        for byte in hasher.finalize() {
            hex.append(digits[Int(byte >> 4)])
            hex.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: hex, as: UTF8.self)
        #else
        var hasher = PortableSHA256.Hasher()
        for part in parts { hasher.update(part) }
        return hasher.finalize()
        #endif
    }

    public static func sha256Hex(_ data: Data) -> String { sha256Hex([data]) }

    /// The digest of UTF-8 texts, each followed by a zero byte so ["ab", "c"] and ["a", "bc"] differ.
    public static func sha256Hex(texts: [String]) -> String {
        sha256Hex(texts.map { (text: String) -> Data in Data(text.utf8) + Data([0]) })
    }
}
