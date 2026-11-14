// RecordingQualitySetting.swift — REC-005: the selected record quality profile (REC-005-R7, R9, R12;
// specs/150-rec-005-quality-profiles, research REC-005-D3, D6).
//
// One device-local String, key `settings.recording.qualityProfile` (`draft`, `standard`, `high`, `max`),
// default Standard (absent or unknown → Standard; nothing stored until changed). It depends on the device's
// encoder, so it is left out of the library backup, erased with the Settings category and removed by
// `-uitestResetNotice`. The rows' availability comes from the capability source and the rows' size (the
// shown visual's drawable, else the screen's native pixels); Record re-checks with the real drawable.
import CoreGraphics
import Foundation
import FrameRecording
import Observation
import Rendering
import UIKit

/// The encoder's answers with the display's current frame rate (REC-005-D3) and, REC-006-D4, the render loop's
/// cap (QualityGovernor: 30 fps in Low Power Mode or at serious/critical thermal state).
struct DisplayBoundCapabilities: RecordingEncoderCapabilities {
    let encoder: any RecordingEncoderCapabilities
    let maxFramesPerSecond: Int
    var renderLimit: RecordingRenderLimit? = nil

    func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool {
        encoder.canEncode(codec, width: width, height: height)
    }

    func maxEncodedFramesPerSecond(_ codec: RecordingCodec, width: Int, height: Int) -> Int {
        encoder.maxEncodedFramesPerSecond(codec, width: width, height: height)
    }
}

@MainActor
@Observable
final class RecordingQualitySetting {
    static let profileKey = "settings.recording.qualityProfile"
    static let sectionTitle = "Recording quality"
    static let footer = "Recordings never upscale: a profile records at most the size of the picture shown. "
        + "Unavailable profiles show why. A change applies to the next recording."

    @ObservationIgnored private let defaults: UserDefaults
    /// The capability source for a query now (the display's frame rate can change with the window's screen).
    @ObservationIgnored let capabilitiesProvider: @MainActor () -> any RecordingEncoderCapabilities
    /// The size the rows describe, in pixels (REC-005-R12).
    @ObservationIgnored let rowSize: @MainActor () -> CGSize

    var profile: RecordingQualityProfile {
        didSet { defaults.set(profile.rawValue, forKey: Self.profileKey) }
    }

    /// REC-006-R8: the frame-rate choice, key `settings.recording.frameRate` (`profile`, `24`, `30`, `60`); absent or
    /// unknown → Profile default; nothing stored until changed. Device-local like the profile.
    static let frameRateKey = "settings.recording.frameRate"
    static let frameRateSectionTitle = "Recording frame rate"
    static let frameRateFooter = "Recordings are written at exactly this rate; each frame is the shown frame nearest its time. "
        + "Unavailable rates show why. A change applies to the next recording."

    var frameRate: RecordingFrameRateChoice {
        didSet { defaults.set(frameRate.rawValue, forKey: Self.frameRateKey) }
    }

    init(defaults: UserDefaults, capabilities: @escaping @MainActor () -> any RecordingEncoderCapabilities,
         rowSize: @escaping @MainActor () -> CGSize) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.profileKey)   // the UI-test reset: Standard (REC-005-R7)
            defaults.removeObject(forKey: Self.frameRateKey)   // and Profile default (REC-006-R8)
        }
        self.defaults = defaults
        capabilitiesProvider = capabilities
        self.rowSize = rowSize
        profile = Self.stored(in: defaults)
        frameRate = Self.storedFrameRate(in: defaults)
    }

    /// The stored frame-rate choice, Profile default when absent or unknown.
    static func storedFrameRate(in defaults: UserDefaults) -> RecordingFrameRateChoice {
        (defaults.string(forKey: frameRateKey)).flatMap(RecordingFrameRateChoice.init(rawValue:)) ?? .defaultChoice
    }

    /// The explicit rate the profile rows describe: the choice, lowered as Record would lower it (display, render
    /// cap); nil for Profile default (REC-006-R9).
    private func effectiveExplicitRate(_ capabilities: any RecordingEncoderCapabilities) -> Int? {
        guard let rate = frameRate.rate else { return nil }
        let supported: [Int] = RecordingFrameRateChoice.supportedRates.filter { (r: Int) -> Bool in
            r <= rate && RecordingFrameRateCatalog.availability(rate: r, capabilities: capabilities).isAvailable
        }
        return supported.last ?? RecordingFrameRateChoice.supportedRates[0]
    }

    /// The row of a frame-rate choice for the selected profile and the current size (REC-006-R6).
    func availability(_ choice: RecordingFrameRateChoice) -> RecordingFrameRateAvailability {
        let size: CGSize = rowSize()
        return RecordingFrameRateCatalog.availability(of: choice, profile: profile, drawableWidth: Int(size.width),
                                                      drawableHeight: Int(size.height), capabilities: capabilitiesProvider())
    }

    /// Picks `choice` when it is available here (a disabled row cannot be picked, REC-006-R6).
    @discardableResult
    func select(_ choice: RecordingFrameRateChoice) -> Bool {
        guard availability(choice).isAvailable else { return false }
        frameRate = choice
        return true
    }

    /// "Profile default (30 fps)", "24 fps".
    func title(_ choice: RecordingFrameRateChoice) -> String {
        choice.title(profileRate: profile.frameRate)
    }

    /// "24 fps" or "60 fps, unavailable: Low Power Mode limits the visual to 30 fps." (VoiceOver label).
    func rowLabel(_ choice: RecordingFrameRateChoice) -> String {
        switch availability(choice) {
        case .available: title(choice)
        case .unavailable(let reason): title(choice) + ", unavailable: " + reason.text
        }
    }

    /// The stored profile, Standard when absent or unknown.
    static func stored(in defaults: UserDefaults) -> RecordingQualityProfile {
        (defaults.string(forKey: profileKey)).flatMap(RecordingQualityProfile.init(rawValue:)) ?? .defaultProfile
    }

    /// The row of `profile` for the current size.
    func availability(_ profile: RecordingQualityProfile) -> RecordingProfileAvailability {
        let size: CGSize = rowSize()
        let capabilities: any RecordingEncoderCapabilities = capabilitiesProvider()
        return RecordingQualityCatalog.availability(of: profile, frameRate: effectiveExplicitRate(capabilities),   // REC-006-R9
                                                    drawableWidth: Int(size.width), drawableHeight: Int(size.height),
                                                    capabilities: capabilities)
    }

    /// Picks `profile` when it is available here (a disabled row cannot be picked, REC-005-R5).
    @discardableResult
    func select(_ profile: RecordingQualityProfile) -> Bool {
        guard availability(profile).plan != nil else { return false }
        self.profile = profile
        return true
    }

    /// "High, 1178×2560 · HEVC · 20 Mb/s · 60 fps" or "Max, unavailable: Needs HEVC, …" (VoiceOver label).
    func rowLabel(_ profile: RecordingQualityProfile) -> String {
        switch availability(profile) {
        case .available(let plan): profile.title + ", " + plan.summary
        case .unavailable(let reason): profile.title + ", unavailable: " + reason.text
        }
    }

    // MARK: - The device (REC-005-D3)

    /// One VideoToolbox source for the app (its answers are cached).
    static let encoder = VideoToolboxEncoderCapabilities()

    /// The first window scene's screen (nil before a scene connects).
    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }.first?.screen
    }

    /// The encoder with the screen's highest frame rate (60 before a scene connects) and the render cap.
    static func deviceCapabilities() -> any RecordingEncoderCapabilities {
        let info = ProcessInfo.processInfo
        return DisplayBoundCapabilities(encoder: encoder, maxFramesPerSecond: screen?.maximumFramesPerSecond ?? 60,
                                        renderLimit: renderLimit(thermal: ThermalLevel(info.thermalState), lowPower: info.isLowPowerModeEnabled))
    }

    /// REC-006-D4: the render loop's cap from QualityGovernor's rules (nil when it runs at full rate).
    static func renderLimit(thermal: ThermalLevel, lowPower: Bool) -> RecordingRenderLimit? {
        let cap: Int = QualityGovernor.settings(thermal: thermal, lowPower: lowPower).maxFramesPerSecond
        guard cap < QualitySettings.full.maxFramesPerSecond else { return nil }
        return RecordingRenderLimit(reason: lowPower ? .lowPowerMode : .thermal, maximumFramesPerSecond: cap)
    }

    /// The screen's native size in pixels, portrait (zero before a scene connects).
    static func screenPixelSize() -> CGSize {
        screen?.nativeBounds.size ?? .zero
    }

    /// The documented table, one line per profile (the section footer, REC-005-R1).
    static var tableText: String {
        RecordingQualityProfile.allCases.map { (p: RecordingQualityProfile) -> String in
            p.title + ": " + p.documentation
        }.joined(separator: "\n")
    }
}
