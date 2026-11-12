// PlayOrderTests.swift — the play order behind Next and Previous (AUD-006-T11; AUD-006-R14 to R16).
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class PlayOrderTests: XCTestCase {
    private func item(_ id: String) -> PlaybackItem {
        PlaybackItem(id: id, title: "Track \(id)", durationSeconds: 10, track: .file(URL(fileURLWithPath: "/library/assets/\(id).wav")))
    }

    func testNextAndPreviousInTheMiddle() {
        let order = ListPlayOrder([item("a"), item("b"), item("c")])
        XCTAssertEqual(order.item(after: "a")?.id, "b")
        XCTAssertEqual(order.item(after: "b")?.id, "c")
        XCTAssertEqual(order.item(before: "c")?.id, "b")
        XCTAssertEqual(order.item(before: "b")?.id, "a")
    }

    func testBothEndsWrapAround() {
        let order = ListPlayOrder([item("a"), item("b"), item("c")])
        XCTAssertEqual(order.item(after: "c")?.id, "a")
        XCTAssertEqual(order.item(before: "a")?.id, "c")
    }

    func testOneItemIsItsOwnNeighbour() {
        let order = ListPlayOrder([item("only")])
        XCTAssertEqual(order.item(after: "only")?.id, "only")
        XCTAssertEqual(order.item(before: "only")?.id, "only")
    }

    func testUnknownIdStartsAtTheFirstItemAndEmptyHasNothing() {
        let order = ListPlayOrder([item("a"), item("b")])
        XCTAssertEqual(order.item(after: "gone")?.id, "a")
        XCTAssertEqual(order.item(before: "gone")?.id, "a")
        XCTAssertNil(ListPlayOrder([]).item(after: "a"))
        XCTAssertNil(ListPlayOrder([]).item(before: "a"))
        XCTAssertEqual(order.items.map(\.id), ["a", "b"])
    }

    func testReferenceItem() {
        let reference = PlaybackItem.reference(title: "Reference track", durationSeconds: 60)
        XCTAssertEqual(reference.id, PlaybackItem.referenceID)
        XCTAssertEqual(reference.track, .reference)
        XCTAssertEqual(reference.title, "Reference track")
    }
}
