// UITestSliders.swift — ACC-005: finding and dragging the Settings sliders.
//
// Since ACC-005 each continuous slider is one accessibility element of its own (label, spoken value,
// adjustable action; research D1): XCTest reports it as an "other" element, not a slider, so
// `app.sliders[id]` and `adjust(toNormalizedSliderPosition:)` no longer apply. `slider(_:)` finds it by
// identifier, and `dragSlider(from:to:)` drags its thumb by touch inside the element's frame.
import XCTest

extension XCUIApplication {
    /// The accessible slider with `identifier` (any element type).
    func slider(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

extension XCUIElement {
    /// Drags the slider's thumb from the normalized position `current` to `target` (0…1).
    ///
    /// In a Settings list the element's frame is the whole row (title above, slider below, the row's
    /// padding around), so the drag runs along the slider's line, about 27 pt above the row's bottom
    /// for a titled row, and the track starts about 20 pt inside the row (the list's margins) plus
    /// half a thumb (14 pt). 0 and 1 overshoot the track so the drag lands on the end stop.
    func dragSlider(from current: CGFloat, to target: CGFloat) {
        let rect: CGRect = frame
        let width: CGFloat = max(rect.width, 1)
        let y: CGFloat = rect.height > 50 ? rect.height - 27 : rect.height / 2
        let left: CGFloat = rect.height > 50 ? 34 : 14
        let track: CGFloat = max(width - 2 * left, 1)
        func x(_ position: CGFloat) -> CGFloat { left + min(max(position, 0), 1) * track }
        let origin = coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let start = origin.withOffset(CGVector(dx: x(current), dy: y))
        let endX: CGFloat = target <= 0 ? -10 : (target >= 1 ? width + 10 : x(target))
        let end = origin.withOffset(CGVector(dx: endX, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }
}
