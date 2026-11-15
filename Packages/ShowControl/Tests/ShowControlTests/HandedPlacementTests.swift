// HandedPlacementTests.swift — ACC-010-T03 (specs/248-acc-010-left-handed-layout, contract C1; S1, R3, R5, R6):
// in every arrangement and a few representative sizes, left-handed frames are the horizontal mirror of right-handed
// ones (within 1 pt), the cue pair keeps its reading order, and the identifier set is the same.
import XCTest
@testable import ShowControl

final class HandedPlacementTests: XCTestCase {
    /// (width, height, regular) per arrangement: phone portrait (bar), narrow portrait (grid), phone and iPad landscape.
    private static let cases: [(Double, Double, Bool, PerformanceLayout.Arrangement)] = [
        (402, 778, false, .bottomBar), (440, 870, false, .bottomBar), (834, 1150, true, .bottomBar),
        (250, 600, false, .bottomGrid), (280, 500, false, .bottomGrid), (300, 640, true, .bottomGrid),
        (778, 361, false, .sideColumns), (956, 419, false, .sideColumns), (1366, 980, true, .sideColumns),
    ]

    private func mirror(_ r: OneHandedLayout.Rect, width: Double) -> OneHandedLayout.Rect {
        OneHandedLayout.Rect(x: width - r.maxX, y: r.y, width: r.width, height: r.height)
    }

    private func union(_ a: OneHandedLayout.Rect, _ b: OneHandedLayout.Rect) -> OneHandedLayout.Rect {
        let x: Double = min(a.x, b.x), y: Double = min(a.y, b.y)
        return OneHandedLayout.Rect(x: x, y: y, width: max(a.maxX, b.maxX) - x, height: max(a.maxY, b.maxY) - y)
    }

    private func assertClose(_ a: OneHandedLayout.Rect, _ b: OneHandedLayout.Rect, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let close: Bool = abs(a.x - b.x) <= 1 && abs(a.y - b.y) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
        XCTAssertTrue(close, "\(message): \(a) vs \(b)", file: file, line: line)
    }

    func testLeftHandedFramesMirrorRightHandedFrames() throws {
        for (width, height, regular, expected) in Self.cases {
            let layout = PerformanceLayout(width: width, height: height, regular: regular)
            XCTAssertEqual(layout.arrangement, expected, "\(width)×\(height)")
            let right = layout.targetFrames(width: width, height: height, side: .right, readoutHeight: 40)
            let left = layout.targetFrames(width: width, height: height, side: .left, readoutHeight: 40)
            let label = "\(expected) \(width)×\(height)"
            XCTAssertEqual(Set(right.keys), Set(PadTarget.allCases), label)
            XCTAssertEqual(Set(left.keys), Set(right.keys), "identical targets: \(label)")
            XCTAssertEqual(Set(left.keys.map(\.identifier)), Set(right.keys.map(\.identifier)), "identical identifiers: \(label)")
            for target in [PadTarget.tapTempo, .blackout] {
                assertClose(try XCTUnwrap(left[target]), mirror(try XCTUnwrap(right[target]), width: width), "\(target) \(label)")
            }
            let rightCue = union(try XCTUnwrap(right[.previousCue]), try XCTUnwrap(right[.nextCue]))
            let leftCue = union(try XCTUnwrap(left[.previousCue]), try XCTUnwrap(left[.nextCue]))
            assertClose(leftCue, mirror(rightCue, width: width), "cue pair \(label)")
            let previous = try XCTUnwrap(left[.previousCue]), next = try XCTUnwrap(left[.nextCue])
            if expected == .sideColumns {
                XCTAssertLessThan(previous.y, next.y, "Previous cue above Next cue: \(label)")
            } else {
                XCTAssertLessThan(previous.x, next.x, "Previous cue left of Next cue: \(label)")
            }
            XCTAssertNotEqual(left[.blackout], right[.blackout], "positions swap: \(label)")
        }
    }

    func testPlacementsAndReadouts() {
        let bar = PerformanceLayout(width: 402, height: 778, regular: false)
        XCTAssertEqual(bar.placement(.right).rows, [[.previousCue, .nextCue, .tapTempo, .blackout]])
        XCTAssertEqual(bar.placement(.left).rows, [[.blackout, .tapTempo, .previousCue, .nextCue]])
        XCTAssertTrue(bar.placement(.right).cueReadoutLeading)
        XCTAssertFalse(bar.placement(.left).cueReadoutLeading, "readouts follow their groups")
        let grid = PerformanceLayout(width: 250, height: 600, regular: false)
        XCTAssertEqual(grid.placement(.left).rows, [[.previousCue, .nextCue], [.blackout, .tapTempo]])
        let columns = PerformanceLayout(width: 778, height: 361, regular: false)
        XCTAssertEqual(columns.placement(.left).leadingColumn, [.tapTempo, .blackout])
        XCTAssertEqual(columns.placement(.left).trailingColumn, [.previousCue, .nextCue])
        XCTAssertEqual(columns.placement(.left).mirrored, columns.placement(.right), "mirroring twice is the identity")
    }

    func testSideResolution() {
        XCTAssertEqual(ControlsSide.resolve(oneHanded: nil, leftHanded: false), .right)
        XCTAssertEqual(ControlsSide.resolve(oneHanded: nil, leftHanded: true), .left)
        XCTAssertEqual(ControlsSide.resolve(oneHanded: .right, leftHanded: true), .right, "one-handed decides (R6)")
        XCTAssertEqual(ControlsSide.resolve(oneHanded: .left, leftHanded: false), .left)
    }

    func testIdentifiersMatchUIX005() {
        XCTAssertEqual(PadTarget.allCases.map(\.identifier), ["perfPreviousCue", "perfNextCue", "perfTapTempo", "perfBlackout"])
        let critical: [String?] = [CriticalAction.cuePrevious, .cueNext, .tapTempo, .blackout].map(\.padIdentifier)
        XCTAssertEqual(PadTarget.allCases.map(\.identifier), critical.compactMap { $0 }, "the same identifiers as ACC-009's pad actions")
    }
}
