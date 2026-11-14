// CameraRecoveryTests.swift — CAM-013-T11, T13, T14: camera failure recovery in the Camera visual
// host with the stand-in camera (CAM-013-R1 to R11; S1 to S5). The acceptance test composites the
// host offscreen and reads pixels: an injected interruption leaves no camera pixel and offers Retry;
// Retry brings the camera back. Time is a fake clock with a manual scheduler (no wall-clock
// assertion). Host tests need a Metal device and skip without one. No test asks for camera access.
import AVFoundation
import CameraLayer
import Metal
import XCTest
@testable import projectM_iOS

/// A fake monotonic clock and a scheduler that runs closures only when the test advances the clock.
@MainActor
private final class ManualTime {
    var now: Double = 1_000
    private var queued: [(due: Double, action: @MainActor () -> Void)] = []

    var pendingCount: Int { queued.count }

    func schedule(_ delay: Double, _ action: @escaping @MainActor () -> Void) {
        let due: Double = now + delay
        queued.append((due, action))
    }

    /// Moves the clock forward and runs every closure that became due, in order.
    func advance(by seconds: Double) {
        now += seconds
        let due = queued.filter { (entry: (due: Double, action: @MainActor () -> Void)) -> Bool in entry.due <= now }
        queued.removeAll { (entry: (due: Double, action: @MainActor () -> Void)) -> Bool in entry.due <= now }
        for entry in due { entry.action() }
    }
}

@MainActor
final class CameraRecoveryTests: XCTestCase {
    private static let side = 64
    private let orange = StubCameraFrameProvider.Color(red: 230, green: 120, blue: 30)

    private func makeHost(_ scenario: CameraScenario = .granted) throws -> (CameraVisualHost, StubCameraFrameProvider, ManualTime) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        var stub: StubCameraFrameProvider?
        let color = orange
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32) { (device: MTLDevice) -> any CameraFrameProvider in
            let made = StubCameraFrameProvider(device: device, scenario: scenario, pattern: .solid(color))
            stub = made
            return made
        }
        let time = ManualTime()
        host.clock = { () -> Double in time.now }
        host.scheduler = { (delay: Double, action: @escaping @MainActor () -> Void) -> Void in time.schedule(delay, action) }
        return (host, try XCTUnwrap(stub), time)
    }

    /// The notice the visualizer shows for the host's state (the catalog the view uses).
    private func notice(_ host: CameraVisualHost) -> PermissionNotice? {
        PermissionCatalog.cameraNotice(for: host.feedState, position: .back, reason: host.stopReason)
    }

    // MARK: - Pixels

    /// One offscreen composite of the host at `time` seconds; returns how many pixels show the
    /// stand-in's orange.
    private func cameraPixels(_ host: CameraVisualHost, time seconds: UInt64) throws -> Int {
        let time: UInt64 = seconds * 1_000_000_000
        let device = host.compositor.device
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: Self.side, height: Self.side, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(device.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertTrue(host.compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: time,
                                                contentScale: 2, reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        let rowBytes: Int = Self.side * 4
        let length: Int = rowBytes * Self.side
        let buffer = try XCTUnwrap(device.makeBuffer(length: length, options: .storageModeShared))
        let copy = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(copy.makeBlitCommandEncoder())
        blit.copy(from: output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: Self.side, height: Self.side, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: length)
        blit.endEncoding()
        copy.commit()
        copy.waitUntilCompleted()
        let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: length)
        var count = 0
        for index in stride(from: 0, to: length, by: 4) {
            let blue: Int = Int(bytes[index])
            let green: Int = Int(bytes[index + 1])
            let red: Int = Int(bytes[index + 2])
            let isOrange: Bool = red > 200 && green > 90 && green < 150 && blue < 60
            if isOrange { count += 1 }
        }
        return count
    }

    // MARK: - The acceptance (T11; R1, R2, R5, S1, S2)

    /// "Injected interruption clears last frame and offers retry."
    func testInjectedInterruptionClearsTheLastFrameAndOffersRetry() throws {
        let (host, stub, _) = try makeHost()
        host.resume()
        XCTAssertEqual(host.feedState, .running)
        let before: Int = try cameraPixels(host, time: 1)
        XCTAssertGreaterThan(before, 1_000, "the camera covers most of the picture (\(before) of 4096)")

        stub.interrupt(.anotherApp)
        let during: Int = try cameraPixels(host, time: 2)
        XCTAssertEqual(during, 0, "no camera pixel once interrupted: the last frame is cleared")
        let shown = try XCTUnwrap(notice(host), "the notice is shown")
        XCTAssertTrue(shown.offersRetry, "it offers Retry")
        XCTAssertFalse(shown.offersSettings)
        XCTAssertEqual(shown.text, CameraStopReason.anotherApp.notice)
        XCTAssertFalse(CameraIndicator(state: host.feedState).isShown, "the badge never says Camera on while interrupted")

        let starts: Int = stub.startCount
        host.retryCamera()
        XCTAssertEqual(stub.startCount, starts + 1, "Retry starts the camera again at once")
        XCTAssertEqual(stub.stopCount, 1, "after a full stop (picture dropped, session released)")
        XCTAssertEqual(host.feedState, .running)
        XCTAssertNil(notice(host), "the notice goes")
        let after: Int = try cameraPixels(host, time: 3)
        XCTAssertEqual(after, before, "camera pixels are back")
        print("CAM-013 evidence: camera pixels before \(before), interrupted \(during), after Retry \(after) of 4096")
    }

    // MARK: - The table over every interruption reason (T11; R3, R4, R9, S3)

    func testEveryInterruptionReasonClearsExplainsAndReturnsByItself() throws {
        let (host, stub, _) = try makeHost()
        host.resume()
        var time: UInt64 = 1
        let interruptions: [CameraStopReason] = CameraStopReason.allCases.filter { (reason: CameraStopReason) -> Bool in reason.isInterruption }
        XCTAssertEqual(interruptions.count, 5)
        for reason in interruptions {
            // Five dark-bright pairs in ten composites would trip the composite flash guard (FX-019,
            // which clamps the frame time); real interruptions are far apart, so each starts afresh.
            host.compositor.resetFlashHistory()
            stub.interrupt(reason)
            XCTAssertEqual(host.feedState, .interrupted, "\(reason)")
            XCTAssertEqual(host.stopReason, reason, "\(reason)")
            XCTAssertEqual(try cameraPixels(host, time: time), 0, "\(reason): cleared")
            time += 1
            XCTAssertEqual(notice(host)?.text, reason.notice, "\(reason): its words")
            XCTAssertEqual(notice(host)?.offersRetry, true, "\(reason): Retry")
            XCTAssertFalse(CameraIndicator(state: host.feedState).isShown, "\(reason): badge hidden")
            XCTAssertTrue(reason.resumesWhenEnded, "\(reason): returns when the system says so")
            stub.endInterruption()
            XCTAssertEqual(host.feedState, .running, "\(reason): back without a tap")
            XCTAssertNil(host.stopReason)
            XCTAssertNil(notice(host), "\(reason): the notice goes")
            XCTAssertTrue(CameraIndicator(state: host.feedState).isShown, "\(reason): the badge returns")
            XCTAssertGreaterThan(try cameraPixels(host, time: time), 1_000, "\(reason): pictures return")
            time += 1
        }
        XCTAssertEqual(stub.startCount, 1, "no restart was needed")
        XCTAssertEqual(host.recovery.retries, 0)
        for reason in interruptions { XCTAssertEqual(host.recovery.counts[reason], 1, "\(reason) counted") }
    }

    // MARK: - Runtime errors and backoff (T13; R5-R7, R10, S4)

    func testRuntimeErrorThenRetryRecovers() throws {
        let (host, stub, _) = try makeHost()
        host.resume()
        stub.fail(.runtimeError)
        XCTAssertEqual(host.feedState, .failed)
        XCTAssertNil(stub.latestFrame(), "the picture is gone with the session")
        XCTAssertEqual(try cameraPixels(host, time: 1), 0)
        XCTAssertEqual(notice(host)?.text, CameraStopReason.runtimeError.notice)
        XCTAssertEqual(notice(host)?.offersRetry, true)
        XCTAssertFalse(host.retryPending, "no automatic retry for a plain error")
        host.retryCamera()
        XCTAssertEqual(host.feedState, .running)
        XCTAssertGreaterThan(try cameraPixels(host, time: 2), 1_000)
        XCTAssertEqual(host.recoveryProbe, "running|none|1|no|runtimeError:1,retries:1", "numbers only (R10)")
    }

    func testMediaResetIsRetriedOnceByItself() throws {
        let (host, stub, time) = try makeHost()
        host.resume()
        stub.fail(.mediaServicesReset)
        XCTAssertEqual(host.feedState, .failed, "never restarted inside the provider's callback")
        XCTAssertTrue(host.retryPending)
        time.advance(by: 0)
        XCTAssertEqual(host.feedState, .running, "the automatic retry ran")
        XCTAssertEqual(stub.startCount, 2)
        stub.fail(.mediaServicesReset)   // again, at once: the same run of failures
        XCTAssertFalse(host.retryPending, "only once per run")
        time.advance(by: 60)
        XCTAssertEqual(host.feedState, .failed, "the second reset waits for Retry")
        XCTAssertEqual(notice(host)?.text, CameraStopReason.mediaServicesReset.notice)
    }

    func testRetriesBackOffAndTapsInsideTheWaitStartOnce() throws {
        let (host, stub, time) = try makeHost()
        host.resume()
        stub.fail(.runtimeError)
        for _ in 0..<10 { host.retryCamera() }   // ten taps at the same instant
        XCTAssertEqual(stub.startCount, 2, "one start (plus the first)")
        var gaps: [Double] = []
        for _ in 0..<3 {
            stub.fail(.runtimeError)
            let tappedAt: Double = time.now
            host.retryCamera()
            XCTAssertTrue(host.retryPending, "the next attempt waits")
            XCTAssertEqual(host.feedState, .failed)
            host.retryCamera()
            XCTAssertEqual(time.pendingCount, 1, "a tap while waiting adds nothing")
            var waited: Double = 0
            while host.retryPending {
                time.advance(by: 0.5)
                waited += 0.5
            }
            XCTAssertEqual(host.feedState, .running)
            gaps.append(time.now - tappedAt)
            XCTAssertGreaterThan(waited, 0)
        }
        XCTAssertEqual(gaps, [2, 4, 8], "spaced 2, 4, 8 s after the previous attempt (taps at once after a failure)")
        XCTAssertEqual(stub.startCount, 5)
        XCTAssertEqual(host.recovery.counts[.runtimeError], 4)
    }

    func testReasonMappingFromTheSystem() {
        let table: [(AVCaptureSession.InterruptionReason?, CameraStopReason)] = [
            (.videoDeviceInUseByAnotherClient, .anotherApp),
            (.audioDeviceInUseByAnotherClient, .anotherApp),
            (.videoDeviceNotAvailableWithMultipleForegroundApps, .multitasking),
            (.videoDeviceNotAvailableDueToSystemPressure, .systemPressure),
            (.videoDeviceNotAvailableInBackground, .background),
            (nil, .otherInterruption),
        ]
        for (system, expected) in table {
            XCTAssertEqual(AVCameraFrameProvider.stopReason(interruption: system), expected, "\(String(describing: system))")
        }
        XCTAssertEqual(AVCameraFrameProvider.stopReason(error: .mediaServicesWereReset), .mediaServicesReset)
        XCTAssertEqual(AVCameraFrameProvider.stopReason(error: .unknown), .runtimeError)
        XCTAssertEqual(AVCameraFrameProvider.stopReason(error: nil), .runtimeError)
    }

    // MARK: - Revocation and background (T14; R8, R11, S5)

    func testDeniedAtStartShowsOpenSettingsWithoutRetry() throws {
        let (host, _, _) = try makeHost(.denied)
        host.resume()
        XCTAssertEqual(host.feedState, .denied)
        let shown = try XCTUnwrap(notice(host))
        XCTAssertEqual(shown, PermissionCatalog.notice(.camera, .denied), "FILE-013's denied notice")
        XCTAssertTrue(shown.offersSettings)
        XCTAssertFalse(shown.offersRetry)
        XCTAssertEqual(try cameraPixels(host, time: 1), 0)
        host.retryCamera()
        XCTAssertEqual(host.recovery.retries, 0, "Retry does nothing while denied")
    }

    func testWithdrawnAccessShowsTheDeniedNoticeOnTheNextRetry() throws {
        let (host, stub, _) = try makeHost()
        host.resume()
        stub.interrupt(.anotherApp)
        stub.withdrawAccess()
        host.retryCamera()
        XCTAssertEqual(host.feedState, .denied)
        XCTAssertEqual(notice(host)?.offersSettings, true)
        XCTAssertEqual(notice(host)?.offersRetry, false)
    }

    func testBackgroundCancelsAWaitingRetryAndTheReturnStartsFresh() throws {
        let (host, stub, time) = try makeHost()
        host.resume()
        stub.fail(.runtimeError)
        host.retryCamera()
        stub.fail(.runtimeError)
        host.retryCamera()
        XCTAssertTrue(host.retryPending)
        host.appEnteredBackground()
        XCTAssertEqual(stub.state, .idle, "the camera never runs in the background")
        XCTAssertFalse(host.retryPending, "the stop cancels the waiting retry")
        XCTAssertEqual(host.recovery.attempts, 0, "and starts a new run")
        let starts: Int = stub.startCount
        time.advance(by: 60)
        XCTAssertEqual(stub.startCount, starts, "the cancelled retry never runs")
        host.appWillEnterForeground()
        XCTAssertEqual(host.feedState, .running)
        XCTAssertNil(host.stopReason)
        XCTAssertNil(notice(host))
    }

    func testStopCameraEndsRecovery() throws {
        let (host, stub, time) = try makeHost()
        host.resume()
        stub.fail(.mediaServicesReset)
        XCTAssertTrue(host.retryPending)
        host.stopCamera()
        time.advance(by: 60)
        XCTAssertEqual(stub.state, .idle, "the user's Stop camera wins over the automatic retry")
        host.retryCamera()
        XCTAssertEqual(stub.state, .idle)
    }
}
