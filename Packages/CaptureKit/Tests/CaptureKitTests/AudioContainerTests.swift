// AudioContainerTests.swift — recognizing the five containers from leading bytes (AUD-002-T04;
// contracts/audio-containers.md). Pure bytes: no decoder, so this also runs where AVFAudio is absent.
import Foundation
import XCTest
@testable import CaptureKit

final class AudioContainerTests: XCTestCase {
    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    /// One ADTS frame header (AAC-LC, 44.1 kHz, stereo) followed by zero payload, `length` bytes in all.
    private func adtsFrame(length: Int = 64) -> [UInt8] {
        var frame = [UInt8](repeating: 0, count: length)
        frame[0] = 0xFF
        frame[1] = 0xF1                                   // sync, MPEG-4, layer 00, no CRC
        frame[2] = (1 << 6) | (4 << 2) | 0                // AAC-LC, 44.1 kHz, channel configuration 2 (high bit 0)
        frame[3] = (2 << 6) | UInt8((length >> 11) & 0x03)
        frame[4] = UInt8((length >> 3) & 0xFF)
        frame[5] = UInt8((length & 0x07) << 5) | 0x1F
        frame[6] = 0xFC
        return frame
    }

    private func id3(_ size: Int) -> [UInt8] {
        bytes("ID3") + [4, 0, 0, UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F), UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F)]
            + [UInt8](repeating: 0, count: size)
    }

    func testSignatures() {
        XCTAssertEqual(AudioContainer.detect(header: Data(bytes("RIFF") + [1, 2, 3, 4] + bytes("WAVEfmt "))), .wav)
        XCTAssertEqual(AudioContainer.detect(header: Data(bytes("FORM") + [0, 0, 1, 0] + bytes("AIFFCOMM"))), .aiff)
        XCTAssertEqual(AudioContainer.detect(header: Data(bytes("FORM") + [0, 0, 1, 0] + bytes("AIFCFVER"))), .aiff)
        XCTAssertEqual(AudioContainer.detect(header: Data([0, 0, 0, 0x1C] + bytes("ftypM4A ") + [0, 0, 0, 0])), .mpeg4)
        XCTAssertEqual(AudioContainer.detect(header: Data([0, 0, 0, 0x20] + bytes("ftypisom") + [0, 0, 2, 0])), .mpeg4)
        XCTAssertEqual(AudioContainer.detect(header: MP3Fixture.data(frameCount: 3)), .mp3)
        XCTAssertEqual(AudioContainer.detect(header: MP3Fixture.data(sampleRate: 48_000, lines: [10, 16], frameCount: 1)), .mp3,
                       "one frame at the start is enough")
        XCTAssertEqual(AudioContainer.detect(header: Data(adtsFrame() + adtsFrame())), .aac)
        XCTAssertEqual(AudioContainer.detect(header: Data(adtsFrame())), .aac)
    }

    func testExtensions() {
        XCTAssertEqual(AudioContainer.allCases.map(\.fileExtension), ["mp3", "aac", "m4a", "wav", "aiff"])
        XCTAssertEqual(AudioContainer.maxHeaderBytes, 8192)
    }

    func testID3TagIsSkipped() {
        XCTAssertEqual(AudioContainer.detect(header: Data(id3(300)) + MP3Fixture.data(frameCount: 2)), .mp3)
        XCTAssertEqual(AudioContainer.detect(header: Data(id3(300) + adtsFrame() + adtsFrame())), .aac)
        XCTAssertNil(AudioContainer.detect(header: Data(id3(300) + bytes("no audio after the tag, only text"))))
        XCTAssertNil(AudioContainer.detect(header: Data(id3(20_000))), "the tag is longer than the header: undecided from bytes alone")
        XCTAssertNil(AudioContainer.detect(header: Data(bytes("ID3") + [4, 0, 0, 0x80, 0, 0, 0])), "size bytes must be syncsafe")
    }

    func testStreamAfterLeadingBytesNeedsTwoConsistentHeaders() {
        let padding = [UInt8](repeating: 0, count: 417)
        XCTAssertEqual(AudioContainer.detect(header: Data(padding) + MP3Fixture.data(frameCount: 3)), .mp3)
        XCTAssertEqual(AudioContainer.detect(header: Data(padding + adtsFrame() + adtsFrame())), .aac)
        // A lone header-like pair in the middle of other bytes is not a stream.
        XCTAssertNil(AudioContainer.detect(header: Data(padding + [0xFF, 0xFB, 0x14, 0xC0] + [UInt8](repeating: 0x55, count: 600))))
        XCTAssertNil(AudioContainer.detect(header: Data(padding + adtsFrame(length: 64) + [UInt8](repeating: 0x55, count: 600))))
    }

    func testNotRecognized() {
        XCTAssertNil(AudioContainer.detect(header: Data()))
        XCTAssertNil(AudioContainer.detect(header: Data([0xFF, 0xFB, 0x14])), "3 bytes")
        XCTAssertNil(AudioContainer.detect(header: Data(bytes("this is not audio, it is a text file\n"))))
        XCTAssertNil(AudioContainer.detect(header: Data(bytes("RIFF") + [1, 2, 3, 4] + bytes("AVI LIST"))))
        XCTAssertNil(AudioContainer.detect(header: Data(bytes("FORM") + [0, 0, 1, 0] + bytes("8SVXVHDR"))))
        XCTAssertNil(AudioContainer.detect(header: Data([0xFF, 0xFD, 0x14, 0xC0] + [UInt8](repeating: 0, count: 60))), "Layer II")
        XCTAssertNil(AudioContainer.detect(header: Data([0xFF, 0xFF, 0x14, 0xC0] + [UInt8](repeating: 0, count: 60))), "Layer I")
        XCTAssertNil(AudioContainer.detect(header: Data([0xFF, 0xFB, 0xF4, 0xC0] + [UInt8](repeating: 0, count: 60))), "bit-rate index 15")
        XCTAssertNil(AudioContainer.detect(header: Data([0xFF, 0xFB, 0x04, 0xC0] + [UInt8](repeating: 0, count: 60))), "free bit rate")
        XCTAssertNil(AudioContainer.detect(header: Data([0xFF, 0xFB, 0x1C, 0xC0] + [UInt8](repeating: 0, count: 60))), "sample-rate index 3")
        XCTAssertNil(AudioContainer.detect(header: Data([0xFF, 0xF1, 0x7C, 0x80, 0, 0x1F, 0xFC])), "ADTS sample-rate index 15")
        XCTAssertNil(AudioContainer.detect(header: Data(bytes("caff") + [0, 1, 0, 0] + bytes("desc"))), "CAF is 'other'")
        XCTAssertNil(AudioContainer.detect(header: Data(bytes("fLaC") + [0, 0, 0, 0x22] + [UInt8](repeating: 0, count: 34))), "FLAC is 'other'")
        var garbage = [UInt8](repeating: 0, count: 4096)
        for index in garbage.indices { garbage[index] = UInt8(truncatingIfNeeded: index &* 31 &+ 7) }
        XCTAssertNil(AudioContainer.detect(header: Data(garbage)))
    }

    func testDetectAtURLReadsBoundedAndFollowsALongID3Tag() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aud002-container-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // The name is misleading on purpose: only the content counts.
        let tagged = root.appendingPathComponent("tagged.wav")
        try (Data(id3(50_000)) + MP3Fixture.data(frameCount: 4)).write(to: tagged)
        XCTAssertEqual(AudioContainer.detect(at: tagged), .mp3)
        let wave = root.appendingPathComponent("wave.mp3")
        try Data(bytes("RIFF") + [0x24, 0, 0, 0] + bytes("WAVEfmt ") + [UInt8](repeating: 0, count: 28)).write(to: wave)
        XCTAssertEqual(AudioContainer.detect(at: wave), .wav)
        let tagOnly = root.appendingPathComponent("tagonly.mp3")
        try Data(id3(50_000)).write(to: tagOnly)
        XCTAssertNil(AudioContainer.detect(at: tagOnly))
        let lying = root.appendingPathComponent("lying.mp3")
        try Data(bytes("ID3") + [4, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F] + bytes("tag claims 256 MB")).write(to: lying)
        XCTAssertNil(AudioContainer.detect(at: lying))
        let empty = root.appendingPathComponent("empty.m4a")
        try Data().write(to: empty)
        XCTAssertNil(AudioContainer.detect(at: empty))
        XCTAssertNil(AudioContainer.detect(at: root.appendingPathComponent("missing.wav")))
        XCTAssertNil(AudioContainer.detect(at: root), "a folder")
    }
}
