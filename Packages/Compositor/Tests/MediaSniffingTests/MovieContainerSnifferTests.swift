// MED-014-T11: the movie rows of the fixture table through `MovieContainerSniffer` (MED-014-R7, R8,
// S1). Plain Swift: runs on the host and in the Linux shape.
import Foundation
import MediaSniffing
import XCTest

final class MovieContainerSnifferTests: XCTestCase {
    private typealias F = MediaFixtureBytes

    private func sniff(_ bytes: [UInt8], limits: MovieSniffLimits = .standard) -> Result<MovieContainerFacts, MediaSniffError> {
        do throws(MediaSniffError) {
            return .success(try MovieContainerSniffer.sniff(DataByteSource(Data(bytes)), limits: limits))
        } catch {
            return .failure(error)
        }
    }

    private func facts(_ bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line) -> MovieContainerFacts? {
        switch sniff(bytes) {
        case .success(let facts): return facts
        case .failure(let error):
            XCTFail("refused: \(error)", file: file, line: line)
            return nil
        }
    }

    func testMinimalVideoMovieGivesItsTrackFacts() {
        let f = facts(F.movie())
        XCTAssertEqual(f?.trackCount, 1)
        XCTAssertEqual(f?.videoTrackCount, 1)
        XCTAssertEqual(f?.codecString, "avc1")
        XCTAssertEqual(f?.codedWidth, 64)
        XCTAssertEqual(f?.codedHeight, 48)
        XCTAssertEqual(facts(F.movie(moovFirst: false))?.videoTrackCount, 1, "moov after mdat")
    }

    func testMoovRunningPastTheFileIsTruncated() {
        XCTAssertEqual(sniff(F.movieWithOverrunningMoov()), .failure(.truncated), "F12")
    }

    func testSoundOnlyMovieHasNoVideoTrack() {
        let f = facts(F.movie(handler: "soun", format: "mp4a"))
        XCTAssertEqual(f?.trackCount, 1, "F13")
        XCTAssertEqual(f?.videoTrackCount, 0)
        XCTAssertNil(f?.codec)
    }

    func testNonMovieBytesAreUnrecognized() {
        XCTAssertEqual(sniff(Array("This is plain text, not a movie at all.".utf8)), .failure(.unrecognized), "F15")
        XCTAssertEqual(sniff(MediaFixtureBytes.png()), .failure(.unrecognized), "a PNG")
        XCTAssertEqual(sniff([]), .failure(.empty))
        XCTAssertEqual(sniff([0, 0, 0]), .failure(.unrecognized), "shorter than a box header")
    }

    func testOversizedSampleEntryIsReported() {
        let f = facts(F.movie(width: 8192, height: 8))
        XCTAssertEqual(f?.codedWidth, 8192, "F16")
        XCTAssertEqual(f?.codedHeight, 8)
    }

    func testBoxSizeRules() {
        // A 64-bit size (size field 1) for mdat.
        var large = F.movie()
        let mdat = F.boxOffset(large, "mdat")!
        large.replaceSubrange(mdat..<large.count, with: [0, 0, 0, 1] + Array("mdat".utf8) + [0, 0, 0, 0, 0, 0, 0, 24] + [UInt8](repeating: 0, count: 8))
        XCTAssertEqual(facts(large)?.videoTrackCount, 1, "64-bit size")
        // Size 0: the last box runs to the end of the file.
        var toEnd = F.movie()
        toEnd.replaceSubrange(mdat..<mdat + 4, with: [0, 0, 0, 0])
        XCTAssertEqual(facts(toEnd)?.videoTrackCount, 1, "size 0 last box")
        // A size below the header.
        var tiny = F.movie()
        tiny.replaceSubrange(mdat..<mdat + 4, with: [0, 0, 0, 4])
        XCTAssertEqual(sniff(tiny), .failure(.corrupt), "size 4")
        // A 64-bit size beyond the file.
        var huge = F.movie()
        huge.replaceSubrange(mdat..<huge.count, with: [0, 0, 0, 1] + Array("mdat".utf8) + [0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(sniff(huge), .failure(.truncated), "64-bit size past the end")
    }

    func testMoovCountAndWalkBounds() {
        let movie = F.movie()
        let moov = F.boxOffset(movie, "moov")!, mdat = F.boxOffset(movie, "mdat")!
        XCTAssertEqual(sniff(movie + Array(movie[moov..<mdat])), .failure(.corrupt), "two moov")
        XCTAssertEqual(sniff(Array(movie[..<moov]) + Array(movie[mdat...])), .failure(.corrupt), "no moov")
        XCTAssertEqual(sniff(movie, limits: MovieSniffLimits(maxBoxes: 5, maxDepth: 8, maxTracks: 64, maxEntryBytes: 4096)),
                       .failure(.corrupt), "box count bound")
        XCTAssertEqual(sniff(movie, limits: MovieSniffLimits(maxBoxes: 4096, maxDepth: 3, maxTracks: 64, maxEntryBytes: 4096)),
                       .failure(.corrupt), "depth bound")
        // 5,000 empty boxes inside moov exceed the standard bound.
        let many = [UInt8]((0..<5000).flatMap { (_: Int) -> [UInt8] in F.box("free", []) })
        let crowded = F.box("ftyp", Array("qt  ".utf8) + [0, 0, 0, 0]) + F.box("moov", many)
        XCTAssertEqual(sniff(crowded), .failure(.corrupt), "more than 4,096 boxes")
    }

    func testFileByteSourceReadsOnlyWhatItIsAskedFor() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MED014-\(UUID().uuidString).mov")
        try Data(F.movie()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try FileByteSource(url: url)
        XCTAssertEqual(source.count, Int64(F.movie().count))
        XCTAssertEqual(try source.bytes(at: source.count - 2, length: 100).count, 2, "clamped at the end")
        XCTAssertEqual(try source.bytes(at: source.count + 10, length: 4), [], "nothing past the end")
        XCTAssertEqual(try MovieContainerSniffer.sniff(source).codecString, "avc1")
        XCTAssertThrowsError(try FileByteSource(url: url.appendingPathExtension("missing"))) {
            XCTAssertEqual($0 as? MediaSniffError, .unreadable)
        }
    }
}
