// PermissionPrimerDeviceTests.swift — QA-011: a one-time primer per device for the permissions that later device
// tests need (microphone for B05, camera for B06, Local Network for B09's OSC). Each test launches the app so that
// iOS shows its own permission prompt, then WAITS for a person at the device to answer it; the test never taps the
// prompt (owner decision 2026-11-15: permission prompts stay a person's step). A granted permission persists across
// reinstalls of the same app, so this runs once per device; later tests run unattended.
//
//     xcodebuild test-without-building ... -only-testing:projectM-iOSDeviceUITests/PermissionPrimerDeviceTests
import XCTest

@MainActor
final class PermissionPrimerDeviceTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = true
    }

    override func tearDown() async throws {
        app.terminate()
    }

    /// Launches with `arguments`, then waits for a system alert to appear (up to 20 s) and for a person to answer it
    /// (up to 180 s). Reports whether a prompt was shown; no prompt means the permission was already answered.
    private func prime(_ name: String, _ arguments: [String]) {
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "NO"] + arguments
        app.launch()
        let alert = springboard.alerts.firstMatch
        let shown = alert.waitForExistence(timeout: 20)
        if shown {
            print("PERMISSION-PRIMER \(name): prompt shown, waiting for a person to answer: \(alert.label)")
            let answered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alert)
            let result = XCTWaiter().wait(for: [answered], timeout: 180)
            XCTAssertEqual(result, .completed, "\(name): the prompt was answered at the device")
            print("PERMISSION-PRIMER \(name): answered")
        } else {
            print("PERMISSION-PRIMER \(name): no prompt (already answered on this device)")
        }
    }

    func testA_Microphone() { prime("microphone", ["-autostart", "microphone"]) }
    func testB_Camera() { prime("camera", ["-autostart", "inAppPlayback", "-settings.visual", "camera"]) }
    func testC_LocalNetwork() {
        prime("localNetwork", ["-autostart", "inAppPlayback", "-settings.osc.enabled", "YES", "-settings.osc.port", "47127"])
    }
}
