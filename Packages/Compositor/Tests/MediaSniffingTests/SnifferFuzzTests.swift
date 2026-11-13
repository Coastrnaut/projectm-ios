// MED-014-T13: fixed-seed mutation fuzz of the sniffers (MED-014-S2, R13). Every mutation of a valid
// tiny PNG, JPEG skeleton, HEIF header and movie returns facts or a `MediaSniffError`: the test
// passing at all is the "no crash, no hang" proof (a trap or an endless loop would fail the run).
// Plain Swift: host and Linux shape. Counts, not wall-clock time.
import Foundation
import MediaSniffing
import XCTest

final class SnifferFuzzTests: XCTestCase {
    private typealias F = MediaFixtureBytes

    func testImageMutationsAlwaysGiveATypedResult() {
        var rng = F.SplitMix64(seed: 0x4D45_4430_3134)   // "MED014"
        let seeds = [F.png(), ImageHeaderSnifferTests.jpeg(), F.heif()]
        var accepted = 0, refused = 0
        for i in 0..<1800 {
            var bytes = seeds[i % seeds.count]
            for _ in 0...rng.below(3) { bytes = F.mutate(bytes, &rng) }
            do throws(MediaSniffError) {
                _ = try ImageHeaderSniffer.sniff(Data(bytes))
                accepted += 1
            } catch {
                refused += 1
            }
        }
        XCTAssertEqual(accepted + refused, 1800)
        XCTAssertGreaterThan(refused, 900, "most mutations of a checksummed or length-checked file are refused")
    }

    func testMovieMutationsAlwaysGiveATypedResult() throws {
        var rng = F.SplitMix64(seed: 0x4D4F_4F56)   // "MOOV"
        let seeds = [F.movie(), F.movie(handler: "soun", format: "mp4a"), F.movie(moovFirst: false)]
        var results = 0
        for i in 0..<900 {
            var bytes = seeds[i % seeds.count]
            for _ in 0...rng.below(3) { bytes = F.mutate(bytes, &rng) }
            do throws(MediaSniffError) {
                let facts = try MovieContainerSniffer.sniff(DataByteSource(Data(bytes)))
                XCTAssertLessThanOrEqual(facts.boxesVisited, MovieSniffLimits.standard.maxBoxes)
            } catch {
                XCTAssertNotEqual(error, .unreadable, "in-memory bytes never fail to read")
            }
            results += 1
        }
        XCTAssertEqual(results, 900)
    }
}
