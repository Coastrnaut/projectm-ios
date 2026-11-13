// CorpusGeneratorTests.swift — regenerates the OSC and generator-graph seed corpus from the
// repository's own encoders and examples (QA-005-T07; research QA-005-D6). It writes only when
// `QA005_WRITE_CORPUS` names a directory; otherwise it checks that the checked-in files still equal
// what the encoders produce, so a format change shows up here.
//
// The other corpus files were produced once and checked in: scene and archive files from the SCN-001
// and FILE-001 test fixtures (`SceneFixtures.allKinds`, `ArchiveFixtures.archive`, …), and preset,
// expression and JSON text authored for this feature.
import Foundation
import FuzzKit
import GeneratorGraph
import PerformanceControl
import XCTest

final class CorpusGeneratorTests: XCTestCase {
    static func oscItems() -> [(String, [UInt8])] {
        let address = OSCReceiverCatalog.testAddress
        let float = OSCMessage(address: address, arguments: [.float(0.5)])
        let mixed = OSCMessage(address: "/projectm/mixed", arguments: [.int(-7), .string("hello"), .blob([1, 2, 3, 4, 5]),
                                                                       .int64(-1), .double(0.25), .true, .false, .nil, .impulse])
        let inner = OSCPacket.bundle(OSCBundle(timeTag: .immediately, elements: [.message(float)]))
        let nested = OSCPacket.bundle(OSCBundle(timeTag: OSCTimeTag(seconds: 3_900_000_000, fraction: 7),
                                                elements: [inner, .message(OSCMessage(address: address, arguments: [.int(1)]))]))
        return [
            ("float.osc", OSCEncoder.encode(float)),
            ("int.osc", OSCEncoder.encode(OSCMessage(address: address, arguments: [.int(1)]))),
            ("mixed.osc", OSCEncoder.encode(mixed)),
            ("no-arguments.osc", OSCEncoder.encode(OSCMessage(address: "/a", arguments: []))),
            ("nested-bundle.osc", OSCEncoder.encode(nested)),
        ]
    }

    static func graphItems() throws -> [(String, [UInt8])] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        var items: [(String, [UInt8])] = []
        for (i, document) in GeneratorGraphExamples.all.enumerated() {
            items.append(("example-\(i + 1).json", [UInt8](try encoder.encode(document))))
        }
        return items
    }

    func testGeneratedCorpusIsCurrent() throws {
        let generated: [(String, [(String, [UInt8])])] = [("osc", Self.oscItems()), ("graph", try Self.graphItems())]
        if let target = ProcessInfo.processInfo.environment["QA005_WRITE_CORPUS"], !target.isEmpty {
            for (format, items) in generated {
                let dir = URL(fileURLWithPath: target).appendingPathComponent(format, isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for (name, bytes) in items { try Data(bytes).write(to: dir.appendingPathComponent(name)) }
            }
            return
        }
        for (format, items) in generated {
            let corpus = FuzzCorpora.load(format)
            for (name, bytes) in items {
                guard let index = corpus.fileNames.firstIndex(of: name) else {
                    XCTFail("\(format)/\(name) is missing; regenerate with QA005_WRITE_CORPUS")
                    continue
                }
                XCTAssertEqual(corpus.items[index], bytes, "\(format)/\(name) differs from the encoder's output")
            }
        }
    }
}
