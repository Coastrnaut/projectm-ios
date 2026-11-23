// ListScrolling.swift — one scroll step of an app list (Settings and its pushed screens) that always starts and ends
// inside the list's visible area, well away from the screen's edges.
//
// QA-011 pass 6 D2 (iPad Pro M5, 2026-11-19): `swipeUp()`/`swipeDown()` on the Settings panel's CollectionView, which
// is as tall as the screen ({{632, 0}, {400, 1376}}), leave the start point to XCUITest; one prompt-flow test ended on
// the Home Screen after such swipes. A drag that starts near the bottom edge is the system's Home gesture, and one at
// the top edge pulls down Notification Centre, so every step here keeps at least 15 % of the list's height (and
// 120 pt at the top, 100 pt at the bottom) clear of its edges, in the list's right-hand margin (a drag through a
// slider's thumb mid-row moves the slider; the left edge is the navigation back gesture).
//
// QA-011 full run 12 D2 (2026-11-20, FILE-010-T11): the right-hand margin is where a row's switch sits. With Settings
// at its top, a downward step started at (992, 206), on the "Lock scene" switch, and one of twelve such steps turned
// the scene lock on (screenshots: the switch on, "Scene locked" over the visual); every visual change after that was
// refused, so Photo was never chosen, Record refused ("Recording is available for the Camera, Photo, Video, Text and
// spectrum visuals") and the relaunch showed projectM. A step now never starts on a switch or a slider: it moves its
// start point along the drag, into the list, until it is clear of them.
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
        let (planned, to): (CGFloat, CGFloat) = bottom - top > 60
            ? (up ? (bottom, top) : (top, bottom))
            : (up ? (frame.midY + frame.height / 6, frame.midY - frame.height / 6)
                  : (frame.midY - frame.height / 6, frame.midY + frame.height / 6))
        let from = Self.dragStart(x: x, from: planned, to: to, avoiding: dragSensitiveFrames())
        let origin = coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: x - frame.minX, dy: from - frame.minY))
        let end = origin.withOffset(CGVector(dx: x - frame.minX, dy: to - frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: velocity,
                    thenHoldForDuration: velocity.rawValue <= XCUIGestureVelocity.slow.rawValue ? 0.1 : 0)
    }

    /// One short, slow drag that moves this list's content by `distance` points (positive: down, towards the start;
    /// negative: up, towards the end), at most 160 pt, starting in the list's middle band and held before the release.
    /// Short enough that a sheet at its start springs back instead of closing (FILE-010-T11 on D1, 2026-11-23: a
    /// full-height drag towards the start closed the Settings sheet). False when the list is too small to drag in.
    @discardableResult
    func nudge(by distance: CGFloat) -> Bool {
        let frame = self.frame
        let length = min(abs(distance), 160)
        guard frame.width > 1, frame.height > length + 120, length > 0 else { return false }
        let x = frame.minX + frame.width * 0.9
        let planned = distance > 0 ? frame.midY - length / 2 : frame.midY + length / 2
        let target = distance > 0 ? planned + length : planned - length
        let from = Self.dragStart(x: x, from: planned, to: target, avoiding: dragSensitiveFrames())
        let to = distance > 0 ? from + length : from - length
        let origin = coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: x - frame.minX, dy: from - frame.minY))
        let end = origin.withOffset(CGVector(dx: x - frame.minX, dy: to - frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        return true
    }

    /// The first start point on the way from `from` towards `to` (steps of 22 pt, at most half the drag) that lies
    /// outside every frame in `avoiding` grown by 12 pt; `from` itself when none is clear.
    static func dragStart(x: CGFloat, from: CGFloat, to: CGFloat, avoiding: [CGRect]) -> CGFloat {
        guard !avoiding.isEmpty else { return from }
        let zones = avoiding.map { $0.insetBy(dx: -12, dy: -12) }
        let direction: CGFloat = to >= from ? 1 : -1
        let limit = abs(to - from) / 2
        var offset: CGFloat = 0
        while offset <= limit {
            let y = from + direction * offset
            if !zones.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) { return y }
            offset += 22
        }
        return from
    }

    /// The on-screen frames of this list's switches and sliders, which a drag starting on them would change (one
    /// snapshot; empty when it cannot be taken).
    func dragSensitiveFrames() -> [CGRect] {
        guard let root = try? snapshot() else { return [] }
        var frames: [CGRect] = []
        var pending: [any XCUIElementSnapshot] = [root]
        while let node = pending.popLast() {
            if node.elementType == .switch || node.elementType == .slider { frames.append(node.frame) }
            pending.append(contentsOf: node.children)
        }
        return frames
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

// QA-011 D1 full run 1 (iPhone 15, iOS 27.0.1, 2026-11-22): ACC-002-T20, ACC-012-T22 and PRE-015-T26 tapped the preset
// browser's "My Presets" row, and every failure dump still showed the library home ("My Presets, 1 preset" listed, no
// preset row) 30 s later; PRE-009-T13 long-pressed the third Calm row right after "Compare…" put the compare bar up and
// no menu opened. FX-019-T23 opened My Presets the same way in the same run. On an iPhone the browser sheet's list runs
// to the bottom of the screen and iOS 26+ floats the `.searchable` field over its foot (as Settings' search, FILE-013),
// with the PRE-009 compare bar and the PRE-010 audition bar above it; with the colour and motion chip rows in the list,
// the home's last rows and a short filtered list's last row sit under that chrome. The element's frame lies inside the
// window, so `isHittable` and a frames-only reveal accept it, and the tap lands on the chrome. On an iPad the search
// field sits in the navigation bar at the top, which is why D2 and D3 pass. A row now counts as revealed only above the
// bottom chrome, and a row that opens a list is tapped again until its destination shows.
extension XCUIApplication {
    /// The top edge of the chrome pinned over the foot of the frontmost list: the floating search field on an iPhone
    /// (only a search field in the lower half of the window counts: an iPad's sits in the navigation bar), the PRE-009
    /// compare bar, the PRE-010 audition bar and a tab bar. The window's bottom when none shows.
    var bottomChromeTop: CGFloat {
        let window = windows.firstMatch.frame
        var top = window.maxY
        let chrome: [XCUIElement] = [searchFields.firstMatch, descendants(matching: .any)["compareBar"].firstMatch,
                                     descendants(matching: .any)["auditionBar"].firstMatch, tabBars.firstMatch]
        for element in chrome where element.exists {
            let frame = element.frame
            if frame.height > 0, frame.minY > window.midY, frame.minY < top { top = frame.minY }
        }
        return top
    }

    /// True when `element` lies wholly between the navigation bar and the bottom chrome, where a tap reaches it.
    func isClearOfChrome(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame, bar = navigationBars.firstMatch
        let top: CGFloat = bar.exists ? bar.frame.maxY : windows.firstMatch.frame.minY
        return frame.height > 0 && frame.minY >= top && frame.maxY <= bottomChromeTop
    }

    /// The list that holds `reference` (the smallest collection view or table whose frame contains its centre), else
    /// the frontmost list, else the window. On an iPad the preset browser is a form sheet in the middle of the window
    /// ({140, …, 540 wide} on D3): a drag in the window's right margin lands on the dimmed background and moves nothing.
    func listHolding(_ reference: XCUIElement?) -> XCUIElement {
        if let reference, reference.exists {
            let centre = CGPoint(x: reference.frame.midX, y: reference.frame.midY)
            let lists = (collectionViews.allElementsBoundByIndex + tables.allElementsBoundByIndex)
                .filter { $0.exists && $0.frame.width > 1 && $0.frame.contains(centre) }
            if let list = lists.min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) { return list }
        }
        let front = frontList
        return front.exists && front.frame.width > 1 ? front : windows.firstMatch
    }

    /// One held drag inside the list that holds `reference` (`listHolding`), clear of its edges and switches
    /// (`scrollStep`), that moves the content towards the list's end. D3 (iPad A16, iPadOS 26.5, 2026-11-23): ACC-002
    /// at AX5 dragged twelve times in the window's right margin (x 787 of 820) beside the browser sheet (x 140-680),
    /// so My Presets was never built and never opened; the iPhone's full-width list hid that.
    func dragContentUp(near reference: XCUIElement? = nil) {
        listHolding(reference).scrollStep(up: true)
    }

    /// One held drag like `dragContentUp`, towards the list's start.
    func dragContentDown(near reference: XCUIElement? = nil) {
        listHolding(reference).scrollStep(up: false)
    }

    /// Scrolls `row` clear of the bottom chrome, taps it and waits for `destination`; up to `attempts` taps, since a
    /// tap that met the chrome, or a list redrawn under the finger, leaves the list where it was. True once it shows.
    /// A row above the top bar is brought down, one under the bottom chrome up.
    @discardableResult
    func openListRow(_ row: XCUIElement, destination: XCUIElement, attempts: Int = 3) -> Bool {
        for _ in 0..<attempts {
            if destination.exists { return true }
            for _ in 0..<6 where row.exists && !isClearOfChrome(row) {
                if row.frame.maxY > bottomChromeTop { dragContentUp(near: row) } else { dragContentDown(near: row) }
            }
            if row.exists { row.tap() }
            if destination.waitForExistence(timeout: 3) { return true }
        }
        return destination.exists
    }
}
