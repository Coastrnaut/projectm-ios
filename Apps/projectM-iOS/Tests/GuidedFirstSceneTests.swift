// GuidedFirstSceneTests.swift — UIX-001-T03, T06: the guided first scene's flow (steps, Back keeps the
// draft), stored state (pending, finished, skipped, unknown), launch rule (recovery offer, harness
// suppression, `-uitestGuidedFirstScene`), re-open, and what Play applies (and does not). In-memory
// UserDefaults suites; no UI, no files, no network. Budget: about 1 s for the file (owner rule 7).
import XCTest
@testable import projectM_iOS

final class GuidedFirstSceneFlowTests: XCTestCase {
    func testStepsRunInOrderAndStopAtTheEnds() {
        var flow = GuidedFirstSceneFlow()
        XCTAssertEqual(flow.step, .welcome)
        XCTAssertFalse(flow.canGoBack)
        flow.back()
        XCTAssertEqual(flow.step, .welcome, "Back stops at the first step")
        var seen: [GuidedFirstSceneStep] = [flow.step]
        for _ in 0..<6 {
            flow.next()
            if seen.last != flow.step { seen.append(flow.step) }
        }
        XCTAssertEqual(seen, [.welcome, .sound, .visual, .look, .play])
        XCTAssertTrue(flow.isLast)
        XCTAssertEqual(flow.position, 5)
        XCTAssertEqual(GuidedFirstSceneFlow.stepCount, 5)
    }

    func testBackKeepsTheDraft() {
        var flow = GuidedFirstSceneFlow()
        flow.next(); flow.next()
        flow.draft.visual = .text
        flow.next()
        flow.draft.message = "Hi"
        flow.back(); flow.back()
        XCTAssertEqual(flow.step, .sound)
        XCTAssertEqual(flow.draft.visual, .text)
        XCTAssertEqual(flow.draft.message, "Hi")
    }

    func testOnlyPermissionFreeVisualsAreOffered() {
        let offered = GuidedVisual.allCases.map(\.choice)
        XCTAssertEqual(offered, [.circularSpectrum, .linearSpectrum, .text])
        XCTAssertFalse(offered.contains { (choice: VisualChoice) -> Bool in choice.usesCamera || choice.usesPhoto || choice.usesVideo })
        let draft = GuidedFirstSceneDraft()
        XCTAssertEqual(draft.visual, .circularSpectrum)
        XCTAssertTrue(draft.glow)
        XCTAssertEqual(draft.message, "Hello")
    }

    func testLaunchRule() {
        XCTAssertTrue(GuidedFirstScenePolicy.offersAtLaunch(state: .pending, recoveryPending: false, suppressed: false))
        XCTAssertFalse(GuidedFirstScenePolicy.offersAtLaunch(state: nil, recoveryPending: false, suppressed: false), "never offered")
        XCTAssertFalse(GuidedFirstScenePolicy.offersAtLaunch(state: .finished, recoveryPending: false, suppressed: false))
        XCTAssertFalse(GuidedFirstScenePolicy.offersAtLaunch(state: .skipped, recoveryPending: false, suppressed: false))
        XCTAssertFalse(GuidedFirstScenePolicy.offersAtLaunch(state: .pending, recoveryPending: true, suppressed: false), "PERF-010 first")
        XCTAssertFalse(GuidedFirstScenePolicy.offersAtLaunch(state: .pending, recoveryPending: false, suppressed: true))
    }

    func testHarnessSuppression() {
        let isSuppressed = GuidedFirstScenePolicy.isSuppressed
        XCTAssertTrue(isSuppressed(["app", "-uitestResetNotice"], [:], true))
        XCTAssertTrue(isSuppressed(["app", "-autostart", "inAppPlayback"], [:], true))
        XCTAssertTrue(isSuppressed(["app"], ["XCTestConfigurationFilePath": "x"], true))
        XCTAssertTrue(isSuppressed(["app"], ["PROJECTM_AUTORUN": "sc101"], true))
        XCTAssertFalse(isSuppressed(["app", "-uitestResetNotice", "-uitestGuidedFirstScene"], ["XCTestConfigurationFilePath": "x"], true))
        XCTAssertFalse(isSuppressed(["app"], [:], true), "a normal launch")
        XCTAssertFalse(isSuppressed(["app", "-uitestResetNotice"], ["XCTestConfigurationFilePath": "x"], false), "Release")
    }
}

@MainActor
final class GuidedFirstSceneCoordinatorTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, () -> Void) {
        let suite = "GuidedFirstSceneTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    func testNoticeOffersItAndPendingSurvivesARelaunch() throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let guide = GuidedFirstSceneCoordinator(defaults: defaults, suppressed: false)
        XCTAssertNil(guide.state)
        guide.noticeAcknowledged(recoveryPending: false)
        XCTAssertEqual(guide.state, .pending)
        XCTAssertTrue(guide.isPresented)
        // Killed mid-tutorial: the next launch offers it again from step 1.
        let relaunched = GuidedFirstSceneCoordinator(defaults: defaults, suppressed: false)
        relaunched.presentAtLaunchIfDue(recoveryPending: false)
        XCTAssertTrue(relaunched.isPresented)
        XCTAssertEqual(relaunched.flow.step, .welcome)
    }

    func testOlderInstallIsNeverOfferedAtLaunch() throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let guide = GuidedFirstSceneCoordinator(defaults: defaults, suppressed: false)
        guide.presentAtLaunchIfDue(recoveryPending: false)
        XCTAssertFalse(guide.isPresented)
        XCTAssertNil(guide.state, "nothing is written")
    }

    func testSkipAndFinishAreFinal() throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let guide = GuidedFirstSceneCoordinator(defaults: defaults, suppressed: false)
        guide.noticeAcknowledged(recoveryPending: false)
        guide.flow.next()
        guide.skip()
        XCTAssertFalse(guide.isPresented)
        XCTAssertEqual(guide.state, .skipped)
        guide.noticeAcknowledged(recoveryPending: false)
        XCTAssertFalse(guide.isPresented, "a skipped guide is not offered again")
        XCTAssertEqual(guide.state, .skipped)

        guide.open()   // the Settings row
        XCTAssertTrue(guide.isPresented)
        guide.flow.draft.visual = .linearSpectrum
        let draft = guide.finish()
        XCTAssertEqual(draft.visual, .linearSpectrum)
        XCTAssertEqual(guide.state, .finished)
        let relaunched = GuidedFirstSceneCoordinator(defaults: defaults, suppressed: false)
        relaunched.presentAtLaunchIfDue(recoveryPending: false)
        XCTAssertFalse(relaunched.isPresented)
    }

    func testReopenStartsFreshAndSuppressionOrRecoveryBlocksTheLaunchOffer() throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let suppressed = GuidedFirstSceneCoordinator(defaults: defaults, suppressed: true)
        suppressed.noticeAcknowledged(recoveryPending: false)
        XCTAssertFalse(suppressed.isPresented, "harness launch")
        XCTAssertEqual(suppressed.state, .pending)
        let afterCrash = GuidedFirstSceneCoordinator(defaults: defaults, suppressed: false)
        afterCrash.presentAtLaunchIfDue(recoveryPending: true)
        XCTAssertFalse(afterCrash.isPresented, "the recovery offer is not covered")
        suppressed.open()
        suppressed.flow.next()
        suppressed.flow.draft.glow = false
        suppressed.open()
        XCTAssertEqual(suppressed.flow, GuidedFirstSceneFlow(), "re-open starts at step 1 with the defaults")
    }

    func testUnknownStoredValueReadsAsNeverOffered() throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        defaults.set("later", forKey: GuidedFirstScenePolicy.key)
        let guide = GuidedFirstSceneCoordinator(defaults: defaults, suppressed: false)
        XCTAssertNil(guide.state)
        guide.presentAtLaunchIfDue(recoveryPending: false)
        XCTAssertFalse(guide.isPresented)
        GuidedFirstSceneCoordinator.reset(defaults)
        XCTAssertNil(defaults.object(forKey: GuidedFirstScenePolicy.key))
    }

    func testPlayAppliesOnlyTheVisualAndItsLook() throws {
        let (defaults, cleanUp) = try makeDefaults()
        defer { cleanUp() }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let texts = TextOverlayCoordinator.makeDefault(defaults: defaults)
        let before = (osc: settings.oscEnabled, port: settings.oscPort, bars: settings.circularSpectrumBars,
                      overlay: settings.showsPerformanceOverlay, message: texts.spec.message)

        AppCoordinator.apply(GuidedFirstSceneDraft(visual: .circularSpectrum, glow: true, message: "ignored"),
                             settings: settings, texts: texts)
        XCTAssertEqual(settings.visual, .circularSpectrum)
        XCTAssertTrue(settings.glowEnabled)
        XCTAssertEqual(texts.spec.message, before.message, "a spectrum leaves the Text message alone")

        AppCoordinator.apply(GuidedFirstSceneDraft(visual: .linearSpectrum, glow: false, message: "ignored"),
                             settings: settings, texts: texts)
        XCTAssertEqual(settings.visual, .linearSpectrum)
        XCTAssertFalse(settings.glowEnabled)

        AppCoordinator.apply(GuidedFirstSceneDraft(visual: .text, glow: true, message: "Hi\u{0007} there"),
                             settings: settings, texts: texts)
        XCTAssertEqual(settings.visual, .text)
        XCTAssertFalse(settings.glowEnabled, "Text leaves the glow alone")
        XCTAssertEqual(texts.spec.message, "Hi there", "through MED-009's sanitizer")

        XCTAssertEqual(settings.oscEnabled, before.osc, "OSC untouched")
        XCTAssertEqual(settings.oscPort, before.port)
        XCTAssertEqual(settings.circularSpectrumBars, before.bars)
        XCTAssertEqual(settings.showsPerformanceOverlay, before.overlay)
        XCTAssertFalse(settings.visual.usesCamera)
    }
}
