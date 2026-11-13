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
                   "Linear Spectrum": "linearSpectrum", "Camera": "camera", "Photo": "photo"][title] ?? title
        return buttons["visual.\(raw)"]
    }
}
