// OutputProfileAppTests.swift — OUT-014-T09, T10 (specs/288-out-014-output-profile-export; contract C2): the roadmap
// acceptance, "Import/export reproduces calibration on same display class". A real ExternalDisplayCoordinator gets a
// device slot, a stand-in visual and external stand-in displays built like the app's (`ExternalDisplayViewController`
// in an off-screen window with OUT-011's stand-in readings). Custom calibration and corner pin → export → reset
// everything → import: every setting, the external slot's `sublayerTransform` and the calibration the slot hands the
// held visual equal the originals, without a warning; on a 1280 × 720 stand-in the same file warns first. Invalid files
// change nothing; the file carries no identifiers. Simulator results are never device evidence (OUT-014-T13 is).
import Compositor
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class OutputProfileAppTests: XCTestCase {
    private struct Rig {
        let external: ExternalDisplayCoordinator
        let setting: ExternalOutputSetting
        let profiles: OutputProfileCoordinator
        let defaults: UserDefaults
        let suite: String
    }

    private func scene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }).first else {
            throw XCTSkip("No window scene in the test host")
        }
        return scene
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("out014-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func rig() throws -> Rig {
        let name = "out014-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        let external = ExternalDisplayCoordinator()
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        external.registerDeviceSlot(device)
        external.show(UIView())
        external.visualizerActive(true)
        let setting = ExternalOutputSetting(defaults: defaults, external: external)
        let profiles = OutputProfileCoordinator(simulation: false, temporaryDirectory: try temporaryFolder())
        return Rig(external: external, setting: setting, profiles: profiles, defaults: defaults, suite: name)
    }

    /// An off-screen stand-in display of `width` × `height` points at scale 1 with stand-in screen readings.
    private func connect(_ coordinator: ExternalDisplayCoordinator, id: String, width: Int, height: Int) throws -> VisualSlotView {
        let window = UIWindow(windowScene: try scene())
        window.frame = CGRect(x: 100_000, y: 0, width: CGFloat(width), height: CGFloat(height))
        window.windowLevel = .normal - 1
        let controller = ExternalDisplayViewController()
        controller.slot.traitOverrides.displayScale = 1
        controller.slot.standInReadings = UITestExternalDisplay.standInReadings(width: width, height: height)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        addTeardownBlock { @MainActor in window.isHidden = true }
        let slot = controller.slot
        coordinator.externalConnected(id: id, slot: slot, geometry: slot.geometry, foreground: true)
        slot.layoutIfNeeded()
        return slot
    }

    private func customize(_ setting: ExternalOutputSetting) throws {
        setting.cornerPin = try XCTUnwrap(CornerPin(topLeft: CornerPinPoint(x: 0.08, y: 0.04), topRight: CornerPinPoint(x: 0.95, y: 0),
                                                    bottomRight: CornerPinPoint(x: 1, y: 0.97), bottomLeft: CornerPinPoint(x: 0.02, y: 0.9)))
        setting.calibration = DisplayCalibration(gamma: 1.37, red: 0.8, green: 1.05, blue: 1.2)
        setting.outputMode = .clean
        setting.fit = .fill
        setting.pixelAspect = .wide
        setting.resolutionMode = .custom
        setting.resolutionPercent = 65
    }

    private static func values(_ t: CATransform3D) -> [Double] {
        [t.m11, t.m12, t.m13, t.m14, t.m21, t.m22, t.m23, t.m24, t.m31, t.m32, t.m33, t.m34, t.m41, t.m42, t.m43, t.m44]
            .map { (v: CGFloat) -> Double in Double(v) }
    }

    /// What the display shows: the slot's warp and the calibration it hands the held visual.
    private struct Output: Equatable {
        var transform: [Double]
        var calibration: DisplayCalibration
    }

    private func output(_ slot: VisualSlotView) -> Output {
        Output(transform: Self.values(slot.layer.sublayerTransform), calibration: slot.calibration)
    }

    // MARK: - T09: the acceptance

    func testRoundTripOnTheSameDisplayClassReproducesTheOutputWithoutAWarning() throws {
        let r: Rig = try rig()
        let slot: VisualSlotView = try connect(r.external, id: "stand-in", width: 1920, height: 1080)
        try customize(r.setting)
        let original: OutputProfile = r.setting.outputProfile(display: nil)
        let shown: Output = output(slot)
        XCTAssertFalse(CATransform3DIsIdentity(slot.layer.sublayerTransform), "the pin is live")
        XCTAssertFalse(shown.calibration.isIdentity)

        XCTAssertTrue(r.profiles.prepareExport(r.setting))
        let file: URL = try XCTUnwrap(r.profiles.exportFile)
        XCTAssertTrue(r.profiles.showMover, "the system file export opens")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let data: Data = try XCTUnwrap(r.profiles.lastExport)
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertEqual(try OutputProfileDocument.decode(data).display?.nativeWidth, 1920, "the display class is in the file")
        r.profiles.exportCancelled()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path), "no temporary copy is left")

        r.setting.apply(OutputProfile())   // reset everything
        XCTAssertTrue(CATransform3DIsIdentity(slot.layer.sublayerTransform))
        XCTAssertTrue(slot.calibration.isIdentity)

        r.profiles.importData(data, into: r.setting)
        XCTAssertNil(r.profiles.pending, "same class: no warning")
        XCTAssertEqual(r.profiles.message, OutputProfileCoordinator.appliedText)
        XCTAssertEqual(r.setting.outputProfile(display: nil), original, "every setting, exactly")
        XCTAssertEqual(output(slot), shown, "the display's warp and calibration equal the originals, inside the call")
        XCTAssertEqual(r.external.calibrationSummary.components(separatedBy: " values=").last, "1.37,0.8,1.05,1.2")
        XCTAssertEqual(r.defaults.string(forKey: ExternalOutputSetting.calibrationKey), "1.37,0.8,1.05,1.2", "persisted in the usual key")
        XCTAssertEqual(r.defaults.string(forKey: ExternalOutputSetting.cornerPinKey), original.cornerPin.stored)
        let domain: [String: Any] = r.defaults.persistentDomain(forName: r.suite) ?? [:]
        let written = Set<String>(domain.keys)
        XCTAssertFalse(written.isEmpty)
        XCTAssertTrue(written.isSubset(of: Set(ExternalOutputSetting.keys)), "no new keys: \(written)")
    }

    func testADifferentDisplayClassWarnsBeforeAnythingChanges() throws {
        let r: Rig = try rig()
        _ = try connect(r.external, id: "big", width: 1920, height: 1080)
        try customize(r.setting)
        let original: OutputProfile = r.setting.outputProfile(display: nil)
        XCTAssertTrue(r.profiles.prepareExport(r.setting))
        let data: Data = try XCTUnwrap(r.profiles.lastExport)
        r.profiles.exportFinished(.success(try XCTUnwrap(r.profiles.exportFile)))
        XCTAssertEqual(r.profiles.message, OutputProfileCoordinator.exportedText)
        r.external.externalDisconnected(id: "big")
        let small: VisualSlotView = try connect(r.external, id: "small", width: 1280, height: 720)
        r.setting.apply(OutputProfile())
        let reset: Output = output(small)

        r.profiles.importData(data, into: r.setting)
        let pending = try XCTUnwrap(r.profiles.pending, "a different class warns")
        XCTAssertEqual(pending.differences, [.resolution])
        XCTAssertTrue(pending.text.contains("1920 × 1080 px") && pending.text.contains("1280 × 720 px"), pending.text)
        XCTAssertEqual(r.setting.outputProfile(display: nil), OutputProfile(), "nothing changes before the choice")
        XCTAssertEqual(output(small), reset)
        r.profiles.cancelPending()
        XCTAssertEqual(r.profiles.message, OutputProfileCoordinator.cancelledText)
        XCTAssertEqual(r.setting.outputProfile(display: nil), OutputProfile(), "Cancel changes nothing")

        r.profiles.importData(data, into: r.setting)
        r.profiles.applyPending(into: r.setting)
        XCTAssertNil(r.profiles.pending)
        XCTAssertEqual(r.profiles.message, OutputProfileCoordinator.appliedText)
        XCTAssertEqual(r.setting.outputProfile(display: nil), original, "Apply Anyway applies everything")
        XCTAssertEqual(small.calibration, DisplayCalibration(gamma: 1.37, red: 0.8, green: 1.05, blue: 1.2))
        XCTAssertFalse(CATransform3DIsIdentity(small.layer.sublayerTransform))
    }

    func testWithoutADisplayTheProfileAppliesUnchecked() throws {
        let r: Rig = try rig()
        try customize(r.setting)
        let original: OutputProfile = r.setting.outputProfile(display: nil)
        XCTAssertTrue(r.profiles.prepareExport(r.setting))
        let data: Data = try XCTUnwrap(r.profiles.lastExport)
        r.profiles.exportCancelled()
        XCTAssertNil(try OutputProfileDocument.decode(data).display, "no display: no class in the file")
        r.setting.apply(OutputProfile())
        r.profiles.importData(data, into: r.setting)
        XCTAssertNil(r.profiles.pending)
        XCTAssertEqual(r.profiles.message, OutputProfileCoordinator.uncheckedText)
        XCTAssertEqual(r.setting.outputProfile(display: nil), original)
    }

    // MARK: - T10: invalid files change nothing

    private func edited(_ data: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var settings = try XCTUnwrap(top["settings"] as? [String: Any])
        edit(&settings)
        top["settings"] = settings
        return try JSONSerialization.data(withJSONObject: top)
    }

    func testInvalidFilesChangeNothing() throws {
        let r: Rig = try rig()
        let slot: VisualSlotView = try connect(r.external, id: "stand-in", width: 1920, height: 1080)
        try customize(r.setting)
        let before: OutputProfile = r.setting.outputProfile(display: nil)
        let shown: Output = output(slot)
        XCTAssertTrue(r.profiles.prepareExport(r.setting))
        let good: Data = try XCTUnwrap(r.profiles.lastExport)
        r.profiles.exportCancelled()
        let bowTie: Data = try edited(good) { (settings: inout [String: Any]) in
            var corners = settings["cornerPin"] as? [Any] ?? []
            corners.swapAt(1, 2)   // top-right and bottom-right swapped: a self-intersecting bow tie
            settings["cornerPin"] = corners
        }
        let badCalibration: Data = try edited(good) { (settings: inout [String: Any]) in
            settings["calibration"] = ["gamma": 9.0, "red": 1.0, "green": 1.0, "blue": 1.0]
        }
        for (name, bytes) in [("bow tie", bowTie), ("calibration", badCalibration),
                              ("truncated", good.prefix(good.count / 2)), ("empty", Data())] {
            XCTAssertNotEqual(bytes, good, name)
            r.profiles.importData(bytes, into: r.setting)
            XCTAssertNil(r.profiles.pending, name)
            XCTAssertTrue(r.profiles.message?.hasPrefix("Could not import: ") == true, "\(name): \(r.profiles.message ?? "nil")")
            XCTAssertEqual(r.setting.outputProfile(display: nil), before, "\(name): nothing applied")
            XCTAssertEqual(output(slot), shown, name)
        }
    }

    // MARK: - T09: privacy and the shared rule

    func testTheExportedFileHoldsNoIdentifiers() throws {
        let r: Rig = try rig()
        _ = try connect(r.external, id: "uitest-external-display-7F3A", width: 1920, height: 1080)
        try customize(r.setting)
        XCTAssertTrue(r.profiles.prepareExport(r.setting))
        let text = String(decoding: try XCTUnwrap(r.profiles.lastExport), as: UTF8.self)
        r.profiles.exportCancelled()
        var forbidden: [String] = [UIDevice.current.name, "uitest-external-display-7F3A", "stand-in"]
        if let vendor = UIDevice.current.identifierForVendor?.uuidString { forbidden.append(vendor) }
        for value in forbidden where !value.isEmpty {
            XCTAssertFalse(text.contains(value), "the file contains \(value)")
        }
        let patterns: [String] = ["[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",   // UUID
                                  "\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b",                         // IPv4
                                  "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", "\"name\"", "http"]
        for pattern in patterns {
            XCTAssertNil(text.range(of: pattern, options: .regularExpression), "the file matches \(pattern):\n\(text)")
        }
    }

    func testTheImportRangesAreTheSettingsRanges() {
        XCTAssertEqual(OutputProfile.Calibration.gammaRange, DisplayCalibration.gammaRange)
        XCTAssertEqual(OutputProfile.Calibration.trimRange, DisplayCalibration.trimRange)
    }
}
