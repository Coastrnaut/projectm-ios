// MED-011-T04: the clock's formatter, change detection, schedule and settings (MED-011-S1, S4; contract C1,
// C2). Plain Swift: runs on the host, the simulator and Linux. Fixed dates, `en_US_POSIX` and fixed time zones;
// no wall clock is read.
import Foundation
import TextLayer
import XCTest

final class ClockFormatterTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")
    private let utc = TimeZone(secondsFromGMT: 0)!

    /// UTC date from components.
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    private func string(_ cycle: ClockHourCycle, seconds: Bool, _ date: Date, _ zone: TimeZone) -> String {
        ClockFormatter(hourCycle: cycle, showsSeconds: seconds, locale: posix, timeZone: zone).string(for: date)
    }

    /// S1 (roadmap acceptance): a fixed injected clock gives exact strings for each format.
    func testFixedClockGivesExactStringsForEachFormat() {
        let clock = FixedClockSource(now: date(2026, 3, 4, 14, 5, 9), timeZone: utc)
        XCTAssertEqual(string(.twentyFourHour, seconds: false, clock.now, clock.timeZone), "14:05")
        XCTAssertEqual(string(.twentyFourHour, seconds: true, clock.now, clock.timeZone), "14:05:09")
        XCTAssertEqual(string(.twelveHour, seconds: false, clock.now, clock.timeZone), "2:05 PM")
        XCTAssertEqual(string(.twelveHour, seconds: true, clock.now, clock.timeZone), "2:05:09 PM")
        // The injected zone, not the host's: +09:00 shows 23:05.
        XCTAssertEqual(string(.twentyFourHour, seconds: false, clock.now, TimeZone(secondsFromGMT: 9 * 3600)!), "23:05")
    }

    /// S4: midnight in both hour cycles.
    func testMidnight() {
        let before = date(2026, 12, 31, 23, 59, 59), after = date(2027, 1, 1, 0, 0, 0)
        XCTAssertEqual(string(.twentyFourHour, seconds: false, before, utc), "23:59")
        XCTAssertEqual(string(.twentyFourHour, seconds: false, after, utc), "00:00")
        XCTAssertEqual(string(.twelveHour, seconds: false, before, utc), "11:59 PM")
        XCTAssertEqual(string(.twelveHour, seconds: false, after, utc), "12:00 AM")
        XCTAssertEqual(string(.twelveHour, seconds: true, date(2026, 6, 1, 12, 0, 0), utc), "12:00:00 PM", "noon")
    }

    /// S4: New York's 2026 spring-forward (8 March) and fall-back (1 November).
    func testDaylightSavingTransitions() throws {
        guard let ny = TimeZone(identifier: "America/New_York") else {
            throw XCTSkip("No time zone database in this environment")
        }
        XCTAssertEqual(string(.twentyFourHour, seconds: true, date(2026, 3, 8, 6, 59, 59), ny), "01:59:59")
        XCTAssertEqual(string(.twentyFourHour, seconds: true, date(2026, 3, 8, 7, 0, 0), ny), "03:00:00", "spring forward")
        XCTAssertEqual(string(.twelveHour, seconds: false, date(2026, 11, 1, 5, 59, 0), ny), "1:59 AM")
        XCTAssertEqual(string(.twelveHour, seconds: false, date(2026, 11, 1, 6, 0, 0), ny), "1:00 AM", "fall back")
    }

    /// C2: a string is reported only when it changes; a zone change shows at the next update.
    func testClockTextReportsOnlyChanges() {
        let text = ClockText(formatter: ClockFormatter(hourCycle: .twentyFourHour, showsSeconds: false, locale: posix, timeZone: utc))
        let start = date(2026, 3, 4, 14, 5, 0)
        XCTAssertEqual(text.update(at: start, timeZone: utc), "14:05")
        var changes = 0
        for s in 1..<60 where text.update(at: start.addingTimeInterval(TimeInterval(s)), timeZone: utc) != nil { changes += 1 }
        XCTAssertEqual(changes, 0, "no change within the minute")
        XCTAssertEqual(text.update(at: start.addingTimeInterval(60), timeZone: utc), "14:06")
        XCTAssertEqual(text.update(at: start.addingTimeInterval(61), timeZone: TimeZone(secondsFromGMT: 3600)!), "15:06")
        XCTAssertEqual(text.current, "15:06")
    }

    func testScheduleAlignsToTheNextWholeSecond() {
        XCTAssertEqual(ClockSchedule.delay(after: Date(timeIntervalSince1970: 100.25)), 0.75, accuracy: 1e-9)
        XCTAssertEqual(ClockSchedule.delay(after: Date(timeIntervalSince1970: 100)), 1, accuracy: 1e-9)
        XCTAssertEqual(ClockSchedule.delay(after: Date(timeIntervalSince1970: 100.999)), 0.001, accuracy: 1e-6)
    }

    func testSettingsDefaultsSpecAndStorage() throws {
        let d = ClockOverlaySettings.default
        XCTAssertFalse(d.isShown, "off by default")
        XCTAssertEqual(d.hourCycle, .twentyFourHour)
        XCTAssertFalse(d.showsSeconds)
        XCTAssertEqual(d.style.font, .menlo)
        XCTAssertEqual(d.style.verticalPosition, .top)
        XCTAssertEqual(d.style.alignment, .trailing)
        XCTAssertTrue(d.spec(for: "14:05").isEmpty, "hidden → nothing to draw")

        var s = ClockOverlaySettings(isShown: true, hourCycle: .twelveHour, showsSeconds: true)
        s.style.verticalPosition = .bottom
        XCTAssertEqual(s.spec(for: "2:05:09 PM").message, "2:05:09 PM")
        XCTAssertEqual(s.spec(for: "2:05:09 PM").verticalPosition, .bottom)
        XCTAssertEqual(ClockOverlaySettings.decodeStored(s.encodedForStorage()), .settings(s), "round trip")
        XCTAssertEqual(ClockOverlaySettings.decodeStored(Data("garbage".utf8)), .damaged)
        XCTAssertEqual(ClockOverlaySettings.decodeStored(Data("{\"version\":2}".utf8)), .unsupportedVersion(2))
        let lenient = ClockOverlaySettings.decodeStored(Data("{\"version\":1,\"isShown\":true,\"hourCycle\":\"sundial\"}".utf8))
        XCTAssertEqual(lenient, .settings(ClockOverlaySettings(isShown: true)), "unknown values read as defaults")
    }
}
