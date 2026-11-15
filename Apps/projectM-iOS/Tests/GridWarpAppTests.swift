// GridWarpAppTests.swift — OUT-008-T12 (specs/309-out-008-grid-warp; contract C4, C5). The external stand-in display is
// built like the app's (`ExternalDisplayViewController` in an off-screen window), as in DisplayCalibrationAppTests.
// * A Photo visual (a compositor host) on the stand-in: the identity runs no warp pass and its screen equals its
//   recording; a custom mesh reaches the compositor inside the call and changes the screen while the recording output
//   stays the unwarped frame; the corner pin applies on top (OUT-008-R6); a recording hold never defers a change
//   (R11); the editor's guides reach the display even for the identity; back on the device slot nothing is warped
//   (R8); a native spectrum reports "unsupported"; the rehearsal preview's slot never takes the mesh.
// * The preference: absent, stored, malformed and invalid values; the key list; an output profile carries it.
// Simulator results are never device evidence (OUT-008-T15 is).
import Compositor
import Metal
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class GridWarpAppTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "out008-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    /// A valid 3 × 3 mesh with the centre moved.
    private func bent() throws -> GridWarp {
        var points: [GridWarpPoint] = GridWarp.identity.points
        points[4] = GridWarpPoint(x: 0.6, y: 0.42)
        return try XCTUnwrap(GridWarp(columns: 3, rows: 3, points: points))
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

    /// Four vertical stripes, so a bend moves visible edges.
    private func stripes() throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let colors: [UIColor] = [UIColor(white: 0.5, alpha: 1), .orange, .blue, .white]
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90), format: format).image { (c: UIGraphicsImageRendererContext) in
            for (i, color) in colors.enumerated() {
                color.setFill()
                c.fill(CGRect(x: i * 40, y: 0, width: 40, height: 90))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("out008-\(UUID().uuidString).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func poll(_ description: String, timeout: Double = 10, _ condition: @MainActor () -> Bool) async throws {
        var waited: Double = 0
        while !condition() {
            if waited >= timeout { return XCTFail("timed out: \(description)") }
            try await Task.sleep(for: .milliseconds(20))
            waited += 0.02
        }
    }

    /// One frame of the host's compositor into a 64 × 36 screen texture and its recording output (raw bytes).
    private func frame(_ host: PhotoVisualHost, _ queue: MTLCommandQueue, time: UInt64) throws -> (screen: [UInt8], recording: [UInt8]) {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 64, height: 36, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        let screen = try XCTUnwrap(queue.device.makeTexture(descriptor: d))
        let recording = try XCTUnwrap(queue.device.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertTrue(host.compositor.composite(into: screen, commandBuffer: commands, presentationTimeNanoseconds: time,
                                                contentScale: 1, reduceFlashing: false, audio: .empty))
        XCTAssertTrue(host.compositor.encodeOutput(into: recording, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        return (Self.bytes(screen), Self.bytes(recording))
    }

    private static func bytes(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            if let base = raw.baseAddress {
                texture.getBytes(base, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            }
        }
        return bytes
    }

    /// OUT-008-R2, R6 to R8, R11; S1, S4.
    func testTheMeshReachesTheExternalOutputOnlyAndNeverTheRecording() async throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw XCTSkip("no Metal device") }
        let external = ExternalDisplayCoordinator()
        external.usesDisplayLink = false
        let coordinator = AppCoordinator(defaults: try defaults(), externalDisplay: external)
        let photo = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        photo.content = .file(try stripes())
        let deviceSlot = VisualSlotView(role: .device)
        deviceSlot.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        external.registerDeviceSlot(deviceSlot)
        external.show(photo.view)
        external.visualizerActive(true)
        let slot = try externalWindow()
        external.externalConnected(id: "stand-in", slot: slot, geometry: slot.geometry, foreground: true)
        XCTAssertTrue(photo.view.superview === slot)
        photo.resume()
        defer { photo.pause() }
        try await poll("the picture is shown") { photo.framesShown > 2 }
        photo.pause()
        XCTAssertEqual(external.gridWarpSummary, "warp=identity grid=3x3 guides=off applied=no")
        XCTAssertEqual(photo.compositor.outputWarp, .none, "the identity runs no pass")
        let plain = try frame(photo, queue, time: 1_000_000_000)
        XCTAssertEqual(plain.screen, plain.recording)
        XCTAssertEqual(photo.compositor.warpedFrames, 0)

        let warp: GridWarp = try bent()
        coordinator.externalOutput.gridWarp = warp
        XCTAssertEqual(photo.compositor.outputWarp, warp.outputMesh(showsGuides: false), "applied inside the call")
        XCTAssertEqual(external.gridWarpSummary, "warp=custom grid=3x3 guides=off applied=yes")
        let warped = try frame(photo, queue, time: 1_016_666_667)
        XCTAssertEqual(photo.compositor.warpedFrames, 1)
        XCTAssertEqual(warped.recording, plain.screen, "the recording output stays unwarped (content)")
        XCTAssertNotEqual(warped.screen, plain.screen, "the external output changed")

        // R6: the corner pin maps the slot on top; the mesh stays with the visual.
        coordinator.externalOutput.cornerPin = CornerPin.identity.nudging(.topLeft, dx: 0.05, dy: 0.05)
        XCTAssertFalse(CATransform3DIsIdentity(slot.layer.sublayerTransform), "corner pin on the slot")
        XCTAssertEqual(slot.warpState, "yes", "grid warp still drawn by the visual")
        // R11: never deferred by a recording hold.
        external.holdsPlacement = true
        coordinator.externalOutput.gridWarp = .identity
        XCTAssertEqual(photo.compositor.outputWarp, .none, "not deferred by the hold")
        coordinator.externalOutput.gridWarp = warp
        external.holdsPlacement = false
        // R5: the editor's guides, even on the identity.
        coordinator.externalOutput.gridWarp = .identity
        external.beginGridWarpEditing()
        XCTAssertEqual(photo.compositor.outputWarp, .identity(columns: 3, rows: 3, showsGuides: true))
        XCTAssertEqual(external.gridWarpSummary, "warp=identity grid=3x3 guides=on applied=yes")
        external.endGridWarpEditing()
        XCTAssertEqual(photo.compositor.outputWarp, .none)
        coordinator.externalOutput.gridWarp = warp

        // R8: the rehearsal preview's slot never takes the mesh.
        let preview = RehearsalPreviewView(content: UIView())
        XCTAssertEqual(preview.slot.outputWarp, .none)

        // Back on the device: nothing is warped.
        external.externalDisconnected(id: "stand-in")
        XCTAssertTrue(photo.view.superview === deviceSlot)
        XCTAssertEqual(photo.compositor.outputWarp, .none, "the device is never warped")
        XCTAssertEqual(try frame(photo, queue, time: 1_033_333_334).screen, plain.screen)

        // A native spectrum (no final pass) is not covered and says so.
        let spectrumView = NativeSpectrumLayerView(device: device)
        external.show(spectrumView)
        external.externalConnected(id: "stand-in-2", slot: slot, geometry: slot.geometry, foreground: true)
        XCTAssertFalse(spectrumView.acceptsOutputWarp)
        XCTAssertEqual(external.gridWarpSummary, "warp=custom grid=3x3 guides=off applied=unsupported")
    }

    /// OUT-008-R4, R9, R10; S5.
    func testTheMeshPersistsReadsSafelyAndTravelsInProfiles() throws {
        let defaults = try defaults()
        let external = ExternalDisplayCoordinator()
        let setting = ExternalOutputSetting(defaults: defaults, external: external)
        XCTAssertEqual(setting.gridWarp, .identity)
        XCTAssertNil(defaults.object(forKey: ExternalOutputSetting.gridWarpKey), "nothing stored until changed")
        let warp: GridWarp = try bent()
        setting.gridWarp = warp
        XCTAssertEqual(defaults.string(forKey: ExternalOutputSetting.gridWarpKey), warp.stored)
        XCTAssertEqual(external.gridWarp, warp, "applied live")
        let relaunched = ExternalDisplayCoordinator()
        XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: relaunched).gridWarp, warp, "persisted")
        XCTAssertEqual(relaunched.gridWarp, warp, "applied at launch")

        // An output profile carries it; applying a profile restores it (no new key).
        let profile: OutputProfile = setting.outputProfile(display: nil)
        setting.gridWarp = .identity
        XCTAssertNil(defaults.object(forKey: ExternalOutputSetting.gridWarpKey), "identity is stored as absent")
        setting.apply(try OutputProfileDocument.decode(OutputProfileDocument.encode(profile)))
        XCTAssertEqual(setting.gridWarp, warp)

        var swapped: [GridWarpPoint] = GridWarp.identity.points
        swapped.swapAt(0, 1)
        let folded: String = GridWarp.candidate(columns: 3, rows: 3, points: swapped).stored
        for bad in ["garbage", "3x3:0,0", "12x3:" + warp.stored.dropFirst(4), folded] {
            defaults.set(bad, forKey: ExternalOutputSetting.gridWarpKey)
            XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: ExternalDisplayCoordinator()).gridWarp, .identity, bad)
        }
        XCTAssertTrue(ExternalOutputSetting.keys.contains("settings.externalDisplay.gridWarp"), "device-local, excluded from backup")
        // R4: an edit that would fold is refused with a reason in words; the mesh stays.
        guard case .refused(let why) = warp.moving(row: 1, column: 1, to: GridWarpPoint(x: 1, y: 0)) else {
            return XCTFail("a folding edit is refused")
        }
        XCTAssertFalse(ExternalOutputSetting.reason(why).isEmpty)
        XCTAssertEqual(ExternalOutputSetting.spokenValue(GridWarpPoint(x: 0.52, y: 0.475)), "52 % across, 47.5 % down")
    }
}
