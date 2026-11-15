// ParticleTrailAppTests.swift — VIS-010-T13: the Trails setting in the app (VIS-010-R9, R11): default Off, persistence
// and safe reading; every key list; the host hands the length to the fountain and the orbit (in place, and to a
// generator a style change builds) and names it in the visual's accessibility value. The host test needs a Metal
// device (the simulator renders with the host GPU); it skips without one.
import LibraryBackup
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class ParticleTrailAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "ParticleTrailAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSettingDefaultsPersistsAndReadsSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.particleTrails, .off, "Off by default (existing pictures unchanged)")
        XCTAssertEqual(ParticleTrailSetting.allCases.map(\.title), ["Off", "Short", "Long"])
        XCTAssertEqual(ParticleTrailSetting.allCases.map(\.length), [.off, .short, .long])
        settings.particleTrails = .long
        XCTAssertEqual(defaults.string(forKey: "settings.particleTrails"), "long")
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).particleTrails, .long)
        defaults.set("endless", forKey: AppSettings.particleTrailsKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).particleTrails, .off, "unknown → Off")
        defaults.set(2, forKey: AppSettings.particleTrailsKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).particleTrails, .off, "not a string → Off")
    }

    /// FR-065 setting (reset by `-uitestResetNotice` through `allKeys`) and in the FILE-005 backup policy.
    func testKeyIsInEveryList() {
        XCTAssertTrue(AppSettings.allKeys.contains("settings.particleTrails"))
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains("settings.particleTrails"))
    }

    func testHostAppliesTrailsToFountainAndOrbit() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .particleFountain(gravity: .medium), barCount: .b32)
        let fountain = try XCTUnwrap(host.particleFountainGenerator)
        XCTAssertEqual(fountain.trails, .off)
        XCTAssertEqual(host.view.accessibilityValue, "Medium gravity, Glow off", "Off: the value is unchanged")
        host.particleTrails = .long
        XCTAssertEqual(fountain.trails, .long, "in place, from the next frame")
        XCTAssertEqual(host.view.accessibilityValue, "Medium gravity, Glow off, Trails Long")
        try host.apply(style: .particleFountain(gravity: .low))
        XCTAssertTrue(host.particleFountainGenerator === fountain)
        XCTAssertEqual(fountain.trails, .long, "a gravity change keeps the trails")
        try host.apply(style: .particleOrbit(radius: .medium))
        let orbit = try XCTUnwrap(host.particleOrbitGenerator)
        XCTAssertEqual(orbit.trails, .long, "a generator a style change builds gets the trails")
        XCTAssertEqual(host.view.accessibilityValue, "Medium radius, Glow off, Trails Long")
        host.particleTrails = .short
        XCTAssertEqual(orbit.trails, .short)
        host.particleTrails = .off
        XCTAssertEqual(orbit.trails, .off)
        XCTAssertEqual(host.view.accessibilityValue, "Medium radius, Glow off")
        host.pause()
    }
}
