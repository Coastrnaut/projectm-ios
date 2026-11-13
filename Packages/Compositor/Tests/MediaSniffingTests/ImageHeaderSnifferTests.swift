// MED-014-T07: the image rows of the fixture table through `ImageHeaderSniffer` (MED-014-R1 to R5,
// S1). Plain Swift: runs on the host and in the Linux shape. JPEG fixtures here are assembled by
// hand (an ImageIO-encoded JPEG is in CompositorTests' SafeDecoderTests).
import Foundation
import MediaSniffing
import XCTest

final class ImageHeaderSnifferTests: XCTestCase {
    private typealias F = MediaFixtureBytes

    private func sniff(_ bytes: [UInt8]) -> Result<ImageHeaderFacts, MediaSniffError> {
        do throws(MediaSniffError) {
            return .success(try ImageHeaderSniffer.sniff(Data(bytes)))
        } catch {
            return .failure(error)
        }
    }

    private func assertFails(_ bytes: [UInt8], _ expected: MediaSniffError, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(sniff(bytes), .failure(expected), message, file: file, line: line)
    }

    /// A hand-made baseline JPEG skeleton: SOI, APP0, DQT, SOF0 (w × h, 1 component), DHT, SOS,
    /// a few entropy bytes (with stuffing and a restart marker), EOI.
    static func jpeg(width: Int = 16, height: Int = 16, eoi: Bool = true) -> [UInt8] {
        var b: [UInt8] = [0xFF, 0xD8]
        b += [0xFF, 0xE0, 0x00, 0x10] + Array("JFIF".utf8) + [0, 1, 1, 0, 0, 1, 0, 1, 0, 0]
        b += [0xFF, 0xDB, 0x00, 0x43, 0x00] + [UInt8](repeating: 1, count: 64)
        b += [0xFF, 0xC0, 0x00, 0x0B, 0x08, UInt8(height >> 8), UInt8(height & 0xFF), UInt8(width >> 8), UInt8(width & 0xFF),
              0x01, 0x01, 0x11, 0x00]
        b += [0xFF, 0xC4, 0x00, 0x14, 0x00] + [1] + [UInt8](repeating: 0, count: 15) + [0]
        b += [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00]
        b += [0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD0, 0x56]
        if eoi { b += [0xFF, 0xD9] }
        return b
    }

    // MARK: PNG (F1-F4, F8, F9)

    func testValidPNGGivesItsSize() {
        XCTAssertEqual(sniff(F.png()), .success(ImageHeaderFacts(container: .png, width: 8, height: 6)), "F1")
    }

    func testPNGCutAtEveryKindOfPointIsTruncated() {
        let png = F.png()
        let chunks = F.pngChunkOffsets(png)
        let idat = chunks.first { $0.type == "IDAT" }!, iend = chunks.first { $0.type == "IEND" }!
        let cuts: [(String, Int)] = [("after the signature", 8), ("inside IHDR", 8 + 15), ("inside IDAT", idat.offset + 8 + idat.length / 2),
                                     ("before IEND", iend.offset), ("inside IEND's CRC", png.count - 2)]
        for (name, cut) in cuts { assertFails(Array(png.prefix(cut)), .truncated, "F2 cut \(name) at \(cut)") }
        // Inside the signature the bytes are not recognisably a PNG: left to ImageIO ("not an image").
        for cut in 1..<8 { XCTAssertEqual(sniff(Array(png.prefix(cut))), .success(ImageHeaderFacts(container: .other)), "cut at \(cut)") }
        // Every later cut point: never a success, never a crash.
        for cut in 8..<png.count {
            if case .success = sniff(Array(png.prefix(cut))) { XCTFail("cut at \(cut) accepted") }
        }
    }

    func testPNGWithAFlippedDataByteFailsItsChecksum() {
        var png = F.png()
        let idat = F.pngChunkOffsets(png).first { $0.type == "IDAT" }!
        png[idat.offset + 8 + 10] ^= 0x01
        assertFails(png, .corrupt, "F3")
    }

    func testAbsurdPNGHeaderSizeIsReportedForTheLimitCheck() {
        let facts = sniff(F.png(headerWidth: 100_000, headerHeight: 100_000))
        XCTAssertEqual(facts, .success(ImageHeaderFacts(container: .png, width: 100_000, height: 100_000)), "F4")
        XCTAssertEqual(try? facts.get().pixelCount, 10_000_000_000)
    }

    func testEmptyDataIsEmpty() {
        assertFails([], .empty, "F8")
    }

    func testRandomBytesBehindAPNGSignatureAreRefused() {
        var rng = F.SplitMix64(seed: 14)
        for round in 0..<20 {
            let bytes = F.pngSignature + (0..<4096).map { (_: Int) -> UInt8 in UInt8(truncatingIfNeeded: rng.next()) }
            switch sniff(bytes) {
            case .failure(let error): XCTAssertTrue(error == .corrupt || error == .truncated, "F9 round \(round): \(error)")
            case .success: XCTFail("F9 round \(round) accepted")
            }
        }
    }

    func testPNGEdgeCases() {
        let png = F.png()
        XCTAssertEqual(sniff(png + [1, 2, 3, 4, 5]), .success(ImageHeaderFacts(container: .png, width: 8, height: 6)), "junk after IEND")
        // An ancillary chunk (APNG-style) with a wrong CRC is skipped by length.
        var text = F.pngChunk("tEXt", Array("a\u{0}b".utf8))
        text[text.count - 1] ^= 0xFF
        let iend = F.pngChunkOffsets(png).first { $0.type == "IEND" }!
        let withText = Array(png[..<iend.offset]) + text + Array(png[iend.offset...])
        XCTAssertEqual(sniff(withText), .success(ImageHeaderFacts(container: .png, width: 8, height: 6)), "ancillary chunk skipped")
        // An unknown critical chunk cannot be decoded.
        let withUnknown = Array(png[..<iend.offset]) + F.pngChunk("ZZZZ", [1]) + Array(png[iend.offset...])
        assertFails(withUnknown, .corrupt, "unknown critical chunk")
        // No IDAT at all.
        let noData = F.pngSignature + F.pngChunk("IHDR", Array(png[16..<29])) + F.pngChunk("IEND", [])
        assertFails(noData, .corrupt, "no IDAT")
        // A zero width.
        assertFails(F.png(headerWidth: 0), .corrupt, "zero width")
        // A length field of 0xFFFFFFFF.
        var huge = png
        huge.replaceSubrange(33..<37, with: [0xFF, 0xFF, 0xFF, 0xFF])
        assertFails(huge, .corrupt, "length over 2^31 - 1")
    }

    // MARK: JPEG (F5-F7 shapes)

    func testJPEGSkeletons() {
        XCTAssertEqual(sniff(Self.jpeg()), .success(ImageHeaderFacts(container: .jpeg, width: 16, height: 16)), "F5 shape")
        assertFails(Self.jpeg(eoi: false), .truncated, "F6 shape: no EOI")
        XCTAssertEqual(sniff(Self.jpeg(width: 65_535, height: 65_535)),
                       .success(ImageHeaderFacts(container: .jpeg, width: 65_535, height: 65_535)), "F7 shape")
        assertFails(Self.jpeg(width: 0, height: 16), .corrupt, "zero width")
        XCTAssertEqual(sniff(Self.jpeg() + [9, 9, 9]), .success(ImageHeaderFacts(container: .jpeg, width: 16, height: 16)),
                       "bytes after EOI")
        assertFails(Array(Self.jpeg().prefix(30)), .truncated, "cut inside a segment")
        var noSOF = Self.jpeg()
        noSOF[noSOF.firstIndex(of: 0xC0)!] = 0xC4   // the frame header becomes a table
        assertFails(noSOF, .corrupt, "scan without a frame header")
    }

    // MARK: HEIF (F10, F11)

    func testHEIFHeaders() {
        XCTAssertEqual(sniff(F.heif()), .success(ImageHeaderFacts(container: .heif, width: 4032, height: 3024)),
                       "largest ispe wins")
        var overrun = F.heif()
        overrun[3] = 0xF0   // ftyp size runs past the file
        assertFails(overrun, .truncated, "F10")
        assertFails(F.heif(brands: ["\u{0}\u{0}\u{0}\u{0}", "\u{0}\u{0}\u{0}\u{0}"]), .corrupt, "F11: unprintable brands")
        XCTAssertEqual(sniff(F.heif(brands: ["isom", "mp42"])), .success(ImageHeaderFacts(container: .other)),
                       "a movie's ftyp is left to ImageIO")
        let noMeta = Array(F.heif().prefix(F.boxOffset(F.heif(), "meta")!)) + F.box("mdat", [0])
        assertFails(noMeta, .corrupt, "no meta")
        XCTAssertEqual(sniff(F.heif(sizes: [])), .success(ImageHeaderFacts(container: .heif)), "no ispe: size unknown")
    }

    func testOtherFormatsAreLeftToTheSystemDecoder() {
        XCTAssertEqual(sniff(Array("GIF89a".utf8) + [0, 0, 0, 0]), .success(ImageHeaderFacts(container: .other)))
        XCTAssertEqual(sniff(Array("not an image".utf8)), .success(ImageHeaderFacts(container: .other)))
    }
}
