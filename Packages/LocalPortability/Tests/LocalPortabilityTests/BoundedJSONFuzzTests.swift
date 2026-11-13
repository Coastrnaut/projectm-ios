// FILE-007-T04 (FILE-007-S3): a fixed-seed fuzz of BoundedJSON. Mutated documents never crash the
// validator and only ever produce success or a typed error whose offset lies inside the input; every
// accepted input is also accepted by the platform's JSON parser (the validator is never looser).
import XCTest
import LocalPortability

final class BoundedJSONFuzzTests: XCTestCase {
    /// SplitMix64: deterministic on every platform.
    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    /// Seeds use small numbers without exponents, so no mutation can build a number the platform
    /// parser refuses as unrepresentable.
    private let seeds: [String] = [
        "{\"format\":\"org.example\",\"formatVersion\":1,\"files\":[{\"path\":\"a.txt\",\"sha256\":\"00ff\",\"byteCount\":12}]}",
        "{\"a\":[1,2,{\"b\":null,\"c\":true}],\"d\":\"x\\\"y\\u00e9\",\"e\":-0.5}",
        "[[],{},[[\"\u{00E9}\u{20AC}\"]],false]",
        "{\"k\":\"\\uD83D\\uDE00\",\"n\":[0,10,-3.25]}",
    ]

    /// Bytes a mutation inserts: JSON punctuation, digits, letters, escapes and some invalid UTF-8.
    private let alphabet: [UInt8] = Array("{}[]\":,\\ \n0123456789-.+tfnula/".utf8) + [0x00, 0x1F, 0x7F, 0x80, 0xC0, 0xC3, 0xA9, 0xED, 0xF4, 0xFF]

    private func mutate(_ input: [UInt8], _ rng: inout Generator) -> [UInt8] {
        var bytes = input
        let edits = 1 + rng.below(4)
        for _ in 0..<edits {
            switch rng.below(5) {
            case 0 where !bytes.isEmpty:
                bytes[rng.below(bytes.count)] = alphabet[rng.below(alphabet.count)]
            case 1:
                bytes.insert(alphabet[rng.below(alphabet.count)], at: rng.below(bytes.count + 1))
            case 2 where !bytes.isEmpty:
                bytes.remove(at: rng.below(bytes.count))
            case 3 where bytes.count > 1:
                // Duplicate a slice somewhere else (builds nesting and repeated keys).
                let start = rng.below(bytes.count)
                let length = 1 + rng.below(min(16, bytes.count - start))
                let slice = Array(bytes[start..<(start + length)])
                bytes.insert(contentsOf: slice, at: rng.below(bytes.count + 1))
            default:
                if !bytes.isEmpty { bytes.removeLast(rng.below(min(3, bytes.count) + 1)) }
            }
        }
        return bytes
    }

    func testFixedSeedFuzzReturnsOnlyTypedResults() throws {
        let limits = JSONLimits(maxBytes: 4_096, maxDepth: 6, maxStringBytes: 64, maxNumberBytes: 12, maxElements: 16,
                                rejectsDuplicateKeys: true, requiresObjectRoot: false)
        var rng = Generator(state: 0x0F11_E007)
        var accepted = 0
        var refused = 0
        for iteration in 0..<2_500 {
            let seed = Array(seeds[iteration % seeds.count].utf8)
            let input = mutate(seed, &rng)
            let outcome = BoundedJSON.check(input, limits: limits)
            XCTAssertLessThanOrEqual(outcome.bytesExamined, input.count)
            switch outcome.result {
            case .success(let summary):
                accepted += 1
                XCTAssertEqual(summary.bytesExamined, input.count)
                XCTAssertLessThanOrEqual(summary.deepest, limits.maxDepth)
                XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(input), options: [.fragmentsAllowed]),
                                 "accepted but the platform parser refuses: \(String(decoding: input, as: UTF8.self))")
            case .failure(let error):
                refused += 1
                XCTAssertGreaterThanOrEqual(error.offset, 0)
                XCTAssertLessThanOrEqual(error.offset, input.count)
            }
        }
        XCTAssertEqual(accepted + refused, 2_500)
        XCTAssertGreaterThan(accepted, 50, "the fuzz must exercise the accepting path too")
        XCTAssertGreaterThan(refused, 500, "the fuzz must exercise refusals")
    }
}
