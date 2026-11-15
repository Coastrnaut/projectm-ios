// ClockOverlayStoreTests.swift — MED-011-T10: the clock's settings and ticks in the app (MED-011-R1, R5, R6, R8;
// S3, S5). Each test uses its own UserDefaults suite; "relaunch" is a new coordinator on the same defaults. The
// clock is a manual injected source; no wall clock is read and nothing waits for the tick task.
import Compositor
import Foundation
import Metal
import TextLayer
import XCTest
@testable import projectM_iOS

/// A clock the test moves by hand.
private final class ManualClock: ClockSource, @unchecked Sendable {
    var now: Date
    var timeZone: TimeZone
    init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }
}

@MainActor
final class ClockOverlayStoreTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "ClockOverlayStoreTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    func testSettingsAreOffByDefaultAndSurviveARelaunch() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = ClockOverlayCoordinator(store: ClockOverlayStore(defaults: defaults))
        XCTAssertEqual(clock.settings, .default)
        XCTAssertFalse(clock.settings.isShown, "off by default")
        XCTAssertEqual(clock.summary, "Off")
        XCTAssertNil(defaults.object(forKey: ClockOverlayStore.key), "nothing written before a change")
        clock.settings.isShown = true
        clock.settings.hourCycle = .twelveHour
        clock.settings.showsSeconds = true
        clock.settings.style.verticalPosition = .bottom
        XCTAssertEqual(clock.summary, "12-hour with seconds")
        XCTAssertEqual(Array(defaults.persistentDomain(forName: suite)?.keys ?? [:].keys), [ClockOverlayStore.key], "one settings key")
        let relaunched = ClockOverlayCoordinator(store: ClockOverlayStore(defaults: defaults))
        XCTAssertEqual(relaunched.settings, clock.settings, "identical after a relaunch")
        XCTAssertTrue(AppSettings.allKeys.contains(ClockOverlayStore.key), "removed by the UI-test reset")
    }

    func testDamagedValueIsRemovedAndANewerOneIsKept() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("garbage".utf8), forKey: ClockOverlayStore.key)
        XCTAssertEqual(ClockOverlayStore(defaults: defaults).load(), .default)
        XCTAssertNil(defaults.object(forKey: ClockOverlayStore.key), "a damaged value is removed")
        let newer = Data("{\"version\":9}".utf8)
        defaults.set(newer, forKey: ClockOverlayStore.key)
        XCTAssertEqual(ClockOverlayStore(defaults: defaults).load(), .default)
        XCTAssertEqual(defaults.data(forKey: ClockOverlayStore.key), newer, "left untouched")
    }

    /// R5, R6: ticks push a new spec to the attached layer only when the string changes; hidden → empty spec.
    func testTicksPushOnlyChangedStringsToTheAttachedLayer() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device") }
        let manual = ManualClock(now: Date(timeIntervalSince1970: 1_772_633_100), timeZone: utc)   // 14:05:00 UTC
        let clock = ClockOverlayCoordinator(store: ClockOverlayStore(defaults: defaults), source: manual,
                                            locale: Locale(identifier: "en_US_POSIX"))
        let base = TextLayerSource(device: device)
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .text))
        let compositor = try Compositor(device: device)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in base }
        let layer = try XCTUnwrap(clock.attach(to: compositor))
        XCTAssertEqual(layer.layerName, "clock")
        XCTAssertNil(clock.attach(to: compositor), "one clock per stack")
        XCTAssertEqual(compositor.appliedStack?.entries.last?.descriptor.kind, .clock, "the top layer")
        XCTAssertTrue(layer.spec.isEmpty, "hidden: nothing to draw")
        XCTAssertFalse(clock.isTicking)

        clock.settings.isShown = true
        XCTAssertEqual(layer.spec.message, "14:05")
        XCTAssertEqual(layer.spec.font, .menlo)
        XCTAssertTrue(clock.isTicking, "ticks while shown with a live layer")
        manual.now = manual.now.addingTimeInterval(30)
        XCTAssertFalse(clock.tick(), "same minute: no new spec")
        manual.now = manual.now.addingTimeInterval(30)
        XCTAssertTrue(clock.tick())
        XCTAssertEqual(layer.spec.message, "14:06")
        clock.settings.hourCycle = .twelveHour
        XCTAssertEqual(layer.spec.message, "2:06 PM", "a format change shows at once")
        clock.settings.style.verticalPosition = .bottom
        XCTAssertEqual(layer.spec.verticalPosition, .bottom)
        clock.settings.isShown = false
        XCTAssertTrue(layer.spec.isEmpty, "hidden again")
        XCTAssertFalse(clock.isTicking)
        XCTAssertNil(clock.currentText)
    }
}
