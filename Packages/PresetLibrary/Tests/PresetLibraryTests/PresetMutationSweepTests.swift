// PRE-012-T19: a seeded sweep of corrupted presets (PRE-012-S2). Every variant must be validated
// quickly, must end added, quarantined or refused, and must leave the library exactly as the
// contract says. The seed is fixed, so the sweep is the same on every run and machine.
import XCTest
@testable import PresetLibrary

final class PresetMutationSweepTests: XCTestCase {
    private typealias F = UserPresetFixtures
    static let variants = 600

    /// SplitMix64: small, well known, and the same everywhere.
    /// Only `next()` and the two helpers are used, never the standard library's random functions,
    /// so the sequence does not depend on the Swift version.
    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        /// A value in `range`.
        mutating func pick(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
        mutating func byte(_ range: ClosedRange<Int> = 0...255) -> UInt8 { UInt8(pick(range)) }
    }

    private func mutate(_ base: [UInt8], _ index: Int, _ rng: inout Generator) -> [UInt8] {
        var bytes = base
        func position() -> Int { rng.pick(0...max(bytes.count - 1, 0)) }
        switch index % 10 {
        case 0:   // flip a few bytes to anything
            for _ in 0..<rng.pick(1...8) where !bytes.isEmpty { bytes[position()] = rng.byte() }
        case 1:   // truncate
            bytes = Array(bytes.prefix(position()))
        case 2:   // repeat one line many times
            let lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
            let line = Array(lines[rng.pick(0...(lines.count - 1))]) + [0x0A]
            let times = rng.pick(2...30_000)
            let at = position()
            var repeated: [UInt8] = []
            repeated.reserveCapacity(min(line.count * times, 2 << 20))
            for _ in 0..<times where repeated.count < 2 << 20 { repeated += line }
            bytes.insert(contentsOf: repeated, at: at)
        case 3:   // sprinkle brackets
            let brackets: [UInt8] = Array("()[]{}".utf8)
            for _ in 0..<rng.pick(1...200) { bytes.insert(brackets[rng.pick(0...5)], at: position()) }
        case 4:   // a NUL or a control byte
            bytes.insert(rng.byte(0...8), at: position())
        case 5:   // a long run of one byte
            let run = [UInt8](repeating: [0x28, 0x3D, 0x41, 0x0A, 0x2B, 0x3B, 0xFF][rng.pick(0...6)],
                              count: rng.pick(1...1_000_000))
            bytes.insert(contentsOf: run, at: position())
        case 6:   // random bytes of a random length
            bytes = (0..<rng.pick(0...4_096)).map { _ in rng.byte() }
        case 7:   // delete a range
            let from = position()
            bytes.removeSubrange(from..<min(bytes.count, from + rng.pick(1...400)))
        case 8:   // swap two halves
            let cut = position()
            bytes = Array(bytes[cut...]) + Array(bytes[..<cut])
        default:  // deep nesting inside an equation
            let depth = rng.pick(1...5_000)
            let line = Array("per_frame_3=q1 = \(String(repeating: "(", count: depth))1\(String(repeating: ")", count: depth));\n".utf8)
            bytes += line
        }
        return bytes
    }

    func testEveryVariantIsHandledAndTheLibraryStaysConsistent() async throws {
        let folder = try F.tempDirectory(self)
        let directory = try F.tempDirectory(self).appendingPathComponent("UserPresets")
        let library = UserPresetLibrary(directory: directory)
        await library.load()
        await library.setTrial(FakeTrial())
        let base = Array(F.preset(warp: F.warpShader, comp: F.compShader,
                                  extra: ["wave_0_per_point1=x = 0.5 + 0.3*sin(sample*6.28);", "shape_0_per_frame1=ang = time;"]).utf8)
        _ = await library.importFile(at: try F.write(Data(base), named: "base.milk", in: folder))

        var rng = Generator(state: 0x5EED_0012)
        var counts = ["added": 0, "quarantined": 0, "refused": 0]
        var slowest = 0.0
        for index in 0..<Self.variants {
            let variant = mutate(base, index, &rng)
            let started = Date()
            let validation = MilkdropPresetValidator.validate(variant, knownTextures: [])
            let elapsed = Date().timeIntervalSince(started)
            slowest = max(slowest, elapsed)
            // A hang guard, not a speed target: the slowest variant takes about 0.2 s on the Mac
            // Studio but up to 7 s in a Debug build on CI's xcode-27 simulator (run 43349673457),
            // so a 1 s wall-clock limit failed there without any defect. The speed is reported below.
            XCTAssertLessThan(elapsed, 10.0, "variant \(index) (\(variant.count) bytes) looks hung")

            let before = F.snapshot(directory)
            let playableBefore = await library.snapshot.playable.map(\.id)
            let url = try F.write(Data(variant), named: "variant \(index).milk", in: folder)
            let outcome = await library.importFile(at: url)
            try FileManager.default.removeItem(at: url)
            let after = F.snapshot(directory)
            switch outcome {
            case .refused:
                counts["refused", default: 0] += 1
                XCTAssertEqual(after, before, "variant \(index): a refusal changed the library")
            case .quarantined(let preset):
                counts["quarantined", default: 0] += 1
                XCTAssertNotNil(validation.rejection, "variant \(index)")
                let playableAfter = await library.snapshot.playable.map(\.id)
                XCTAssertEqual(playableAfter, playableBefore, "variant \(index)")
                XCTAssertEqual(after.filter { $0.key.hasPrefix("/files/") }, before.filter { $0.key.hasPrefix("/files/") }, "variant \(index)")
                XCTAssertEqual(after["/quarantine/\(preset.fileName)"], Data(variant), "variant \(index)")
                let data = await library.data(for: preset.id)
                XCTAssertNil(data, "variant \(index)")
                // Keep the quarantine below its limit so later variants are judged, not refused.
                let removed = await library.remove(preset.id)
                XCTAssertTrue(removed)
            case .added(let preset):
                counts["added", default: 0] += 1
                XCTAssertNil(validation.rejection, "variant \(index)")
                let removed = await library.remove(preset.id)
                XCTAssertTrue(removed)
            case .waiting:
                XCTFail("variant \(index): the fake trial always answers")
            }
        }
        let final = await library.snapshot
        XCTAssertEqual(final.playable.map(\.name), ["base"])
        XCTAssertEqual(final.quarantined, [])
        XCTAssertEqual(counts.values.reduce(0, +), Self.variants)
        // The same seed gives the same sweep: these counts are part of the test.
        print("PRE-012 sweep: \(counts.sorted { $0.key < $1.key }), slowest validation \(String(format: "%.3f", slowest)) s")
        XCTAssertEqual(counts, Self.expectedCounts)
    }

    /// Recorded from the first run; a change means the generator or the validator changed.
    static let expectedCounts: [String: Int] = ["added": 98, "quarantined": 468, "refused": 34]
}
