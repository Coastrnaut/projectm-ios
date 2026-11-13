// QA-002-T05: SHA-256 against the FIPS 180-4 examples (and CryptoKit where it exists), SplitMix64
// stability and the scene catalog's rules. Plain Swift: runs on Linux.
import GoldenImages
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#endif

final class GoldenSHA256Tests: XCTestCase {
    func testStandardVectors() {
        XCTAssertEqual(GoldenSHA256.hex([]), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(GoldenSHA256.hex(Array("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(GoldenSHA256.hex(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testPaddingBoundariesMatchCryptoKit() throws {
        #if canImport(CryptoKit)
        for length in [55, 56, 63, 64, 65, 119, 120, 1_000] {
            let bytes = (0..<length).map { (i: Int) -> UInt8 in UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
            let expected = SHA256.hash(data: bytes).map { (b: UInt8) -> String in String(format: "%02x", b) }.joined()
            XCTAssertEqual(GoldenSHA256.hex(bytes), expected, "length \(length)")
        }
        #else
        throw XCTSkip("CryptoKit is not available; the standard vectors cover the algorithm.")
        #endif
    }

    func testSplitMix64IsStable() {
        var random = GoldenRandom(seed: 0)
        // Published SplitMix64 outputs for seed 0.
        XCTAssertEqual(random.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(random.next(), 0x6E78_9E6A_A1B9_65F4)
        var a = GoldenRandom(seed: 42), b = GoldenRandom(seed: 42)
        for _ in 0..<100 { XCTAssertEqual(a.unit(), b.unit()) }
    }

    func testCatalogRunsAreValid() {
        XCTAssertEqual(GoldenSceneCatalog.runs.count, 7, "QA-002-R1: 5 to 8 scenes")
        XCTAssertEqual(Set(GoldenSceneCatalog.runs.map(\.name)).count, GoldenSceneCatalog.runs.count)
        for run in GoldenSceneCatalog.runs { XCTAssertEqual(run.problems, [], run.name) }
        XCTAssertEqual(Set(GoldenSceneCatalog.runs.map(\.seed)).count, GoldenSceneCatalog.runs.count, "distinct seeds")
        XCTAssertEqual(GoldenResolution.all.map(\.description), ["128x96", "256x192"])
        let bad = GoldenSceneRun(name: "bad", seed: 1, frameCount: 4, capturedFrames: [0, 4], audio: .silent)
        XCTAssertFalse(bad.problems.isEmpty, "the warm-up and out-of-range frames are refused")
    }

    func testAudioAndPhotosAreDeterministic() throws {
        let audio = GoldenAudio.seededBands(count: 32)
        XCTAssertEqual(audio.bands(frame: 3, seed: 7), audio.bands(frame: 3, seed: 7))
        XCTAssertNotEqual(audio.bands(frame: 3, seed: 7), audio.bands(frame: 4, seed: 7))
        XCTAssertTrue(audio.bands(frame: 0, seed: 7).allSatisfy { (b: Float) -> Bool in b >= 0.15 && b < 0.85 })
        XCTAssertEqual(GoldenAudio.alternating(count: 4).bands(frame: 6, seed: 0), [1, 1, 1, 1])
        XCTAssertEqual(GoldenAudio.alternating(count: 4).bands(frame: 7, seed: 0), [0, 0, 0, 0])
        XCTAssertEqual(GoldenAudio.silent.bands(frame: 1, seed: 0), [])
        let recipe = GoldenPhotoRecipe(width: 64, height: 48, seed: 1_001)
        XCTAssertEqual(recipe.image(), recipe.image())
        XCTAssertEqual(recipe.image().pixel(x: 63, y: 0).r, 255)
        XCTAssertEqual(recipe.image().pixel(x: 0, y: 47).g, 255)
        let first = GoldenSceneCatalog.runs[0]
        XCTAssertEqual(first.presentationNanoseconds(frame: 0), 1_000_000_000)
        XCTAssertEqual(first.presentationNanoseconds(frame: 6), 1_100_000_002)
    }
}
