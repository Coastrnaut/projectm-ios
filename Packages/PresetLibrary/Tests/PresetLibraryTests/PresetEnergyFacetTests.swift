// PresetEnergyFacetTests.swift — roadmap PRE-005 acceptance (spec PRE-005-S1, S2; contract C2-C4):
// "Classification is stable for fixed preset seed and fixture". Seeded synthetic frame sequences with
// known motion (static, slow drift, fast noise) classify as Calm, Moderate and Energetic; scoring them
// again gives bit-identical scores equal to pinned values (integer maths, so the same on Linux); the
// energy filter returns exactly the matching fixture presets; the score survives the PNG field; index
// migration fixtures (ThumbnailFixtures/motion-*.json) rebuild or keep; the store coalesces saves.
import Foundation
@testable import PresetLibrary
import XCTest

final class PresetEnergyFacetTests: XCTestCase {
    private static let width = 128
    private static let height = 72

    /// A grey RGBA8 picture from a brightness function.
    private static func picture(_ value: (Int, Int) -> UInt8) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v: UInt8 = value(x, y)
                bytes.append(v); bytes.append(v); bytes.append(v); bytes.append(255)
            }
        }
        return bytes
    }

    /// Integer triangle wave across the picture (period 128 px, 0…252), shifted by `shift` pixels.
    private static func triangle(_ x: Int, shift: Int) -> UInt8 {
        let t: Int = (x + shift) % 128
        return UInt8(t < 64 ? t * 4 : (127 - t) * 4)
    }

    /// The fixtures, each three samples like the thumbnail drawing's (PresetMotionScore.sampleFrames),
    /// from seed "PRE5"; with their expected classes and pinned scores.
    private static func fixtures(seed start: UInt64 = 0x5052_4535) -> [(id: String, samples: [[UInt8]], expected: PresetEnergy)] {
        var seed: UInt64 = start
        let next: () -> UInt8 = {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: seed >> 56)
        }
        let still: [UInt8] = picture { (x: Int, y: Int) -> UInt8 in UInt8((x * 3 + y * 5) % 256) }
        let staticFrames: [[UInt8]] = [still, still, still]
        let drift: [[UInt8]] = [0, 2, 4].map { (shift: Int) -> [UInt8] in picture { (x: Int, _: Int) -> UInt8 in triangle(x, shift: shift) } }
        let noise: [[UInt8]] = (0..<3).map { (_: Int) -> [UInt8] in picture { (_: Int, _: Int) -> UInt8 in next() } }
        return [("pack/static.milk", staticFrames, .calm), ("pack/drift.milk", drift, .moderate), ("pack/noise.milk", noise, .energetic)]
    }

    /// Pinned scores of the fixtures (thousandths of a level): any change to the scorer shows here.
    private static let pinned: [String: Int] = ["pack/static.milk": 0, "pack/drift.milk": 7_875, "pack/noise.milk": 86_832]

    func testFixedFixturesClassifyStablyWithPinnedScores() throws {
        let first = Self.fixtures(), second = Self.fixtures()
        for (a, b) in zip(first, second) {
            let scoreA = try XCTUnwrap(PresetMotionScore.score(samples: a.samples, width: Self.width, height: Self.height), a.id)
            let scoreB = try XCTUnwrap(PresetMotionScore.score(samples: b.samples, width: Self.width, height: Self.height), b.id)
            XCTAssertEqual(scoreA, scoreB, "bit-identical on a second run: \(a.id)")
            XCTAssertEqual(scoreA, Self.pinned[a.id], a.id)
            XCTAssertEqual(PresetEnergy.of(score: scoreA), a.expected, a.id)
            XCTAssertEqual(PresetMotionScore.energy(samples: a.samples, width: Self.width, height: Self.height), a.expected)
        }
        // Another seed gives other noise but the same class.
        let other = Self.fixtures(seed: 7)[2]
        XCTAssertEqual(PresetMotionScore.energy(samples: other.samples, width: Self.width, height: Self.height), .energetic)
        // Invalid input: one sample, a size that does not match the bytes.
        XCTAssertNil(PresetMotionScore.score(samples: [first[0].samples[0]], width: Self.width, height: Self.height))
        XCTAssertNil(PresetMotionScore.score(samples: first[0].samples, width: Self.width + 1, height: Self.height))
        XCTAssertEqual(PresetEnergy.of(score: 3_999), .calm)
        XCTAssertEqual(PresetEnergy.of(score: 4_000), .moderate)
        XCTAssertEqual(PresetEnergy.of(score: 16_000), .energetic)
    }

    func testTheEnergyFilterMatchesExactlyTheFixturePresets() throws {
        var scores: [String: Int] = [:]
        for fixture in Self.fixtures() {
            scores[fixture.id] = try XCTUnwrap(PresetMotionScore.score(samples: fixture.samples, width: Self.width, height: Self.height))
        }
        let filter = PresetEnergyFilter(scores: scores)
        for fixture in Self.fixtures() {
            XCTAssertEqual(filter.matching(any: [fixture.expected]), [fixture.id], fixture.expected.name)
            XCTAssertEqual(filter.count(of: fixture.expected), 1)
        }
        XCTAssertEqual(filter.matching(any: [.calm, .energetic]), ["pack/static.milk", "pack/noise.milk"])   // OR
        XCTAssertEqual(filter.matching(any: []).count, 3)
        XCTAssertEqual(filter.chips.map(\.energy), [.calm, .moderate, .energetic])
        XCTAssertEqual(filter.presetCount, 3)
        XCTAssertEqual(PresetEnergyFilter.empty.chips.count, 0)
        XCTAssertEqual(PresetEnergy.calm.spokenName, "Calm motion")
    }

    func testTheScoreTravelsInThePNGField() throws {
        // A minimal chunk-valid PNG (the image data is not decoded here; works on Linux).
        var png: [UInt8] = PresetMotionPNG.signature
        png += PresetMotionPNG.chunk(type: "IHDR", data: [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0])
        png += PresetMotionPNG.chunk(type: "IDAT", data: [1, 2, 3])
        png += PresetMotionPNG.chunk(type: "IEND", data: [])
        let plain = Data(png)
        XCTAssertNil(PresetMotionPNG.score(in: plain))
        let tagged = try XCTUnwrap(PresetMotionPNG.embed(score: 12_345, in: plain))
        XCTAssertEqual(PresetMotionPNG.score(in: tagged), 12_345)
        let retagged = try XCTUnwrap(PresetMotionPNG.embed(score: 7, in: tagged))
        XCTAssertEqual(PresetMotionPNG.score(in: retagged), 7, "replaced, not duplicated")
        XCTAssertEqual(retagged.count, tagged.count - 4)
        XCTAssertEqual(PresetMotionPNG.chunks(retagged)?.last?.type, "IEND")
        XCTAssertEqual(PresetMotionPNG.crc32(Array("IEND".utf8)), 0xAE42_6082, "PNG's CRC-32")
        // Another score version or bad text is ignored; non-PNG bytes are refused.
        var foreign: [UInt8] = PresetMotionPNG.signature
        foreign += PresetMotionPNG.chunk(type: "tEXt", data: Array("projectM-motion".utf8) + [0] + Array("99:5".utf8))
        foreign += PresetMotionPNG.chunk(type: "IEND", data: [])
        XCTAssertNil(PresetMotionPNG.score(in: Data(foreign)))
        XCTAssertNil(PresetMotionPNG.embed(score: 1, in: Data("not a png".utf8)))
        XCTAssertNil(PresetMotionPNG.embed(score: -1, in: plain))
        #if canImport(ImageIO) && canImport(CoreGraphics)
        // A real picture still decodes with its field (Apple platforms).
        XCTAssertNotNil(PresetColorPNG.rgba(Self.onePixelPNG))
        let real = try XCTUnwrap(PresetMotionPNG.embed(score: 99, in: Self.onePixelPNG))
        XCTAssertNotNil(PresetColorPNG.rgba(real))
        XCTAssertEqual(PresetMotionPNG.score(in: real), 99)
        #endif
    }

    /// A 1 × 1 red PNG.
    private static let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==")!

    // MARK: - Index migration (S2)

    private func folder(with fixture: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PresetMotion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        if let fixture {
            let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "ThumbnailFixtures"))
            try FileManager.default.copyItem(at: url, to: dir.appendingPathComponent(PresetMotionIndex.fileName))
        }
        return dir
    }

    func testOldUnknownAndCorruptIndexesAreRebuiltAndCurrentIsKept() throws {
        let cases: [(String, PresetMotionIndex.Repair)] = [("motion-v0", .schema(0)), ("motion-v99", .schema(99)),
                                                         ("motion-corrupt", .unreadable), ("motion-score-v0", .scoreVersion(0))]
        for (fixture, repair) in cases {
            let dir = try folder(with: fixture)
            let opened = PresetMotionIndex.openRepairing(directory: dir)
            XCTAssertEqual(opened.repair, repair, fixture)
            XCTAssertTrue(opened.index.entries.isEmpty, fixture)
            let rewritten = try JSONDecoder().decode(PresetMotionIndex.self, from: Data(contentsOf: dir.appendingPathComponent(PresetMotionIndex.fileName)))
            XCTAssertEqual(rewritten, PresetMotionIndex(), fixture)
            XCTAssertEqual(PresetMotionIndex.openRepairing(directory: dir).repair, .none, fixture)
        }
        let current = PresetMotionIndex.openRepairing(directory: try folder(with: "motion-v1"))
        XCTAssertEqual(current.repair, .dropped(2))   // a negative score, an empty thumbnail ID
        XCTAssertEqual(current.index.entries["pack/a.milk"], .init(thumbnailID: "t-a", score: 1000))
        XCTAssertEqual(current.index.entries["pack/b.milk"], .init(thumbnailID: "t-b", score: 30000))
        XCTAssertEqual(current.index.entries.count, 2)
        XCTAssertEqual(PresetMotionIndex.openRepairing(directory: try folder(with: nil)).repair, .missing)
    }

    func testStoreCoalescesSavesInvalidatesAndPrunes() async throws {
        let dir = try folder(with: nil)
        let gate = MotionGate()
        let store = PresetMotionStore(directory: dir, sleep: { (_: Duration) in await gate.wait() })
        await store.record(presetID: "a", thumbnailID: "t-a", score: 100)
        await store.record(presetID: "b", thumbnailID: "t-b", score: 20_000)
        await store.record(presetID: "b", thumbnailID: "t-b", score: 20_000)   // unchanged
        await store.record(presetID: "x", thumbnailID: "t-x", score: -1)       // refused
        var saves = await store.saveCount
        XCTAssertEqual(saves, 0)
        await gate.open()
        for _ in 0..<500 where await store.saveCount == 0 { try await Task.sleep(for: .milliseconds(10)) }   // up to 5 s (CI)
        saves = await store.saveCount
        XCTAssertEqual(saves, 1)   // one write for both records
        XCTAssertEqual(PresetMotionIndex.openRepairing(directory: dir).index.entries.count, 2)

        let kept = await store.invalidate(presetID: "a", keepingThumbnailID: "t-a")
        XCTAssertFalse(kept)
        let removed = await store.invalidate(presetID: "a", keepingThumbnailID: "t-a2")
        XCTAssertTrue(removed)
        await store.record(presetID: "c", thumbnailID: "t-c", score: 5)
        await store.flush()
        let pruned = await store.retainOnly(["b": "t-b", "c": "t-c-new"])
        XCTAssertEqual(pruned, 1)
        XCTAssertEqual(PresetMotionIndex.openRepairing(directory: dir).index.entries.keys.sorted(), ["b"])
    }
}

/// Holds sleepers until opened (no clock in the test).
private actor MotionGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiters.append(c) }
    }

    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}
