// CameraLensTests.swift — CAM-003-T08: the lens choice in the app with the stand-in camera
// (CAM-003-R2 to R6, R9; S1, S3). Simulator results are never device evidence. Host tests need a
// Metal device and skip without one.
import CameraLayer
import LibraryBackup
import Metal
import XCTest
@testable import projectM_iOS

@MainActor
final class CameraLensTests: XCTestCase {
    /// S1: the Lens row offers exactly the inventory's lenses (none for one lens or the front camera).
    func testRowOffersExactlyTheAvailableLenses() {
        let cases: [(String, [CameraLens])] = [("wide", []), ("wide,ultraWide", [.ultraWide, .wide]),
                                               ("telephoto,wide,ultraWide", [.ultraWide, .wide, .telephoto])]
        for (list, expected) in cases {
            let inventory = CameraVisualHost.makeLensInventory(arguments: ["-uitestCamera", "granted", "-uitestCameraLenses", list])
            XCTAssertEqual(inventory.offeredLenses(for: .back), expected, list)
            XCTAssertEqual(inventory.offeredLenses(for: .front), [], "\(list): no row for Front")
        }
        let none = CameraVisualHost.makeLensInventory(arguments: ["-uitestCamera", "granted"])
        XCTAssertEqual(none.backLenses, [.wide], "the stand-in has the wide lens only by default")
    }

    /// R4, R5, S3: stored, remembered, unknown → wide, missing on the device → wide with the value kept.
    func testLensSettingPersistsAndResolvesToWideWhenMissing() throws {
        let suite = "CameraLensTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.cameraLens, .wide, "wide by default")
        settings.cameraLens = .telephoto
        let relaunched = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(relaunched.cameraLens, .telephoto, "remembered")
        XCTAssertEqual(relaunched.visual, .projectM, "a stored lens never chooses or starts the Camera visual")
        let twoLenses = FixedCameraLensInventory([.wide, .ultraWide])
        XCTAssertEqual(twoLenses.resolve(relaunched.cameraLens), .wide, "missing on this device → wide")
        XCTAssertEqual(relaunched.cameraLens, .telephoto, "the stored value is kept")
        defaults.set("macro", forKey: AppSettings.cameraLensKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).cameraLens, .wide, "unknown → wide")
        XCTAssertTrue(AppSettings.allKeys.contains(AppSettings.cameraLensKey), "cleared by -uitestResetNotice")
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(AppSettings.cameraLensKey), "backed up and erased with Settings")
    }

    /// R3, R6, R9: the host forwards the lens to the running stand-in; a failing lens keeps the previous
    /// one running; listing lenses never starts the camera.
    func testHostSwitchesLensesOnTheRunningCameraAndSurvivesAFailingLens() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let inventory = FixedCameraLensInventory([.wide, .ultraWide, .telephoto])
        var stub: StubCameraFrameProvider?
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32, lens: .ultraWide, lenses: inventory) {
            (device: MTLDevice) -> any CameraFrameProvider in
            let made = StubCameraFrameProvider(device: device, scenario: .granted, lensInventory: inventory, failingLenses: [.telephoto])
            stub = made
            return made
        }
        let camera = try XCTUnwrap(stub)
        _ = inventory.offeredLenses(for: .back)
        XCTAssertEqual(camera.startCount, 0, "listing and creating the host start nothing")
        XCTAssertEqual(host.cameraLens, .ultraWide, "the chosen lens is set before any start")
        host.resume()
        defer { host.pause() }
        XCTAssertEqual(camera.state, .running)
        XCTAssertEqual(camera.session.configuredInputs.map(\.lens), [.ultraWide])

        host.cameraLens = .telephoto
        XCTAssertEqual(host.cameraLens, .ultraWide, "the previous lens keeps running")
        XCTAssertEqual(camera.state, .running)
        host.cameraLens = .wide
        XCTAssertEqual(camera.session.configuredInputs.map(\.lens), [.wide])
        XCTAssertTrue(host.isRunning, "the frame loop kept running")
        XCTAssertEqual(camera.startCount, 1, "switched without a restart")

        host.cameraPosition = .front
        host.cameraLens = .ultraWide
        XCTAssertEqual(camera.session.configuredInputs.first?.position, .front, "front keeps its wide lens")
        host.cameraPosition = .back
        XCTAssertEqual(camera.session.configuredInputs.map(\.lens), [.ultraWide], "back restores the chosen lens")
    }
}
