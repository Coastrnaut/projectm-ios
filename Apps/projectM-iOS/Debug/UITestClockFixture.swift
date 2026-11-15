// UITestClockFixture.swift — DEBUG only (MED-011, ClockOverlayUITests). `-uitestClockFixed <epoch seconds>` makes
// the clock overlay use a fixed clock (UTC, `en_US_POSIX`); the test turns it on in Settings, so the drawn string is deterministic.
// The settings still go through the real store. Not compiled into Release builds.
#if DEBUG
import Foundation
import SwiftUI
import TextLayer

@MainActor
enum UITestClockFixture {
    static let argument = "-uitestClockFixed"

    static func make(defaults: UserDefaults) -> ClockOverlayCoordinator? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count,
              let seconds = TimeInterval(arguments[index + 1]), let utc = TimeZone(secondsFromGMT: 0) else { return nil }
        let source = FixedClockSource(now: Date(timeIntervalSince1970: seconds), timeZone: utc)
        return ClockOverlayCoordinator(store: ClockOverlayStore(defaults: defaults), source: source,
                                       locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// "<text|none> drawn=<frames>": the clock's current string and the frames in which a live clock layer showed it.
struct ClockProbe: View {
    let clock: ClockOverlayCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let shown: String = clock.currentText ?? "none"
            let text: String = shown + " drawn=" + String(clock.framesShown)
            Text(text)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("clockProbe")
                .accessibilityValue(text)
        }
    }
}
#endif
