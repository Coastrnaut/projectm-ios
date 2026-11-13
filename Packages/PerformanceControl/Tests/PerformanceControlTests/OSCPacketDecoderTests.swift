// OSC-002-T08, T12, T13: the packet decoder — valid fixtures, the malformed table and a fixed-seed
// structure-aware fuzz (OSC-002-R1 to R9, S1 to S3; contract P1, P2; research OSC-002-D7).
// "Malformed packet is rejected without crash or unbounded allocation."
@testable import PerformanceControl
import XCTest

final class OSCPacketDecoderTests: XCTestCase {
    // MARK: Byte helpers

    private func padded(_ s: String) -> [UInt8] { padded(Array(s.utf8)) }

    private func padded(_ bytes: [UInt8]) -> [UInt8] {
        var out = bytes + [0]
        while out.count % 4 != 0 { out.append(0) }
        return out
    }

    private func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(truncatingIfNeeded: v >> 24), UInt8(truncatingIfNeeded: v >> 16),
         UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)]
    }

    private func be64(_ v: UInt64) -> [UInt8] {
        be32(UInt32(truncatingIfNeeded: v >> 32)) + be32(UInt32(truncatingIfNeeded: v))
    }

    /// `#bundle`, the time tag, then each element with its size word.
    private func bundle(_ timeTag: UInt64 = 1, _ elements: [[UInt8]]) -> [UInt8] {
        var out = padded("#bundle") + be64(timeTag)
        for e in elements { out += be32(UInt32(e.count)) + e }
        return out
    }

    /// The smallest message: `/a` with no arguments (8 bytes).
    private var tiny: [UInt8] { padded("/a") + padded(",") }

    private func expectPacketError(_ bytes: [UInt8], _ expected: OSCDecodeError, _ label: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        switch OSCDecoder.decodePacket(bytes) {
        case .success(let p): XCTFail("\(label): accepted \(p)", file: file, line: line)
        case .failure(let e): XCTAssertEqual(e, expected, label, file: file, line: line)
        }
    }

    // MARK: Valid fixtures (OSC-002-S3)

    func testEveryArgumentTypeDecodesExactlyFromHandWrittenBytes() throws {
        let bytes: [UInt8] = padded("/all") + padded(",ifsbhdTFNI")
            + be32(UInt32(bitPattern: -2))                     // i
            + be32(Float(0.5).bitPattern)                      // f
            + [0x68, 0xC3, 0xA9, 0]                            // s "hé" (UTF-8), NUL
            + be32(3) + [1, 2, 3, 0]                           // b, one byte of padding
            + be64(UInt64(bitPattern: -5_000_000_000))         // h
            + be64(Double(0.25).bitPattern)                    // d
        let expected = OSCMessage(address: "/all", arguments: [
            .int(-2), .float(0.5), .string("hé"), .blob([1, 2, 3]), .int64(-5_000_000_000), .double(0.25),
            .true, .false, .nil, .impulse,
        ])
        XCTAssertEqual(try OSCDecoder.decodePacket(bytes).get(), .message(expected))
        XCTAssertEqual(try OSCDecoder.decode(bytes).get(), expected)
        XCTAssertEqual(OSCEncoder.encode(expected), bytes)
        XCTAssertEqual(expected.arguments.map { (a: OSCArgument) -> Double? in a.numericValue },
                       [-2, 0.5, nil, nil, -5_000_000_000, 0.25, nil, nil, nil, nil])
    }

    func testEmptyStringAndEmptyBlob() throws {
        let bytes = padded("/e") + padded(",sb") + [0, 0, 0, 0] + be32(0)
        let m = OSCMessage(address: "/e", arguments: [.string(""), .blob([])])
        XCTAssertEqual(try OSCDecoder.decodePacket(bytes).get(), .message(m))
        XCTAssertEqual(OSCEncoder.encode(m), bytes)
    }

    func testEmptyBundleIsValid() throws {
        let bytes = bundle(1, [])
        XCTAssertEqual(bytes.count, 16)
        let packet = try OSCDecoder.decodePacket(bytes).get()
        XCTAssertEqual(packet, .bundle(OSCBundle(timeTag: .immediately, elements: [])))
        XCTAssertTrue(OSCTimeTag.immediately.isImmediately)
        XCTAssertEqual(packet.messages, [])
        XCTAssertEqual(OSCEncoder.encode(packet), bytes)
    }

    func testNestedBundleDecodesInPacketOrderWithTimeTags() throws {
        let m1 = padded("/one") + padded(",f") + be32(Float(1).bitPattern)
        let m2 = padded("/two") + padded(",s") + padded("x")
        let m3 = padded("/three") + padded(",T")
        let inner = bundle(0xE6E1_0000_8000_0000, [m2])
        let bytes = bundle(0xE6E1_0000_0000_0000, [m1, inner, m3])
        let expected = OSCPacket.bundle(OSCBundle(timeTag: OSCTimeTag(seconds: 0xE6E1_0000, fraction: 0), elements: [
            .message(OSCMessage(address: "/one", arguments: [.float(1)])),
            .bundle(OSCBundle(timeTag: OSCTimeTag(seconds: 0xE6E1_0000, fraction: 0x8000_0000), elements: [
                .message(OSCMessage(address: "/two", arguments: [.string("x")])),
            ])),
            .message(OSCMessage(address: "/three", arguments: [.true])),
        ]))
        let packet = try OSCDecoder.decodePacket(bytes).get()
        XCTAssertEqual(packet, expected)
        XCTAssertEqual(packet.messages.map(\.address), ["/one", "/two", "/three"])
        XCTAssertEqual(OSCEncoder.encode(packet), bytes)
        // OSC-001's message-only entry point still refuses it (OSC-002-R11).
        XCTAssertEqual(OSCDecoder.decode(bytes), .failure(.bundleUnsupported))
    }

    func testLimitsThemselvesAreAccepted() throws {
        // Depth exactly 4.
        var nested = bundle(1, [tiny])
        for _ in 2...OSCLimits.maximumBundleDepth { nested = bundle(1, [nested]) }
        XCTAssertEqual(try OSCDecoder.decodePacket(nested).get().messages.count, 1)
        // Exactly 64 elements.
        let full = bundle(1, Array(repeating: tiny, count: OSCLimits.maximumBundleElements))
        XCTAssertEqual(try OSCDecoder.decodePacket(full).get().messages.count, 64)
        // 16 no-payload arguments.
        let sixteen = padded("/t") + padded("," + String(repeating: "T", count: 16))
        XCTAssertEqual(try OSCDecoder.decode(sixteen).get().arguments.count, 16)
    }

    // MARK: Malformed table (OSC-002-S1)

    func testTruncationAtEveryFourByteBoundaryOfARepresentativeMessage() {
        let full = padded("/t") + padded(",fsbd") + be32(Float(1).bitPattern) + padded("hi")
            + be32(2) + [7, 8, 0, 0] + be64(Double(2).bitPattern)
        XCTAssertEqual(full.count, 36)
        let expected: [Int: OSCDecodeError] = [
            0: .empty, 4: .missingTypeTags, 8: .unterminatedString, 12: .truncatedArgument,
            16: .unterminatedString, 20: .truncatedArgument, 24: .invalidBlobSize, 28: .truncatedArgument,
            32: .truncatedArgument,
        ]
        for cut in stride(from: 0, to: full.count, by: 4) {
            expectPacketError(Array(full.prefix(cut)), expected[cut]!, "cut at \(cut)")
        }
        XCTAssertNoThrow(try OSCDecoder.decodePacket(full).get())
    }

    func testTruncationAtEveryFourByteBoundaryOfARepresentativeBundle() throws {
        let m1 = padded("/one") + padded(",i") + be32(1)
        let m2 = padded("/two") + padded(",b") + be32(4) + [1, 2, 3, 4]
        let full = bundle(1, [m1, bundle(1, [m2])])
        let original = try OSCDecoder.decodePacket(full).get().messages
        // Below 8 bytes the marker is incomplete, so it is not a bundle (the message rules apply).
        for cut in stride(from: 8, to: full.count, by: 4) {
            switch OSCDecoder.decodePacket(Array(full.prefix(cut))) {
            case .failure(let e):
                XCTAssertTrue([.truncatedBundle, .invalidElementSize].contains(e), "cut at \(cut): \(e)")
                if cut < 16 { XCTAssertEqual(e, .truncatedBundle, "cut at \(cut)") }
            case .success(let p):
                // Only a cut exactly at an element boundary leaves a valid, shorter bundle.
                XCTAssertTrue([16, 16 + 4 + m1.count].contains(cut), "cut at \(cut) accepted \(p)")
                XCTAssertEqual(p.messages, Array(original.prefix(p.messages.count)))
            }
        }
    }

    func testMalformedStringsAndBlobs() {
        let head = padded("/a")
        let cases: [(String, [UInt8], OSCDecodeError)] = [
            ("misaligned string", head + padded(",s") + [0x68, 0x69, 0], .notAligned),
            ("missing null terminator", head + padded(",s") + Array("abcd".utf8), .unterminatedString),
            ("non-zero string padding", head + padded(",s") + [0x68, 0x69, 0, 0x58], .badPadding),
            ("invalid UTF-8 (bad continuation)", head + padded(",s") + [0xC3, 0x28, 0, 0], .invalidString),
            ("invalid UTF-8 (0xFF)", head + padded(",s") + [0xFF, 0, 0, 0], .invalidString),
            ("blob size word missing", head + padded(",b"), .truncatedArgument),
            ("negative blob size", head + padded(",b") + be32(0xFFFF_FFFF) + [0, 0, 0, 0], .invalidBlobSize),
            ("huge blob size", head + padded(",b") + be32(0x7FFF_FFFF) + [0, 0, 0, 0], .invalidBlobSize),
            ("Int32.min blob size", head + padded(",b") + be32(0x8000_0000), .invalidBlobSize),
            ("blob past the end", head + padded(",b") + be32(8) + [1, 2, 3, 4], .invalidBlobSize),
            ("blob padding past the end", head + padded(",b") + be32(5) + [1, 2, 3, 4], .invalidBlobSize),
            ("non-zero blob padding", head + padded(",b") + be32(1) + [7, 9, 0, 0], .badPadding),
            ("h truncated", head + padded(",h") + be32(1), .truncatedArgument),
            ("d truncated", head + padded(",d"), .truncatedArgument),
            ("unknown tag c", head + padded(",c") + be32(65), .unsupportedTypeTag(UInt8(ascii: "c"))),
            ("array tag", head + padded(",[i]") + be32(1), .unsupportedTypeTag(UInt8(ascii: "["))),
            ("17 no-payload arguments", head + padded("," + String(repeating: "N", count: 17)), .tooManyArguments),
            ("non-ASCII address", padded([0x2F, 0xC3, 0xA9]) + padded(","), .invalidAddress),
            ("trailing bytes", tiny + [0, 0, 0, 0], .trailingBytes),
            ("oversized", [UInt8](repeating: 0, count: OSCLimits.maximumDatagramBytes + 4),
             .oversized(byteCount: OSCLimits.maximumDatagramBytes + 4)),
        ]
        for (label, bytes, expected) in cases { expectPacketError(bytes, expected, label) }
    }

    func testMalformedBundles() {
        let nonASCII = padded([0x2F, 0xC3, 0xA9]) + padded(",")
        var tooDeep = bundle(1, [tiny])
        for _ in 1...OSCLimits.maximumBundleDepth { tooDeep = bundle(1, [tooDeep]) }
        let half = OSCLimits.maximumBundleElements / 2
        let cases: [(String, [UInt8], OSCDecodeError)] = [
            ("marker only", padded("#bundle"), .truncatedBundle),
            ("time tag cut", padded("#bundle") + be32(0), .truncatedBundle),
            ("misaligned bundle", bundle(1, [tiny]) + [0, 0], .notAligned),
            ("element size 0", bundle(1, []) + be32(0), .invalidElementSize),
            ("element size not a multiple of 4", bundle(1, []) + be32(6) + tiny, .invalidElementSize),
            ("element size past the end", bundle(1, []) + be32(12) + tiny, .invalidElementSize),
            ("negative element size", bundle(1, []) + be32(0xFFFF_FFF8) + tiny, .invalidElementSize),
            ("huge element size", bundle(1, []) + be32(0x7FFF_FFFC) + tiny, .invalidElementSize),
            ("element neither message nor bundle", bundle(1, [padded("abc") + padded(",")]), .invalidAddress),
            ("non-ASCII address in an element", bundle(1, [nonASCII]), .invalidAddress),
            ("element with trailing bytes", bundle(1, [tiny + [0, 0, 0, 0]]), .trailingBytes),
            ("nested bundle cut short", bundle(1, [padded("#bundle")]), .truncatedBundle),
            ("depth 5", tooDeep, .bundleTooDeep),
            ("65 elements", bundle(1, Array(repeating: tiny, count: OSCLimits.maximumBundleElements + 1)), .tooManyElements),
            ("65 elements across levels", bundle(1, [bundle(1, Array(repeating: tiny, count: half)),
                                                     bundle(1, Array(repeating: tiny, count: half - 1))]), .tooManyElements),
            ("one bad element among good ones", bundle(1, [tiny, padded("/b") + padded(",f"), tiny]), .truncatedArgument),
        ]
        for (label, bytes, expected) in cases { expectPacketError(bytes, expected, label) }
    }

    // MARK: Fuzz (OSC-002-S2, research OSC-002-D7)

    /// Bytes the decoded packet holds: addresses, strings, blobs and numbers. Copies only, so this
    /// can never exceed the datagram (the allocation bound, counted rather than profiled).
    private func payloadBytes(_ packet: OSCPacket) -> Int {
        packet.messages.reduce(0) { (sum: Int, m: OSCMessage) -> Int in
            sum + m.address.utf8.count + m.arguments.reduce(0) { (s: Int, a: OSCArgument) -> Int in
                switch a {
                case .float, .int: s + 4
                case .int64, .double: s + 8
                case .string(let t): s + t.utf8.count
                case .blob(let b): s + b.count
                case .true, .false, .nil, .impulse: s
                }
            }
        }
    }

    private func depth(_ packet: OSCPacket) -> Int {
        guard case .bundle(let b) = packet else { return 0 }
        return 1 + b.elements.map { (e: OSCPacket) -> Int in depth(e) }.reduce(0, max)
    }

    private func elementCount(_ packet: OSCPacket) -> Int {
        guard case .bundle(let b) = packet else { return 0 }
        return b.elements.count + b.elements.map { (e: OSCPacket) -> Int in elementCount(e) }.reduce(0, +)
    }

    /// A random packet: messages with every type, bundles nested up to `maxDepth`.
    private func randomPacket(_ rng: inout SplitMix64, depth: Int, maxDepth: Int) -> OSCPacket {
        if depth < maxDepth && rng.next() % 3 == 0 {
            let count = Int(rng.next() % 4)
            var elements: [OSCPacket] = []
            for _ in 0..<count { elements.append(randomPacket(&rng, depth: depth + 1, maxDepth: maxDepth)) }
            return .bundle(OSCBundle(timeTag: OSCTimeTag(rawValue: rng.next() % 3 == 0 ? 1 : rng.next()), elements: elements))
        }
        let letters = Array("abcxyz/09_".utf8)
        var address: [UInt8] = [UInt8(ascii: "/")]
        for _ in 0..<Int(rng.next() % 12) { address.append(letters[Int(rng.next() % UInt64(letters.count))]) }
        var arguments: [OSCArgument] = []
        for _ in 0..<Int(rng.next() % 5) {
            switch rng.next() % 10 {
            case 0: arguments.append(.float(Float(bitPattern: UInt32(truncatingIfNeeded: rng.next()))))
            case 1: arguments.append(.int(Int32(truncatingIfNeeded: rng.next())))
            case 2: arguments.append(.int64(Int64(bitPattern: rng.next())))
            case 3: arguments.append(.double(Double(bitPattern: rng.next())))
            case 4: arguments.append(.string(String(repeating: "é", count: Int(rng.next() % 4)) + "s"))
            case 5: arguments.append(.blob((0..<Int(rng.next() % 7)).map { (_: Int) -> UInt8 in UInt8(truncatingIfNeeded: rng.next()) }))
            case 6: arguments.append(.true)
            case 7: arguments.append(.false)
            case 8: arguments.append(.nil)
            default: arguments.append(.impulse)
            }
        }
        return .message(OSCMessage(address: String(decoding: address, as: UTF8.self), arguments: arguments))
    }

    func testStructureAwareFuzzNeverCrashesAndStaysBounded() {
        var rng = SplitMix64(seed: 0x05C0_0002)
        var seeds: [[UInt8]] = []
        for _ in 0..<24 { seeds.append(OSCEncoder.encode(randomPacket(&rng, depth: 0, maxDepth: 4))) }
        let interesting: [UInt32] = [0, 4, 8, 0xFFFF_FFFF, 0xFFFF_FFFC, 0x7FFF_FFFF, 0x8000_0000, 1472]
        var accepted = 0, acceptedBundles = 0, rejected = 0
        var reasons: Set<String> = []
        for i in 0..<24_000 {
            var packet: [UInt8]
            var generated: OSCPacket?
            switch i % 5 {
            case 0:     // random bytes, sometimes behind a bundle marker
                let count = Int(rng.next() % 97)
                packet = (0..<count).map { (_: Int) -> UInt8 in UInt8(truncatingIfNeeded: rng.next()) }
                if rng.next() % 2 == 0 { packet = padded("#bundle") + packet }
            case 1:     // byte mutations of a valid packet
                packet = seeds[Int(rng.next() % UInt64(seeds.count))]
                for _ in 0...(rng.next() % 3) where !packet.isEmpty {
                    packet[Int(rng.next() % UInt64(packet.count))] = UInt8(truncatingIfNeeded: rng.next())
                }
            case 2:     // truncation
                let seed = seeds[Int(rng.next() % UInt64(seeds.count))]
                packet = Array(seed.prefix(Int(rng.next() % UInt64(seed.count + 1))))
            case 3:     // a size-like word at an aligned offset (blob and element sizes live there)
                packet = seeds[Int(rng.next() % UInt64(seeds.count))]
                let words = packet.count / 4
                if words > 0 {
                    let at = Int(rng.next() % UInt64(words)) * 4
                    let old = UInt32(packet[at]) << 24 | UInt32(packet[at + 1]) << 16 | UInt32(packet[at + 2]) << 8 | UInt32(packet[at + 3])
                    let choice = rng.next() % 10
                    let value: UInt32 = choice < 8 ? interesting[Int(choice)] : (choice == 8 ? old &+ 4 : old &- 4)
                    packet.replaceSubrange(at..<(at + 4), with: be32(value))
                }
            default:    // freshly generated, nesting up to 6 (past the limit of 4)
                let p = randomPacket(&rng, depth: 0, maxDepth: 6)
                generated = p
                packet = OSCEncoder.encode(p)
            }

            switch OSCDecoder.decodePacket(packet) {
            case .success(let decoded):
                accepted += 1
                if case .bundle = decoded { acceptedBundles += 1 }
                XCTAssertEqual(OSCEncoder.encode(decoded), packet, "packet \(i) is not canonical")
                XCTAssertLessThanOrEqual(payloadBytes(decoded), packet.count, "packet \(i) payload exceeds datagram")
                XCTAssertLessThanOrEqual(depth(decoded), OSCLimits.maximumBundleDepth, "packet \(i)")
                XCTAssertLessThanOrEqual(elementCount(decoded), OSCLimits.maximumBundleElements, "packet \(i)")
                if let generated { XCTAssertEqual(decoded, generated, "packet \(i)") }
            case .failure(let error):
                rejected += 1
                reasons.insert(error.reason)
                if let generated, packet.count <= OSCLimits.maximumDatagramBytes,
                   depth(generated) <= OSCLimits.maximumBundleDepth,
                   elementCount(generated) <= OSCLimits.maximumBundleElements {
                    XCTFail("valid generated packet \(i) rejected as \(error)")
                }
            }
        }
        XCTAssertGreaterThan(accepted, 1000)
        XCTAssertGreaterThan(acceptedBundles, 100)
        XCTAssertGreaterThan(rejected, 1000)
        for reason in ["invalidBlobSize", "invalidElementSize", "bundleTooDeep", "truncatedBundle", "invalidString"] {
            XCTAssertTrue(reasons.contains(reason), "the fuzz never produced \(reason): \(reasons.sorted())")
        }
    }
}
