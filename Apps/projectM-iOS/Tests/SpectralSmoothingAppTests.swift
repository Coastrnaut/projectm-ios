// SpectralSmoothingAppTests.swift — ANL-003-T05: the Attack and Release settings (ANL-003-R6):
// Instant defaults (today's look), the offered choices, persistence, safe readings of bad stored
// values, the mapping to the smoother's seconds, and the host's smoothing property. Each test makes
// its own defaults suite (nothing is mutated in setUp or tearDown).
import AnalysisFeatures
import Metal
import XCTest
@testable import projectM_iOS

@MainActor
final class SpectralSmoothingAppTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "SpectralSmoothingAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    func testSmoothingDefaultsToInstantAndPersists() {
        withDefaults { (defaults: UserDefaults) in
            let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
            XCTAssertEqual(settings.spectrumAttackMilliseconds, 0, "Instant by default")
            XCTAssertEqual(settings.spectrumReleaseMilliseconds, 0, "Instant by default")
            XCTAssertEqual(settings.spectrumSmoothing, SmoothingTimes.instant, "today's look")
            XCTAssertEqual(AppSettings.spectrumAttackChoices, [0, 25, 50, 100])
            XCTAssertEqual(AppSettings.spectrumReleaseChoices, [0, 100, 250, 500])
            XCTAssertEqual(AppSettings.smoothingTitle(milliseconds: 0), "Instant")
            XCTAssertEqual(AppSettings.smoothingTitle(milliseconds: 250), "250 ms")
            settings.spectrumAttackMilliseconds = 50
            settings.spectrumReleaseMilliseconds = 500
            XCTAssertEqual(defaults.integer(forKey: "settings.spectrum.attack"), 50)
            XCTAssertEqual(defaults.integer(forKey: "settings.spectrum.release"), 500)
            XCTAssertEqual(settings.spectrumSmoothing, SmoothingTimes(attackSeconds: 0.05, releaseSeconds: 0.5))
            let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
            XCTAssertEqual(reloaded.spectrumAttackMilliseconds, 50)
            XCTAssertEqual(reloaded.spectrumReleaseMilliseconds, 500)
            XCTAssertTrue(AppSettings.allKeys.contains(AppSettings.spectrumAttackKey))
            XCTAssertTrue(AppSettings.allKeys.contains(AppSettings.spectrumReleaseKey))
        }
    }

    func testUnofferedValuesReadAsInstant() {
        withDefaults { (defaults: UserDefaults) in
            let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
            settings.spectrumAttackMilliseconds = 30
            settings.spectrumReleaseMilliseconds = 2_000
            XCTAssertEqual(settings.spectrumAttackMilliseconds, 0, "not a choice → Instant")
            XCTAssertEqual(settings.spectrumReleaseMilliseconds, 0, "not a choice → Instant")
            defaults.set(-5, forKey: AppSettings.spectrumAttackKey)
            defaults.set("slow", forKey: AppSettings.spectrumReleaseKey)
            let bad = AppSettings(defaults: defaults, systemReduceMotion: false)
            XCTAssertEqual(bad.spectrumSmoothing, SmoothingTimes.instant)
        }
    }

    func testHostTakesTheSmoothingTimes() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .circular, barCount: .b32)
        defer { host.pause() }
        XCTAssertEqual(host.smoothing, SmoothingTimes.instant, "a new host draws raw bands")
        host.smoothing = SmoothingTimes(attackSeconds: 0.025, releaseSeconds: 0.25)
        XCTAssertEqual(host.smoothing, SmoothingTimes(attackSeconds: 0.025, releaseSeconds: 0.25))
    }
}
