// PresetColorFacetTests.swift — roadmap PRE-004 acceptance (spec PRE-004-S1, S2; contract C1-C4):
// seeded synthetic thumbnails map to their colour families and the palette filter returns exactly the
// fixture presets whose dominant colours include the chosen family; index migration fixtures
// (ThumbnailFixtures/colors-*.json) rebuild or keep; the store coalesces saves and prunes.
import Foundation
@testable import PresetLibrary
import XCTest

final class PresetColorFacetTests: XCTestCase {
    private typealias Pixel = (UInt8, UInt8, UInt8)
    private static let width = 128
    private static let height = 72

    /// RGBA8 rows from a pixel function.
    private static func picture(_ pixel: (Int, Int) -> Pixel) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let p: Pixel = pixel(x, y)
                bytes.append(p.0); bytes.append(p.1); bytes.append(p.2); bytes.append(255)
            }
        }
        return bytes
    }

    /// The seeded fixtures: solid, two-tone, gradient and noisy, with their expected families.
    private static func fixtures() -> [(id: String, rgba: [UInt8], expected: [PresetColorFamily])] {
        var seed: UInt64 = 0x5052_4534   // "PRE4"
        let noise: () -> Int = {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % 61) - 30   // −30…30
        }
        let clamp: (Int) -> UInt8 = { (v: Int) -> UInt8 in UInt8(max(0, min(255, v))) }
        let solid = picture { (_: Int, _: Int) -> Pixel in (220, 30, 30) }
        let twoTone = picture { (x: Int, _: Int) -> Pixel in x < width / 2 ? (30, 60, 220) : (240, 220, 30) }
        let gradient = picture { (x: Int, _: Int) -> Pixel in
            let v = UInt8(x * 255 / (width - 1))
            return (v, v, v)
        }
        let noisy = picture { (_: Int, _: Int) -> Pixel in (clamp(40 + noise()), clamp(180 + noise()), clamp(60 + noise())) }
        return [("fixture/solid-red.milk", solid, [.red]),
                ("fixture/two-tone.milk", twoTone, [.yellow, .blue]),
                ("fixture/grey-gradient.milk", gradient, [.grey, .black, .white]),
                ("fixture/noisy-green.milk", noisy, [.green])]
    }

    func testSeededFixturesMapToTheirFamiliesAndTheFilterMatchesExactly() {
        var colors: [String: [PresetColorFamily]] = [:]
        for fixture in Self.fixtures() {
            let families = PresetColorPalette.dominantFamilies(rgba: fixture.rgba, width: Self.width, height: Self.height)
            XCTAssertEqual(families, fixture.expected, fixture.id)
            colors[fixture.id] = families
        }
        let filter = PresetColorFilter(colors: colors)
        for family in PresetColorFamily.allCases {
            let expected = Set(Self.fixtures().filter { $0.expected.contains(family) }.map(\.id))
            XCTAssertEqual(filter.matching(all: [family]), expected, family.name)
            XCTAssertEqual(filter.count(of: family), expected.count, family.name)
        }
        XCTAssertEqual(filter.matching(all: [.blue, .yellow]), ["fixture/two-tone.milk"])
        XCTAssertEqual(filter.matching(all: [.blue, .red]), [])
        XCTAssertEqual(filter.chips.map(\.family), [.red, .yellow, .green, .blue, .white, .grey, .black])
    }

    func testClassificationRulesAndInvalidInput() {
        XCTAssertEqual(PresetColorPalette.family(r: 10, g: 10, b: 40), .black)
        XCTAssertEqual(PresetColorPalette.family(r: 230, g: 240, b: 250), .white)
        XCTAssertEqual(PresetColorPalette.family(r: 128, g: 120, b: 130), .grey)
        XCTAssertEqual(PresetColorPalette.family(r: 255, g: 140, b: 0), .orange)
        XCTAssertEqual(PresetColorPalette.family(r: 0, g: 200, b: 200), .cyan)
        XCTAssertEqual(PresetColorPalette.family(r: 140, g: 40, b: 220), .purple)
        XCTAssertEqual(PresetColorPalette.family(r: 230, g: 60, b: 160), .pink)
        XCTAssertEqual(PresetColorPalette.family(r: 230, g: 20, b: 60), .red)
        XCTAssertEqual(PresetColorPalette.dominantFamilies(rgba: [1, 2, 3], width: 4, height: 4), [])
        // No family reaches 12%: the largest alone.
        var counts = Array(repeating: 0, count: PresetColorFamily.allCases.count)
        for i in counts.indices { counts[i] = 10 }
        counts[PresetColorFamily.cyan.order] = 11
        XCTAssertEqual(PresetColorPalette.rank(counts), [.cyan])
    }

    #if canImport(ImageIO) && canImport(CoreGraphics)
    func testPNGDecodeKeepsTheFamilies() throws {
        let data = try XCTUnwrap(Self.pngFixture())
        XCTAssertEqual(PresetColorPNG.dominantFamilies(data), [.yellow, .blue])
        XCTAssertEqual(PresetColorPNG.dominantFamilies(Data([0, 1, 2])), [])
    }

    private static func pngFixture() -> Data? {
        let rgba = fixtures()[1].rgba
        let output = NSMutableData()
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
    #endif

    // MARK: - Index migration (S2)

    private func folder(with fixture: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PresetColors-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        if let fixture {
            let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "ThumbnailFixtures"))
            try FileManager.default.copyItem(at: url, to: dir.appendingPathComponent(PresetColorIndex.fileName))
        }
        return dir
    }

    func testOldUnknownAndCorruptIndexesAreRebuiltAndCurrentIsKept() throws {
        let cases: [(String, PresetColorIndex.Repair)] = [("colors-v0", .schema(0)), ("colors-v99", .schema(99)),
                                                        ("colors-corrupt", .unreadable), ("colors-palette-v0", .palette(0))]
        for (fixture, repair) in cases {
            let dir = try folder(with: fixture)
            let opened = PresetColorIndex.openRepairing(directory: dir)
            XCTAssertEqual(opened.repair, repair, fixture)
            XCTAssertTrue(opened.index.entries.isEmpty, fixture)
            let rewritten = try JSONDecoder().decode(PresetColorIndex.self, from: Data(contentsOf: dir.appendingPathComponent(PresetColorIndex.fileName)))
            XCTAssertEqual(rewritten, PresetColorIndex(), fixture)
            XCTAssertEqual(PresetColorIndex.openRepairing(directory: dir).repair, .none, fixture)
        }
        let current = PresetColorIndex.openRepairing(directory: try folder(with: "colors-v1"))
        XCTAssertEqual(current.repair, .dropped(1))   // "teal" is not a family
        XCTAssertEqual(current.index.entries["pack/a.milk"], .init(thumbnailID: "t-a", colors: [.blue, .purple]))
        XCTAssertEqual(current.index.entries["pack/b.milk"], .init(thumbnailID: "t-b", colors: [.red]))
        XCTAssertNil(current.index.entries["pack/c.milk"])
        XCTAssertEqual(PresetColorIndex.openRepairing(directory: try folder(with: nil)).repair, .missing)
    }

    func testStoreCoalescesSavesInvalidatesAndPrunes() async throws {
        let dir = try folder(with: nil)
        let gate = AsyncGate()
        let store = PresetColorStore(directory: dir, sleep: { (_: Duration) in await gate.wait() })
        await store.record(presetID: "a", thumbnailID: "t-a", colors: [.blue])
        await store.record(presetID: "b", thumbnailID: "t-b", colors: [.red])
        await store.record(presetID: "b", thumbnailID: "t-b", colors: [.red])   // unchanged
        var saves = await store.saveCount
        XCTAssertEqual(saves, 0)
        await gate.open()
        for _ in 0..<200 where await store.saveCount == 0 { await Task.yield() }
        saves = await store.saveCount
        XCTAssertEqual(saves, 1)   // one write for both records
        XCTAssertEqual(PresetColorIndex.openRepairing(directory: dir).index.entries.count, 2)

        let kept = await store.invalidate(presetID: "a", keepingThumbnailID: "t-a")
        XCTAssertFalse(kept)
        let removed = await store.invalidate(presetID: "a", keepingThumbnailID: "t-a2")
        XCTAssertTrue(removed)
        await store.record(presetID: "c", thumbnailID: "t-c", colors: [.green])
        await store.flush()
        let pruned = await store.retainOnly(["b": "t-b", "c": "t-c-new"])
        XCTAssertEqual(pruned, 1)
        XCTAssertEqual(PresetColorIndex.openRepairing(directory: dir).index.entries.keys.sorted(), ["b"])
    }
}

/// Holds sleepers until opened (no clock in the test).
private actor AsyncGate {
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
