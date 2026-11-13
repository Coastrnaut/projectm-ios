// OSC-001-T03: the bounded OSC decoder (OSC-001-R8 to R11; contract C1; research OSC-001-D3, D4).
// OSC-002-T14: regression suite; only the `,s` case changed (strings are supported since OSC-002).
@testable import PerformanceControl
import XCTest

final class OSCDecoderTests: XCTestCase {
    /// `s` null-terminated and zero-padded to a multiple of 4.
    private func padded(_ s: String) -> [UInt8] {
        var bytes = Array(s.utf8) + [0]
        while bytes.count % 4 != 0 { bytes.append(0) }
        return bytes
    }

    private func floatBytes(_ f: Float) -> [UInt8] {
        let bits = f.bitPattern
        return [UInt8(bits >> 24 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits & 0xFF)]
    }

    private func intBytes(_ i: Int32) -> [UInt8] { floatBytes(Float(bitPattern: UInt32(bitPattern: i))) }

    private func expectError(_ bytes: [UInt8], _ expected: OSCDecodeError, file: StaticString = #filePath, line: UInt = #line) {
        switch OSCDecoder.decode(bytes) {
        case .success(let m): XCTFail("accepted \(m)", file: file, line: line)
        case .failure(let e): XCTAssertEqual(e, expected, file: file, line: line)
        }
    }

    // MARK: Accepted

    func testFloatMessageMatchesHandWrittenBytes() throws {
        let bytes = padded("/projectm/test") + padded(",f") + floatBytes(0.42)
        let message = try OSCDecoder.decode(bytes).get()
        XCTAssertEqual(message, OSCMessage(address: "/projectm/test", arguments: [.float(0.42)]))
        XCTAssertEqual(OSCEncoder.encode(message), bytes)
    }

    func testIntAndMixedArgumentsRoundTrip() throws {
        let messages = [
            OSCMessage(address: "/a", arguments: [.int(1)]),
            OSCMessage(address: "/a/b", arguments: [.int(-7), .float(3.5), .int(Int32.max)]),
            OSCMessage(address: "/zero", arguments: []),
            OSCMessage(address: "/sixteen", arguments: Array(repeating: .float(1), count: 16)),
        ]
        for m in messages {
            XCTAssertEqual(try OSCDecoder.decode(OSCEncoder.encode(m)).get(), m)
        }
        XCTAssertEqual(OSCArgument.int(-7).numericValue, -7)
        XCTAssertEqual(OSCArgument.float(0.5).numericValue, 0.5)
    }

    func testAddressOfMaximumLengthIsAccepted() throws {
        let address = "/" + String(repeating: "a", count: OSCLimits.maximumAddressBytes - 1)
        let m = OSCMessage(address: address, arguments: [.float(1)])
        XCTAssertEqual(try OSCDecoder.decode(OSCEncoder.encode(m)).get(), m)
    }

    // MARK: Rejected (OSC-001-R9)

    func testOversizedIsRejectedFirst() {
        expectError([UInt8](repeating: 0, count: OSCLimits.maximumDatagramBytes + 4),
                    .oversized(byteCount: OSCLimits.maximumDatagramBytes + 4))
    }

    func testEmptyAndUnaligned() {
        expectError([], .empty)
        expectError(Array("/ab".utf8) + [0, 0], .notAligned)
    }

    func testUnterminatedAndBadPadding() {
        expectError(Array("/abc".utf8), .unterminatedString)                     // no terminator at all
        expectError(padded("/a") + Array(",fff".utf8), .unterminatedString)       // type tags never end
        var bad = padded("/a") + padded(",f") + floatBytes(1)
        bad[3] = 0x41   // "/a\0A": padding byte not zero
        expectError(bad, .badPadding)
    }

    func testInvalidAddresses() {
        expectError(padded("noslash") + padded(",f") + floatBytes(1), .invalidAddress)
        expectError(padded("/a b") + padded(",f") + floatBytes(1), .invalidAddress)          // space
        expectError([0x2F, 0xC3, 0xA9, 0] + padded(",f") + floatBytes(1), .invalidAddress)   // "/é"
        let long = "/" + String(repeating: "a", count: OSCLimits.maximumAddressBytes)
        expectError(padded(long) + padded(",f") + floatBytes(1), .invalidAddress)
    }

    /// The message-only entry point keeps OSC-001's contract (OSC-002-R11); `decodePacket` decodes bundles.
    func testBundleIsUnsupported() {
        expectError(padded("#bundle") + [UInt8](repeating: 0, count: 8), .bundleUnsupported)
    }

    func testMissingTypeTagsAndUnsupportedTag() {
        expectError(padded("/a"), .missingTypeTags)                                // nothing after the address
        expectError(padded("/a") + padded("f") + floatBytes(1), .missingTypeTags)  // no comma
        // OSC-002 accepts `s`; `c` (character) is still unsupported.
        expectError(padded("/a") + padded(",c") + intBytes(65), .unsupportedTypeTag(UInt8(ascii: "c")))
    }

    func testTooManyArguments() {
        let tags = "," + String(repeating: "f", count: OSCLimits.maximumArguments + 1)
        var bytes = padded("/a") + padded(tags)
        for _ in 0...OSCLimits.maximumArguments { bytes += floatBytes(1) }
        expectError(bytes, .tooManyArguments)
    }

    func testTruncatedAndTrailing() {
        expectError(padded("/a") + padded(",ff") + floatBytes(1), .truncatedArgument)
        expectError(padded("/a") + padded(",f") + floatBytes(1) + floatBytes(2), .trailingBytes)
    }

    func testEveryReasonHasADistinctStableKey() {
        let errors: [OSCDecodeError] = [.oversized(byteCount: 2000), .empty, .notAligned, .unterminatedString, .badPadding,
                                        .invalidAddress, .missingTypeTags, .tooManyArguments, .unsupportedTypeTag(0x73),
                                        .truncatedArgument, .trailingBytes, .bundleUnsupported,
                                        .invalidString, .invalidBlobSize, .truncatedBundle, .invalidElementSize,
                                        .bundleTooDeep, .tooManyElements]
        XCTAssertEqual(Set(errors.map(\.reason)).count, errors.count)
        // OSC-001's keys are stable (OSC-002-R8).
        XCTAssertEqual(errors.prefix(12).map(\.reason),
                       ["oversized", "empty", "notAligned", "unterminatedString", "badPadding", "invalidAddress",
                        "missingTypeTags", "tooManyArguments", "unsupportedTypeTag", "truncatedArgument",
                        "trailingBytes", "bundleUnsupported"])
    }

    // MARK: Fuzz (research OSC-001-D4; OSC-001-S3)

    func testFixedSeedFuzzNeverCrashesAndAcceptsOnlyWellFormedPackets() {
        var rng = SplitMix64(seed: 0x05C0_0001)
        let seeds: [[UInt8]] = [
            OSCEncoder.encode(OSCMessage(address: "/projectm/test", arguments: [.float(0.42)])),
            OSCEncoder.encode(OSCMessage(address: "/a/b/c", arguments: [.int(3), .float(-1), .int(0)])),
            OSCEncoder.encode(OSCMessage(address: "/x", arguments: [])),
        ]
        var accepted = 0
        for i in 0..<20_000 {
            var packet: [UInt8]
            switch i % 3 {
            case 0:
                let count = Int(rng.next() % 65)
                packet = (0..<count).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            case 1:
                packet = seeds[Int(rng.next() % UInt64(seeds.count))]
                for _ in 0...(rng.next() % 3) {
                    packet[Int(rng.next() % UInt64(packet.count))] = UInt8(truncatingIfNeeded: rng.next())
                }
            default:
                let seed = seeds[Int(rng.next() % UInt64(seeds.count))]
                packet = Array(seed.prefix(Int(rng.next() % UInt64(seed.count))))
            }
            if case .success(let message) = OSCDecoder.decode(packet) {
                accepted += 1
                XCTAssertEqual(OSCEncoder.encode(message), packet, "accepted packet \(i) is not canonical")
            }
        }
        XCTAssertGreaterThan(accepted, 0, "mutations that keep a packet valid should be accepted")
    }
}

/// A tiny deterministic generator (SplitMix64), so the fuzz corpus is the same on every run and host.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
