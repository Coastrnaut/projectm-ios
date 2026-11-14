// OneHandedLayoutTests.swift — ACC-009 (specs/244-acc-009-one-handed-mode; S1, S2; contract C1, C2).
//
// The acceptance "Layout switch preserves every critical action on phone sizes", on the pure geometry: over a table of
// phone safe areas (the smallest supported iPhone to Pro Max, portrait and landscape), Dynamic Type base sides and
// states, the one-handed layout places exactly the standard layout's critical actions, each at least 44 pt (the pad's
// 60 pt while the pad is on), inside the safe area and the thumb zone, without overlap, inside the reserved band.
// Pure arithmetic: the whole table runs in milliseconds.
import ShowControl
import XCTest

final class OneHandedLayoutTests: XCTestCase {
    typealias Rect = OneHandedLayout.Rect

    /// Safe areas in points (status bar, notch and home indicator taken off), portrait; landscape swaps the shape.
    struct Phone {
        let name: String
        let portrait: (width: Double, height: Double)
        let landscape: (width: Double, height: Double)
    }

    static let phones: [Phone] = [
        Phone(name: "iPhone SE (3rd generation)", portrait: (375, 647), landscape: (667, 375)),
        Phone(name: "iPhone 13 mini", portrait: (375, 728), landscape: (724, 354)),
        Phone(name: "iPhone 17e", portrait: (390, 763), landscape: (750, 369)),
        Phone(name: "iPhone 17", portrait: (402, 778), landscape: (750, 381)),
        Phone(name: "iPhone 17 Pro Max", portrait: (440, 860), landscape: (832, 419)),
    ]

    /// Base sides: the default size, a large standard size and an accessibility size (clamped to 56).
    static let baseSides: [Double] = [44, 50, 70]

    static let contexts: [CriticalActionContext] = [
        CriticalActionContext(hasCues: true, padOn: true, alternateVisual: false, controlsVisible: true),
        CriticalActionContext(hasCues: true, padOn: false, alternateVisual: false, controlsVisible: true),
        CriticalActionContext(hasCues: false, padOn: false, alternateVisual: false, controlsVisible: true),
        CriticalActionContext(hasCues: false, padOn: false, alternateVisual: true, controlsVisible: true),
    ]

    private func layout(_ size: (width: Double, height: Double), _ hand: OneHandedHand, base: Double,
                        _ context: CriticalActionContext) -> OneHandedLayout {
        OneHandedLayout(width: size.width, height: size.height, hand: hand, baseTarget: base,
                        padTarget: context.padOn ? PerformanceLayout.compactTarget : nil,
                        actions: CriticalAction.displayed(context))
    }

    /// S1: every rule over the whole table.
    func testEveryPhoneSizeKeepsEveryCriticalActionInTheThumbZone() {
        var cases = 0
        for phone in Self.phones {
            for (shape, size) in [("portrait", phone.portrait), ("landscape", phone.landscape)] {
                for base in Self.baseSides {
                    for context in Self.contexts {
                        for hand in OneHandedHand.allCases {
                            cases += 1
                            let tag = "\(phone.name) \(shape) base \(base) \(context) \(hand)"
                            check(layout(size, hand, base: base, context), size: size, context: context, tag: tag)
                        }
                    }
                }
            }
        }
        XCTAssertEqual(cases, 5 * 2 * 3 * 4 * 2)
    }

    private func check(_ layout: OneHandedLayout, size: (width: Double, height: Double), context: CriticalActionContext,
                       tag: String) {
        let safe = Rect(x: 0, y: 0, width: size.width, height: size.height)
        // The same set as the standard layout, each action once.
        XCTAssertEqual(layout.frames.map(\.action), CriticalAction.standard(context), tag)
        XCTAssertTrue(layout.fits, "\(tag): does not fit")
        let band: Rect = layout.reservedRect
        for (index, entry) in layout.frames.enumerated() {
            let rect: Rect = entry.rect
            let minimum: Double = entry.action.isPadAction && context.padOn ? PerformanceLayout.compactTarget : OneHandedLayout.minimumTarget
            XCTAssertGreaterThanOrEqual(rect.width, minimum, "\(tag) \(entry.action): width")
            XCTAssertGreaterThanOrEqual(rect.height, minimum, "\(tag) \(entry.action): height")
            XCTAssertTrue(safe.contains(rect), "\(tag) \(entry.action): outside the safe area")
            XCTAssertTrue(layout.zone.contains(rect), "\(tag) \(entry.action): outside the zone")
            XCTAssertTrue(band.contains(rect), "\(tag) \(entry.action): outside the reserved band")
            for other in layout.frames[(index + 1)...] {
                XCTAssertFalse(rect.intersects(other.rect), "\(tag): \(entry.action) overlaps \(other.action)")
            }
        }
    }

    /// The zone is the bottom corner on the chosen side (research D1).
    func testZoneIsTheBottomCornerOfTheChosenSide() {
        let portraitRight: Rect = OneHandedLayout.zone(width: 400, height: 800, hand: .right)
        XCTAssertEqual(portraitRight, Rect(x: 100, y: 480, width: 300, height: 320))
        let portraitLeft: Rect = OneHandedLayout.zone(width: 400, height: 800, hand: .left)
        XCTAssertEqual(portraitLeft, Rect(x: 0, y: 480, width: 300, height: 320))
        let landscapeRight: Rect = OneHandedLayout.zone(width: 800, height: 400, hand: .right)
        XCTAssertEqual(landscapeRight, Rect(x: 480, y: 100, width: 320, height: 300))
    }

    /// C2: the sets per state.
    func testStandardAndDisplayedSets() {
        let full = CriticalActionContext(hasCues: true, padOn: false, alternateVisual: false, controlsVisible: true)
        XCTAssertEqual(CriticalAction.standard(full), CriticalAction.allCases)
        var native = full
        native.alternateVisual = true
        native.hasCues = false
        XCTAssertEqual(CriticalAction.standard(native), [.tapTempo, .blackout, .pauseResume, .settings, .stop])
        var hiddenPad = full
        hiddenPad.controlsVisible = false
        hiddenPad.padOn = true
        XCTAssertEqual(CriticalAction.displayed(hiddenPad), [.cuePrevious, .cueNext, .tapTempo, .blackout])
        hiddenPad.padOn = false
        XCTAssertEqual(CriticalAction.displayed(hiddenPad), [])
        XCTAssertEqual(Set(CriticalAction.allCases.map(\.identifier)).count, 11, "identifiers are unique")
    }

    /// S2: with the pad on, the pad targets keep their frames when the controls show or hide.
    func testPadTargetsDoNotMoveWhenTheControlsShow() {
        for phone in Self.phones {
            for size in [phone.portrait, phone.landscape] {
                var context = CriticalActionContext(hasCues: true, padOn: true, alternateVisual: false, controlsVisible: true)
                let shown: OneHandedLayout = layout(size, .right, base: 44, context)
                context.controlsVisible = false
                let hidden: OneHandedLayout = layout(size, .right, base: 44, context)
                XCTAssertEqual(hidden.frames.map(\.action), [.cuePrevious, .cueNext, .tapTempo, .blackout])
                for entry in hidden.frames {
                    XCTAssertEqual(shown.frame(of: entry.action), entry.rect, "\(phone.name) \(entry.action)")
                    XCTAssertEqual(entry.rect.width, PerformanceLayout.compactTarget)
                }
            }
        }
    }

    /// Clarification: Stop is farthest from the thumb (top row), the pad group nearest (bottom rows); rows hug the edge.
    func testOrderPutsStopFarthestFromTheThumb() {
        let context = CriticalActionContext(hasCues: true, padOn: false, alternateVisual: false, controlsVisible: true)
        let right: OneHandedLayout = layout((402, 778), .right, base: 44, context)
        let stop: Rect = right.frame(of: .stop)!
        let minY: Double = right.frames.map(\.rect.y).min()!
        XCTAssertEqual(stop.y, minY, "Stop is in the top row")
        let blackout: Rect = right.frame(of: .blackout)!
        XCTAssertEqual(blackout.maxY, right.zone.maxY - OneHandedLayout.margin, "the pad group is in the bottom row")
        let rightmost: Double = right.frames.map(\.rect.maxX).max()!
        XCTAssertEqual(rightmost, right.zone.maxX - OneHandedLayout.margin, accuracy: 0.001, "right hand: rows hug the right edge")
        let left: OneHandedLayout = layout((402, 778), .left, base: 44, context)
        let leftmost: Double = left.frames.map(\.rect.x).min()!
        XCTAssertEqual(leftmost, OneHandedLayout.margin, accuracy: 0.001, "left hand: rows hug the left edge")
    }

    /// R4: in a short area the base shrinks in 4 pt steps, never below 44 pt, and no action is dropped.
    func testShrinksToFitAndNeverDropsAnAction() {
        let context = CriticalActionContext(hasCues: true, padOn: false, alternateVisual: false, controlsVisible: true)
        // 375 × 540: zone 281 × 216. At 56 pt (4 per row, 3 rows) 200 pt fits; make it shorter so 56 pt cannot.
        let short = OneHandedLayout(width: 375, height: 470, hand: .right, baseTarget: 56, padTarget: nil,
                                    actions: CriticalAction.displayed(context))
        XCTAssertLessThan(short.baseTarget, 56)
        XCTAssertGreaterThanOrEqual(short.baseTarget, OneHandedLayout.minimumTarget)
        XCTAssertTrue(short.fits)
        XCTAssertEqual(short.frames.count, 11)
        // Far too short: every action is still placed at 44 pt and the layout says it does not fit.
        let tiny = OneHandedLayout(width: 375, height: 200, hand: .left, baseTarget: 56, padTarget: nil,
                                   actions: CriticalAction.displayed(context))
        XCTAssertEqual(tiny.baseTarget, OneHandedLayout.minimumTarget)
        XCTAssertFalse(tiny.fits)
        XCTAssertEqual(tiny.frames.map(\.action), CriticalAction.allCases)
    }

    /// D5: the base side clamps to 44…56; nothing placed reserves nothing.
    func testBaseClampAndEmptyLayout() {
        XCTAssertEqual(OneHandedLayout.baseTarget(scaled: 30), 44)
        XCTAssertEqual(OneHandedLayout.baseTarget(scaled: 50), 50)
        XCTAssertEqual(OneHandedLayout.baseTarget(scaled: 90), 56)
        let empty = OneHandedLayout(width: 402, height: 778, hand: .right, baseTarget: 44, padTarget: nil, actions: [])
        XCTAssertEqual(empty.reservedInsets, PerformanceLayout.Insets())
        XCTAssertTrue(empty.frames.isEmpty)
    }
}
