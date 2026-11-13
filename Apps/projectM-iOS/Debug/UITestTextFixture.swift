// UITestTextFixture.swift — DEBUG only (MED-009-R14). Typing emoji and Arabic through XCUITest's
// keyboard is unreliable, so `-uitestSeedText <message>` saves the message through the same path
// as the editor (TextOverlayCoordinator.setMessage: cleaning, limits, the stored JSON) before the
// first screen. Not compiled into Release builds.
#if DEBUG
import Foundation

@MainActor
enum UITestTextFixture {
    static let argument = "-uitestSeedText"

    static func seedIfRequested(_ texts: TextOverlayCoordinator) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return }
        texts.setMessage(arguments[i + 1])
    }
}
#endif
