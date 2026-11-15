// DisplayCalibrationAppTests.swift — OUT-009-T09, T12 (specs/268-out-009-output-color-calibration; contract C3-C6). The
// external stand-in display is built like the app's (`ExternalDisplayViewController` in an off-screen window).
// T09, the row's acceptance ("calibration changes output but leaves saved scene parameters untouched"): a Photo
// visual (a compositor host) on the external stand-in renders the transfer function's prediction of its uncalibrated
// pixels once the setting changes, while its recording output stays the uncalibrated frame; back on the device slot it
// is uncalibrated again; the scene document's bytes, the scene inputs and the autosave revision are identical before
// and after; a native spectrum view reports "unsupported"; the blackout still reads black; a recording hold does not
// defer it. T12: the preference. Simulator results are never device evidence (OUT-009-T14 is).
import Compositor
import Metal
import PresentationLifecycle
import SceneFormat
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class DisplayCalibrationAppTests: XCTestCase {
    private let calibration = DisplayCalibration(gamma: 1.5, red: 0.8, green: 1, blue: 1.2)

    private func defaults() throws -> UserDefaults {
        let name = "out009-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    private func externalWindow() throws -> VisualSlotView {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }.first)
        let controller = ExternalDisplayViewController()
        controller.slot.traitOverrides.displayScale = 1
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 100_000, y: 0, width: 640, height: 360)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        addTeardownBlock { @MainActor in window.isHidden = true }
        return controller.slot
    }

    /// Four stripes: mid grey, orange, dark blue, white.
    private func stripes() throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let colors: [UIColor] = [UIColor(white: 0.5, alpha: 1), UIColor(red: 1, green: 0.5, blue: 0.1, alpha: 1),
                                 UIColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1), .white]
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90), format: format).image { (c: UIGraphicsImageRendererContext) in
            for (i, color) in colors.enumerated() {
                color.setFill()
                c.fill(CGRect(x: i * 40, y: 0, width: 40, height: 90))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("out009-\(UUID().uuidString).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func poll(_ description: String, timeout: Double = 10, _ condition: @MainActor () -> Bool) async throws {
        var waited: Double = 0
        while !condition() {
            if waited >= timeout {
                XCTFail("timed out: \(description)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
            waited += 0.02
        }
    }

    /// One frame of the host's own compositor into a 64 × 36 screen texture (the host's format) and its recording
    /// output; returns both as encoded RGB rows.
    private func frame(_ host: PhotoVisualHost, _ queue: MTLCommandQueue, time: UInt64) throws -> (screen: [SIMD3<Double>], recording: [SIMD3<Double>]) {
        let device: MTLDevice = queue.device
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 64, height: 36, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        let screen = try XCTUnwrap(device.makeTexture(descriptor: d)), recording = try XCTUnwrap(device.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertTrue(host.compositor.composite(into: screen, commandBuffer: commands, presentationTimeNanoseconds: time,
                                                contentScale: 1, reduceFlashing: false, audio: .empty))
        XCTAssertTrue(host.compositor.encodeOutput(into: recording, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        return (Self.read(screen), Self.read(recording))
    }

    private static func read(_ texture: MTLTexture) -> [SIMD3<Double>] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            if let base = raw.baseAddress {
                texture.getBytes(base, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            }
        }
        var out: [SIMD3<Double>] = []
        for i in 0..<(texture.width * texture.height) {   // BGRA
            out.append(SIMD3<Double>(Double(bytes[i * 4 + 2]) / 255, Double(bytes[i * 4 + 1]) / 255, Double(bytes[i * 4]) / 255))
        }
        return out
    }

    /// One carry for every capture (a fresh carry draws a new scene id).
    private let carry = SceneAutosaveCarry.fresh()

    /// The scene document the autosave would write now (its bytes).
    private func sceneBytes(_ coordinator: AppCoordinator) -> [UInt8] {
        SceneAutosaveCapture.document(coordinator.sceneInputs, carry: carry, liveBindings: nil).document.encoded()
    }

    /// T09 (OUT-009-R2 to R7, S2 to S4): the acceptance.
    func testCalibrationChangesTheExternalOutputButNotTheSceneTheRecordingOrTheDevice() async throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw XCTSkip("no Metal device") }
        let external = ExternalDisplayCoordinator()
        external.usesDisplayLink = false
        let coordinator = AppCoordinator(defaults: try defaults(), externalDisplay: external)
        let bytesBefore: [UInt8] = sceneBytes(coordinator)
        let inputsBefore: SceneInputs = coordinator.sceneInputs
        let revisionBefore: Int? = coordinator.sceneAutosave?.editRevision
        XCTAssertTrue(sceneBytes(coordinator) == bytesBefore, "the capture is deterministic")

        let photo = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        photo.content = .file(try stripes())
        let deviceSlot = VisualSlotView(role: .device)
        deviceSlot.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        external.registerDeviceSlot(deviceSlot)
        external.show(photo.view)
        external.visualizerActive(true)
        let slot = try externalWindow()
        external.externalConnected(id: "stand-in", slot: slot, geometry: slot.geometry, foreground: true)
        XCTAssertTrue(photo.view.superview === slot, "the visual is on the external display")
        photo.resume()
        defer { photo.pause() }
        try await poll("the picture is shown") { photo.framesShown > 2 }
        photo.pause()   // frames below are driven by the test
        XCTAssertEqual(external.calibrationSummary, "cal=identity applied=no values=1,1,1,1")

        let plain = try frame(photo, queue, time: 1_000_000_000)
        XCTAssertEqual(plain.screen, plain.recording, "uncalibrated: screen = recording")
        XCTAssertTrue(plain.screen.contains { (p: SIMD3<Double>) -> Bool in p.x > 0.2 && p.y > 0.2 }, "the picture has content")

        coordinator.externalOutput.calibration = calibration
        XCTAssertEqual(photo.compositor.displayCalibration, calibration, "applied to the visual inside the call")
        XCTAssertEqual(external.calibrationSummary, "cal=custom applied=yes values=1.5,0.8,1,1.2")
        let calibrated = try frame(photo, queue, time: 1_016_666_667)
        XCTAssertEqual(calibrated.recording, plain.screen, "the recording output stays uncalibrated (content)")
        var changed = 0
        for (i, p) in plain.screen.enumerated() {
            let expected: SIMD3<Double> = calibration.apply(encoded: p)
            for c in 0..<3 { XCTAssertEqual(calibrated.screen[i][c], expected[c], accuracy: 2.0 / 255, "pixel \(i) channel \(c)") }
            if calibrated.screen[i] != p { changed += 1 }
        }
        XCTAssertGreaterThan(changed, plain.screen.count / 2, "the external output changed")

        // The show is untouched (OUT-009-R5, S3).
        XCTAssertTrue(sceneBytes(coordinator) == bytesBefore, "scene document bytes identical")
        XCTAssertEqual(coordinator.sceneInputs, inputsBefore, "saved scene parameters identical")
        XCTAssertEqual(coordinator.sceneAutosave?.editRevision, revisionBefore, "no autosave edit")

        // OUT-009-R6: live during a recording hold; R7: the blackout still covers everything.
        external.holdsPlacement = true
        coordinator.externalOutput.calibration = .identity
        XCTAssertTrue(photo.compositor.displayCalibration.isIdentity, "not deferred by the hold")
        coordinator.externalOutput.calibration = calibration
        external.holdsPlacement = false
        external.setBlackout(true)
        XCTAssertTrue(external.isOutputBlack)
        external.setBlackout(false)

        // Back on the device (OUT-009-R4): uncalibrated, the same pixels as before.
        external.externalDisconnected(id: "stand-in")
        XCTAssertTrue(photo.view.superview === deviceSlot)
        XCTAssertTrue(photo.compositor.displayCalibration.isIdentity, "the device is never calibrated")
        XCTAssertEqual(try frame(photo, queue, time: 1_033_333_334).screen, plain.screen)
        XCTAssertEqual(external.calibrationSummary, "cal=custom applied=none values=1.5,0.8,1,1.2")

        // A native spectrum (no final pass) is shown uncalibrated and says so (OUT-009-R3).
        let spectrumView = NativeSpectrumLayerView(device: device)
        external.show(spectrumView)
        external.externalConnected(id: "stand-in-2", slot: slot, geometry: slot.geometry, foreground: true)
        XCTAssertTrue(spectrumView.superview === slot)
        XCTAssertFalse(spectrumView.acceptsDisplayCalibration)
        XCTAssertEqual(external.calibrationSummary, "cal=custom applied=unsupported values=1.5,0.8,1,1.2")
        XCTAssertTrue(sceneBytes(coordinator) == bytesBefore, "still identical")
    }

    /// T12 (OUT-009-R9, S5): the calibration persists; the identity removes it; bad stored values read the identity.
    func testTheCalibrationPersistsAndReadsSafely() throws {
        let defaults = try defaults()
        let external = ExternalDisplayCoordinator()
        let setting = ExternalOutputSetting(defaults: defaults, external: external)
        XCTAssertEqual(setting.calibration, .identity)
        XCTAssertNil(defaults.object(forKey: ExternalOutputSetting.calibrationKey), "nothing stored until changed")
        setting.calibration = calibration
        XCTAssertEqual(defaults.string(forKey: ExternalOutputSetting.calibrationKey), "1.5,0.8,1,1.2")
        XCTAssertEqual(external.displayCalibration, calibration, "applied live")
        let relaunched = ExternalDisplayCoordinator()
        XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: relaunched).calibration, calibration, "persisted")
        XCTAssertEqual(relaunched.displayCalibration, calibration, "applied at launch")
        setting.calibration = .identity
        XCTAssertNil(defaults.object(forKey: ExternalOutputSetting.calibrationKey), "identity is stored as absent")
        defaults.set("9,0,1,1", forKey: ExternalOutputSetting.calibrationKey)
        XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: ExternalDisplayCoordinator()).calibration,
                       DisplayCalibration(gamma: 2.5, red: 0.5, green: 1, blue: 1), "clamped")
        for bad in ["garbage", "1,1,1"] {
            defaults.set(bad, forKey: ExternalOutputSetting.calibrationKey)
            XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: ExternalDisplayCoordinator()).calibration, .identity, bad)
        }
        XCTAssertTrue(ExternalOutputSetting.keys.contains("settings.externalDisplay.calibration"), "device-local, excluded from backup")
        XCTAssertEqual(DisplayCalibrationParameterSpecs.setting(.red, 0.8234, in: .identity).red, 0.82, accuracy: 1e-12, "slider grid")
    }
}
