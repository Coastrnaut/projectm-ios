// UITestCountdownFixture.swift — DEBUG only (MED-012, CountdownOverlayUITests). `-uitestCountdownFixed <seconds>` makes
// the countdown use a monotonic clock frozen at that value, so a started countdown shows its full duration ("05:00")
// deterministically. The settings still go through the real store. Not compiled into Release builds.
#if DEBUG
import Foundation
import SwiftUI
import TextLayer

@MainActor
enum UITestCountdownFixture {
    static let argument = "-uitestCountdownFixed"

    static func make(defaults: UserDefaults) -> CountdownOverlayCoordinator? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count,
              let seconds = Double(arguments[index + 1]) else { return nil }
        return CountdownOverlayCoordinator(store: CountdownOverlayStore(defaults: defaults), clock: FixedMonotonicClock(seconds: seconds))
    }
}

/// "<text|none> <state> finished=<n> drawn=<frames>" (contract C5): the countdown's string while shown, its state, its
/// finished events and the frames in which a live countdown layer showed it.
struct CountdownProbe: View {
    let countdown: CountdownOverlayCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let text: String = Self.value(countdown)
            Text(text)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("countdownProbe")
                .accessibilityValue(text)
        }
    }

    static func value(_ countdown: CountdownOverlayCoordinator) -> String {
        let shown: String = countdown.settings.isShown ? (countdown.currentText ?? "none") : "none"
        let state: String = countdown.state.rawValue
        let finished: String = "finished=" + String(countdown.finishedCount)
        let drawn: String = "drawn=" + String(countdown.framesShown)
        return shown + " " + state + " " + finished + " " + drawn
    }
}
#endif
