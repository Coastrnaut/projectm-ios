// UITestWaits.swift — waits that return as soon as their condition holds (owner rule 7, 2026-11-13:
// short tests). `waitForExistence(timeout:)` and `XCTNSPredicateExpectation` check about once a
// second, so each one cost about 1 s even when the element was already on screen: 15-20 s per test.
// These poll every 0.1 s instead. Timeouts are ceilings for a slow shared Mac, never frame budgets.
import XCTest

/// Polls `condition` every 0.1 s, checking at once first; false after `timeout` seconds.
@MainActor
func poll(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if condition() { return true }
        if Date() >= deadline { return false }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}

extension XCUIElement {
    /// True as soon as the element exists (at once when it already does); false after `timeout`.
    func appears(within timeout: TimeInterval = 10) -> Bool { poll(timeout) { self.exists } }

    /// True as soon as the element is gone (at once when it already is); false after `timeout`.
    func disappears(within timeout: TimeInterval = 10) -> Bool { poll(timeout) { !self.exists } }
}

extension XCUIApplication {
    /// The Settings row for a visual, by its title (VIS-002-F1: rows replaced the segmented
    /// `visualPicker`). Identifiers are `visual.<VisualChoice raw value>`.
    func visualRow(_ title: String) -> XCUIElement {
        let raw = ["projectM": "projectM", "Circular Spectrum": "circularSpectrum",
                   "Linear Spectrum": "linearSpectrum", "Camera": "camera", "Photo": "photo", "Video": "video", "Text": "text"][title] ?? title
        return buttons["visual.\(raw)"]
    }
}

extension XCUIApplication {
    /// Scrolls until `element` sits fully on screen (below the navigation bar when scrolling down),
    /// at most 8 held drags of 70 % of the screen; true when it is visible. Shared by every suite
    /// whose rows can fall below the fold as Settings grows (GlowUITests failed this way on
    /// 2026-11-13). Frames, not `isHittable`, which fails the test for an off-screen row.
    @discardableResult
    func reveal(_ element: XCUIElement, down: Bool = false) -> Bool {
        let window = windows.firstMatch
        let bar = navigationBars.firstMatch
        let top = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
        func visible() -> Bool {
            guard element.exists else { return false }
            let frame = element.frame, screen = window.frame
            let limit: CGFloat = down ? bar.frame.maxY : screen.minY
            return frame.height > 0 && frame.minY >= limit && frame.maxY <= screen.maxY
        }
        for _ in 0..<8 where !visible() {
            // Down (towards the top of the list) uses a short drag from mid-screen: a long pull from
            // near the top on a list already at its top dismisses the sheet instead of scrolling.
            let midHigh = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
            let midLow = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let (from, to) = down ? (midHigh, midLow) : (bottom, top)
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0.1)
        }
        return visible()
    }
}
