// Feature 002 SC-103 (T238): frames delivered on time while scrolling the longest lists for 10 s:
// All presets A-Z and the largest folder (projectM Classic › milkdrop, 608 presets). The app's
// FrameMeter (`-uitestFrameMeter`) counts frames on time and refresh slots missed. On a device
// (`scripts/run_device_tests.py scroll`) the test fails below 95%; on the simulator it only
// reports, because simulator timing is never evidence (Constitution X). Debug build: Release is at
// least as fast.
import XCTest

@MainActor
final class PresetScrollPerformanceUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openBrowser() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "YES", "-uitestFrameMeter"]
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        acknowledge.tap()
        app.buttons["In-App Playback"].tap()
        let presets = app.buttons["presets"]
        if !presets.waitForExistence(timeout: 5) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        presets.tap()
        XCTAssertTrue(app.buttons["node:all"].waitForExistence(timeout: 10), "library home")
    }

    /// Swipes up for `seconds`, then returns frames on time and missed from the meter.
    private func scroll(for seconds: TimeInterval) -> (frames: Int, missed: Int) {
        let meter = app.staticTexts["frameMeter"]
        XCTAssertTrue(meter.waitForExistence(timeout: 5), "launched with -uitestFrameMeter")
        let start = meterValues(meter)
        let began = Date()
        while Date().timeIntervalSince(began) < seconds {
            app.swipeUp(velocity: .fast)
        }
        let end = meterValues(meter)
        return (end.frames - start.frames, end.missed - start.missed)
    }

    private func meterValues(_ meter: XCUIElement) -> (frames: Int, missed: Int) {
        let numbers = meter.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return numbers.count == 2 ? (numbers[0], numbers[1]) : (0, 0)
    }

    private func check(_ list: String, _ result: (frames: Int, missed: Int)) {
        let total = result.frames + result.missed
        let onTime = total == 0 ? 0 : Double(result.frames) / Double(total)
        let line = String(format: "SC103 %@ frames=%d missed=%d onTime=%.4f", list, result.frames, result.missed, onTime)
        print(line)   // scripts/run_device_tests.py reads this line from the test log
        add(XCTAttachment(string: line))
        XCTAssertGreaterThan(total, 100, "the meter ran while scrolling")
        #if !targetEnvironment(simulator)
        XCTAssertGreaterThanOrEqual(onTime, 0.95, "SC-103: at least 95% of frames on time (\(list))")
        #endif
    }

    func testScrollAllPresetsAToZ() {
        openBrowser()
        app.buttons["node:all"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch.waitForExistence(timeout: 10))
        check("all", scroll(for: 10))
    }

    func testScrollTheLargestFolder() {
        openBrowser()
        app.buttons["node:projectm-classic"].tap()
        let folder = app.buttons["node:projectm-classic/milkdrop"]
        for _ in 0..<10 { if folder.exists && folder.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        XCTAssertEqual(folder.label, "milkdrop, 608 presets", "the largest folder")
        folder.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'")).firstMatch.waitForExistence(timeout: 10))
        check("largest-folder", scroll(for: 10))
    }
}
