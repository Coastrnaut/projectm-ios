// AudioContainer.swift — which audio container a file really is, decided from its leading bytes
// (AUD-002; specs/006-aud-002-support-common-audio-containers/contracts/audio-containers.md,
// research AUD-002-D3). Foundation only, all platforms.
//
// The system's audio parser is chosen by a file's extension, so a WAV named `.mp3` fails and a raw
// AAC stream named `.mp3` is read as the wrong kind of audio. The library therefore recognizes
// the content first and names its own copy accordingly.
//
// Untrusted input: recognition reads a bounded number of bytes, allocates nothing that depends on
// the file, and returns nil for anything it does not know.
import Foundation

/// The five containers the app guarantees (AUD-002-R1). Anything else is "other": nil.
public enum AudioContainer: String, Sendable, Equatable, CaseIterable {
    /// MPEG-1/2/2.5 Layer III frames, optionally after an ID3v2 tag.
    case mp3
    /// Raw AAC in ADTS frames, optionally after an ID3v2 tag.
    case aac
    /// An MPEG-4 file (`ftyp` box): M4A and its relatives.
    case mpeg4
    /// RIFF/WAVE.
    case wav
    /// AIFF or AIFF-C.
    case aiff

    /// The extension under which the system's decoder reads this container.
    public var fileExtension: String {
        switch self {
        case .mp3: return "mp3"
        case .aac: return "aac"
        case .mpeg4: return "m4a"
        case .wav: return "wav"
        case .aiff: return "aiff"
        }
    }

    /// The most bytes one recognition window looks at.
    public static let maxHeaderBytes = 8192

    /// Recognizes the container from the first bytes of a file. Looks at no more than
    /// `maxHeaderBytes`. An ID3v2 tag is skipped when the audio after it is inside `header`;
    /// if the tag is longer, the result is nil (`detect(at:)` follows the tag in the file).
    public static func detect(header: Data) -> AudioContainer? {
        let bytes = [UInt8](header.prefix(maxHeaderBytes))
        switch signature(bytes) {
        case .container(let container): return container
        case .id3(let length): return length < bytes.count ? stream(bytes, from: length) : nil
        case .none: return stream(bytes, from: 0)
        }
    }

    /// Recognizes the container of the file at `url` with at most two reads of `maxHeaderBytes`.
    /// Nil when the file cannot be read or is none of the five.
    public static func detect(at url: URL) -> AudioContainer? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let first = try? handle.read(upToCount: maxHeaderBytes), !first.isEmpty else { return nil }
        let bytes = [UInt8](first)
        switch signature(bytes) {
        case .container(let container):
            return container
        case .none:
            return stream(bytes, from: 0)
        case .id3(let length):
            if length < bytes.count, let found = stream(bytes, from: length) { return found }
            // The audio starts after the tag: one seek, one more window. The tag is never read.
            guard (try? handle.seek(toOffset: UInt64(length))) != nil,
                  let second = try? handle.read(upToCount: maxHeaderBytes), !second.isEmpty else { return nil }
            return stream([UInt8](second), from: 0)
        }
    }

    // MARK: - Signatures

    private enum Signature {
        case container(AudioContainer)
        /// An ID3v2 tag; the payload is the offset of the first byte after it.
        case id3(Int)
        case none
    }

    private static func matches(_ bytes: [UInt8], at offset: Int, _ text: String) -> Bool {
        let wanted = Array(text.utf8)
        guard offset >= 0, bytes.count >= offset + wanted.count else { return false }
        return !zip(bytes[offset..<offset + wanted.count], wanted).contains { $0 != $1 }
    }

    private static func signature(_ bytes: [UInt8]) -> Signature {
        if matches(bytes, at: 0, "RIFF"), matches(bytes, at: 8, "WAVE") { return .container(.wav) }
        if matches(bytes, at: 0, "FORM"), matches(bytes, at: 8, "AIFF") || matches(bytes, at: 8, "AIFC") { return .container(.aiff) }
        if matches(bytes, at: 4, "ftyp"), bytes.count >= 12 { return .container(.mpeg4) }
        if matches(bytes, at: 0, "ID3"), bytes.count >= 10 {
            // Four "syncsafe" size bytes (7 bits each), then an optional 10-byte footer (flag 0x10).
            let size = bytes[6...9]
            guard !size.contains(where: { $0 & 0x80 != 0 }) else { return .none }
            let length = size.reduce(0) { ($0 << 7) | Int($1) }
            return .id3(10 + length + (bytes[5] & 0x10 != 0 ? 10 : 0))
        }
        return .none
    }

    // MARK: - MPEG audio and ADTS frame headers

    /// The length in bytes of the frame whose header starts at `offset`, and what it is; nil when
    /// those four (MPEG audio) or seven (ADTS) bytes are not a valid header.
    private static func frame(_ bytes: [UInt8], at offset: Int) -> (container: AudioContainer, length: Int)? {
        guard offset >= 0, bytes.count >= offset + 4, bytes[offset] == 0xFF, bytes[offset + 1] & 0xE0 == 0xE0 else { return nil }
        let b1 = bytes[offset + 1]
        let b2 = bytes[offset + 2]
        let layer = (b1 >> 1) & 0x03
        if layer == 0 {
            // ADTS: 12 sync bits, a sample-rate index below 13, and a frame length of at least the header.
            guard b1 & 0xF0 == 0xF0, bytes.count >= offset + 7, (b2 >> 2) & 0x0F <= 12 else { return nil }
            let length = (Int(bytes[offset + 3] & 0x03) << 11) | (Int(bytes[offset + 4]) << 3) | Int(bytes[offset + 5] >> 5)
            return length >= 7 ? (.aac, length) : nil
        }
        guard layer == 1 else { return nil }                       // Layer III only; I and II are "other"
        let version = (b1 >> 3) & 0x03                            // 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5, 1 = reserved
        let bitRateIndex = Int(b2 >> 4)
        let rateIndex = Int((b2 >> 2) & 0x03)
        guard version != 1, (1...14).contains(bitRateIndex), rateIndex != 3 else { return nil }
        let mpeg1 = version == 3
        let kilobits = (mpeg1 ? [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
                              : [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160])[bitRateIndex - 1]
        let rate = [44_100, 48_000, 32_000][rateIndex] / (mpeg1 ? 1 : (version == 2 ? 2 : 4))
        let padding = Int((b2 >> 1) & 0x01)
        return (.mp3, (mpeg1 ? 144_000 : 72_000) * kilobits / rate + padding)
    }

    /// A frame stream starting at `start`: one valid header there is enough (a one-frame file is
    /// still that format). Otherwise the first place in the window where two consecutive frames of
    /// the same kind are found; a single header-like byte pair among other bytes is not a stream.
    private static func stream(_ bytes: [UInt8], from start: Int) -> AudioContainer? {
        guard start >= 0, start < bytes.count else { return nil }
        if let first = frame(bytes, at: start) { return first.container }
        var offset = start + 1
        while offset + 4 <= bytes.count {
            if bytes[offset] == 0xFF, let first = frame(bytes, at: offset),
               let second = frame(bytes, at: offset + first.length), second.container == first.container {
                return first.container
            }
            offset += 1
        }
        return nil
    }
}
