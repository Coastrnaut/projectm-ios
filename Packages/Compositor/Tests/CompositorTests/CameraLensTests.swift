// CAM-003-T05: lens inventory, the input switch routine and lens switching on a running stand-in
// camera (CAM-003-R1, R5 to R10; S2, S3). The inventory and switch tests are plain Swift (every
// platform, including the Linux shape); the stand-in provider tests need a Metal device.
import CameraLayer
import XCTest
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
#endif

final class CameraLensTests: XCTestCase {
    // MARK: Inventory (R1, R2, R5)

    func testInventoryListsDistinctLensesWidestFirstAndOffersOnlyTwoOrMore() {
        let all = FixedCameraLensInventory([.telephoto, .wide, .ultraWide, .wide])
        XCTAssertEqual(all.backLenses, [.ultraWide, .wide, .telephoto])
        XCTAssertEqual(FixedCameraLensInventory(list: "wide, ultraWide,fisheye").backLenses, [.ultraWide, .wide], "unknown ignored")
        XCTAssertEqual(FixedCameraLensInventory([.wide]).offeredLenses(for: .back), [], "one lens: no row")
        XCTAssertEqual(FixedCameraLensInventory([.wide, .ultraWide]).offeredLenses(for: .back), [.ultraWide, .wide])
        XCTAssertEqual(all.offeredLenses(for: .back), [.ultraWide, .wide, .telephoto])
        XCTAssertEqual(all.offeredLenses(for: .front), [], "front: no row")
        XCTAssertEqual(FixedCameraLensInventory([]).offeredLenses(for: .back), [])
        XCTAssertEqual(CameraLens.allCases.map(\.title), ["Ultra Wide", "Wide", "Telephoto"])
    }

    func testStoredLensMissingOnDeviceResolvesToWide() {   // S3
        let two = FixedCameraLensInventory([.wide, .ultraWide])
        XCTAssertEqual(two.resolve(.telephoto), .wide)
        XCTAssertEqual(two.resolve(.ultraWide), .ultraWide)
        XCTAssertEqual(FixedCameraLensInventory([]).resolve(.ultraWide), .wide)
        XCTAssertEqual(CameraLens(stored: nil), .wide)
        XCTAssertEqual(CameraLens(stored: "zoom"), .wide)
        XCTAssertEqual(CameraLens(stored: "telephoto"), .telephoto)
    }

    // MARK: Switch routine (contract C2; R6, R7)

    private func running(_ lens: CameraLens, failing: Set<CameraLens> = []) -> FakeCameraCaptureSession {
        let session = FakeCameraCaptureSession(failingLenses: failing)
        let outcome = CameraInputSwitch.replace(in: session, makeInput: { session.makeInput(lens: lens) },
                                                makeFallback: { session.makeInput(lens: .wide) })
        XCTAssertEqual(outcome, .switched)
        session.startRunning()
        return session
    }

    private func switchTo(_ lens: CameraLens, _ session: FakeCameraCaptureSession) -> CameraInputSwitchOutcome {
        CameraInputSwitch.replace(in: session, makeInput: { session.makeInput(lens: lens) },
                                  makeFallback: { session.makeInput(lens: .wide) })
    }

    func testSwitchOutcomes() {
        let session = running(.wide, failing: [.telephoto])
        XCTAssertEqual(switchTo(.ultraWide, session), .switched)
        XCTAssertEqual(session.configuredInputs.map(\.lens), [.ultraWide])

        let configurations = session.configurations
        XCTAssertEqual(switchTo(.telephoto, session), .keptPrevious, "creation fails")
        XCTAssertEqual(session.configurations, configurations, "creation failure touches nothing")
        XCTAssertEqual(session.configuredInputs.map(\.lens), [.ultraWide])

        session.refusedLenses = [.wide]
        session.failingLenses = []
        XCTAssertEqual(switchTo(.wide, session), .keptPrevious, "session refuses the new input")
        XCTAssertEqual(session.configuredInputs.map(\.lens), [.ultraWide])

        session.refusedLenses = [.telephoto, .ultraWide]   // the previous one can no longer be re-added either
        XCTAssertEqual(switchTo(.telephoto, session), .fellBackToWide)
        XCTAssertEqual(session.configuredInputs.map(\.lens), [.wide])

        session.refusedLenses = [.wide, .ultraWide, .telephoto]
        XCTAssertEqual(switchTo(.ultraWide, session), .noInput, "nothing addable")
        XCTAssertTrue(session.configuredInputs.isEmpty)
        XCTAssertEqual(session.changesOutsideConfiguration, 0, "every change inside begin/commit")
    }

    #if canImport(Metal) && !COMPOSITOR_NO_METAL
    // MARK: Stand-in provider (R6 to R10; S2)

    private func stub(_ lenses: [CameraLens], failing: Set<CameraLens> = [], scenario: CameraScenario = .granted,
                      lens: CameraLens = .wide) throws -> StubCameraFrameProvider {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        return StubCameraFrameProvider(device: device, scenario: scenario, lensInventory: FixedCameraLensInventory(lenses),
                                       failingLenses: failing, lens: lens)
    }

    /// The acceptance: 30 switches on a running session, a third of them to a failing lens.
    func testRepeatedSwitchingDuringARunningSessionNeverLosesTheInput() throws {
        let camera = try stub([.wide, .ultraWide, .telephoto], failing: [.telephoto])
        camera.start()
        XCTAssertEqual(camera.state, .running)
        let order: [CameraLens] = [.ultraWide, .telephoto, .wide]
        var lastSequence: UInt64 = camera.latestFrame()?.sequence ?? 0
        for step in 0..<30 {
            let before: CameraLens = camera.lens
            let wanted: CameraLens = order[step % 3]
            camera.selectLens(wanted)
            XCTAssertEqual(camera.state, .running, "step \(step)")
            XCTAssertTrue(camera.session.isRunning, "step \(step)")
            XCTAssertEqual(camera.session.configuredInputs.count, 1, "exactly one input, step \(step)")
            XCTAssertEqual(camera.session.configuredInputs.first?.lens, camera.lens, "lens names the input, step \(step)")
            if wanted == .telephoto {
                XCTAssertEqual(camera.lens, before, "failing lens: the previous one keeps running")
                XCTAssertEqual(camera.lastLensOutcome, .keptPrevious)
            } else {
                XCTAssertEqual(camera.lens, wanted)
                let sequence: UInt64 = try XCTUnwrap(camera.latestFrame()?.sequence, "a picture after the switch")
                XCTAssertGreaterThan(sequence, lastSequence, "a new picture, not the previous lens's (R8)")
                lastSequence = sequence
            }
        }
        XCTAssertEqual(camera.session.changesOutsideConfiguration, 0)
        XCTAssertEqual(camera.startCount, 1, "never restarted")
    }

    func testLensIsRecordedWhileIdleOrDeniedAndIgnoredByTheFrontCamera() throws {
        let idle = try stub([.wide, .ultraWide])
        idle.selectLens(.ultraWide)
        XCTAssertEqual(idle.lens, .ultraWide)
        XCTAssertEqual(idle.state, .idle, "never starts the camera")
        XCTAssertTrue(idle.session.configuredInputs.isEmpty)
        idle.selectLens(.telephoto)
        XCTAssertEqual(idle.lens, .wide, "unlisted → wide")
        idle.selectLens(.ultraWide)
        idle.start()
        XCTAssertEqual(idle.session.configuredInputs.first?.lens, .ultraWide, "starts on the recorded lens")

        let denied = try stub([.wide, .ultraWide], scenario: .denied)
        denied.start()
        denied.selectLens(.ultraWide)
        XCTAssertEqual(denied.state, .denied)
        XCTAssertEqual(denied.accessRequests, 0)

        let front = try stub([.wide, .ultraWide])
        front.select(.front)
        front.start()
        front.selectLens(.ultraWide)
        XCTAssertEqual(front.session.configuredInputs.first?.position, .front)
        XCTAssertEqual(front.session.configuredInputs.first?.lens, .wide, "front keeps its wide lens (R9)")
        front.select(.back)
        XCTAssertEqual(front.session.configuredInputs.first?.lens, .ultraWide, "back restores the chosen lens")
        XCTAssertEqual(front.state, .running)
    }

    func testStartOnAFailingLensFallsBackToWide() throws {
        let camera = try stub([.wide, .ultraWide], failing: [.ultraWide], lens: .ultraWide)
        camera.start()
        XCTAssertEqual(camera.state, .running)
        XCTAssertEqual(camera.lens, .wide)
        XCTAssertEqual(camera.session.configuredInputs.map(\.lens), [.wide])
        camera.stop()
        XCTAssertTrue(camera.session.configuredInputs.isEmpty, "a stopped session holds no input")
        XCTAssertFalse(camera.session.isRunning)
    }
    #endif
}
