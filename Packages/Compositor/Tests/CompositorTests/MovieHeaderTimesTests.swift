// MovieHeaderTimesTests.swift — FILE-008-T05 (FILE-008-R6): synthetic movies with version 0 and 1
// headers, a 64-bit box size, and hostile sizes. Plain bytes; runs on Linux.
import Foundation
import XCTest
@testable import VideoLayer

final class MovieHeaderTimesTests: XCTestCase {
    private func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }

    private func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(UInt32(8 + payload.count)) + Array(type.utf8) + payload
    }

    /// A full box header with non-zero times, then `rest` filler bytes.
    private func timedBox(_ type: String, version: UInt8, rest: Int = 12) -> [UInt8] {
        let width = version == 1 ? 8 : 4
        let times = [UInt8](repeating: 0xAB, count: 2 * width)
        return box(type, [version, 0, 0, 0] + times + [UInt8](repeating: 0x11, count: rest))
    }

    private func movie() -> [UInt8] {
        let mdia = box("mdia", timedBox("mdhd", version: 0) + box("hdlr", [UInt8](repeating: 0xCD, count: 20)))
        let trak = box("trak", timedBox("tkhd", version: 1) + mdia)
        let moov = box("moov", timedBox("mvhd", version: 0, rest: 80) + trak)
        // ftyp, then an mdat with a 64-bit size, then moov (as the passthrough export writes it).
        let mdatPayload = [UInt8](repeating: 0xAB, count: 32)
        let mdat = be32(1) + Array("mdat".utf8) + [0, 0, 0, 0] + be32(UInt32(16 + mdatPayload.count)) + mdatPayload
        return box("ftyp", Array("qt  ".utf8) + [0, 0, 0, 0]) + mdat + moov
    }

    private func write(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mht-\(UUID().uuidString).mov")
        try Data(bytes).write(to: url)
        return url
    }

    func testFindsTheSixFieldsOfVersion0And1Headers() {
        let bytes = movie()
        let moovStart = 16 + 48   // after ftyp (16 bytes) and mdat (48 bytes)
        XCTAssertEqual(Array(bytes[(moovStart + 4)..<(moovStart + 8)]), Array("moov".utf8))
        let payload = Array(bytes[(moovStart + 8)...])
        let fields = MovieHeaderTimes.fields(inMoovPayload: payload)
        XCTAssertEqual(fields.map(\.width), [4, 4, 8, 8, 4, 4])
        for field in fields {
            XCTAssertEqual(Array(payload[field.offset..<(field.offset + field.width)]), [UInt8](repeating: 0xAB, count: field.width))
        }
    }

    func testZeroesTheTimesInPlaceAndNothingElse() throws {
        let original = movie()
        let url = try write(original)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try MovieHeaderTimes.zero(fileAt: url), 6)
        let changed = [UInt8](try Data(contentsOf: url))
        XCTAssertEqual(changed.count, original.count)
        let differing = zip(original, changed).filter { (pair: (UInt8, UInt8)) -> Bool in pair.0 != pair.1 }
        XCTAssertEqual(differing.count, 2 * 4 + 2 * 8 + 2 * 4, "only the time bytes change")
        XCTAssertTrue(differing.allSatisfy { (pair: (UInt8, UInt8)) -> Bool in pair.0 == 0xAB && pair.1 == 0 })
        XCTAssertEqual(try MovieHeaderTimes.zero(fileAt: url), 6, "repeatable")
        XCTAssertEqual([UInt8](try Data(contentsOf: url)), changed)
    }

    func testHostileSizesWriteNothing() throws {
        var bytes = movie()
        bytes[0] = 0x7F   // the first box claims to run past the end
        let url = try write(bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try MovieHeaderTimes.zero(fileAt: url))
        XCTAssertEqual([UInt8](try Data(contentsOf: url)), bytes)

        let noMovie = try write(box("ftyp", [1, 2, 3, 4]))
        defer { try? FileManager.default.removeItem(at: noMovie) }
        XCTAssertThrowsError(try MovieHeaderTimes.zero(fileAt: noMovie)) { (error: any Error) in
            XCTAssertEqual(error as? MovieHeaderTimes.Failure, .noMovieBox)
        }
        // A truncated header inside moov stops the walk without reading out of bounds.
        let broken = box("trak", be32(200) + Array("tkhd".utf8) + [1, 0, 0, 0])
        XCTAssertEqual(MovieHeaderTimes.fields(inMoovPayload: broken), [])
    }
}
