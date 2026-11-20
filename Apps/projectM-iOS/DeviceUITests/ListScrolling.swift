// ListScrolling.swift — one scroll step of an app list (Settings and its pushed screens) that always starts and ends
// inside the list's visible area, well away from the screen's edges.
//
// QA-011 pass 6 D2 (iPad Pro M5, 2026-11-19): `swipeUp()`/`swipeDown()` on the Settings panel's CollectionView, which
// is as tall as the screen ({{632, 0}, {400, 1376}}), leave the start point to XCUITest; one prompt-flow test ended on
// the Home Screen after such swipes. A drag that starts near the bottom edge is the system's Home gesture, and one at
// the top edge pulls down Notification Centre, so every step here keeps at least 15 % of the list's height (and
// 120 pt at the top, 100 pt at the bottom) clear of its edges, in the list's right-hand margin (a drag through a
// slider's thumb mid-row moves the slider; the left edge is the navigation back gesture).
import XCTest

extension XCUIElement {
    /// One scroll step of this list. `up`: the finger moves up, the content moves towards the end (as `swipeUp()`).
    /// `.slow` steps hold at the end (no momentum, precise); faster ones are flicks that glide.
    func scrollStep(up: Bool, velocity: XCUIGestureVelocity = .slow) {
        let frame = self.frame
        guard frame.width > 1, frame.height > 1 else { return }
        let top = frame.minY + max(frame.height * 0.15, 120)
        let bottom = frame.maxY - max(frame.height * 0.15, 100)
        let x = frame.minX + frame.width * 0.9
        // A list too short for the margins: its middle third.
        let (from, to): (CGFloat, CGFloat) = bottom - top > 60
            ? (up ? (bottom, top) : (top, bottom))
            : (up ? (frame.midY + frame.height / 6, frame.midY - frame.height / 6)
                  : (frame.midY - frame.height / 6, frame.midY + frame.height / 6))
        let origin = coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: x - frame.minX, dy: from - frame.minY))
        let end = origin.withOffset(CGVector(dx: x - frame.minX, dy: to - frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: velocity,
                    thenHoldForDuration: velocity.rawValue <= XCUIGestureVelocity.slow.rawValue ? 0.1 : 0)
    }
}

extension XCUIApplication {
    /// The frontmost app list: the Settings panel or sheet (a collection view), else a table.
    var frontList: XCUIElement { collectionViews.firstMatch.exists ? collectionViews.firstMatch : tables.firstMatch }

    /// One scroll step of the frontmost app list (`XCUIElement.scrollStep`).
    func scrollFrontList(up: Bool, velocity: XCUIGestureVelocity = .slow) {
        frontList.scrollStep(up: up, velocity: velocity)
    }
}
