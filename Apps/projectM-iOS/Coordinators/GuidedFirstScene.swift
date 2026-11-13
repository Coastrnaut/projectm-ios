// GuidedFirstScene.swift — UIX-001 guided first scene: the tutorial's pure flow, its stored state, the
// launch rule and its coordinator (UIX-001-R1 to R8, R13; data-model; contract G3).
//
// * Five steps: welcome → sound → visual → look → play. Skip on every step, Back from step 2.
// * The draft offers only permission-free visuals with a scene-recorded look: Circular Spectrum
//   (default, glow on), Linear Spectrum, Text ("Hello"). Never Camera, Photo, Video or projectM.
// * Stored state, key `guide.firstScene`: `pending` (written when the notice is acknowledged and the
//   key is absent), `finished` (Play), `skipped` (Skip); absent = never offered, so installs older
//   than this feature are never offered it by themselves (research UIX-001-D2).
// * Launch rule: offered when pending, unless the PERF-010 recovery offer is pending or the DEBUG
//   harness suppresses it (UI tests, unit-test host, automation) without `-uitestGuidedFirstScene`.
// * The Settings row (`open()`) is never gated. Nothing here starts a source or touches a setting;
//   AppCoordinator+Guide.swift applies a finished scene.
import Foundation
import Observation

/// The tutorial's steps, in order (UIX-001-R2).
enum GuidedFirstSceneStep: Int, CaseIterable, Sendable {
    case welcome, sound, visual, look, play

    /// The value of the `guide.step` accessibility marker.
    var name: String {
        switch self {
        case .welcome: "welcome"
        case .sound: "sound"
        case .visual: "visual"
        case .look: "look"
        case .play: "play"
        }
    }
}

/// The visuals the tutorial offers (UIX-001-R3): permission-free, no file, a scene-recorded look.
enum GuidedVisual: String, CaseIterable, Sendable {
    case circularSpectrum, linearSpectrum, text

    var choice: VisualChoice {
        switch self {
        case .circularSpectrum: .circularSpectrum
        case .linearSpectrum: .linearSpectrum
        case .text: .text
        }
    }

    var title: String { choice.title }

    var detail: String {
        switch self {
        case .circularSpectrum: "Bars in a ring that move with the sound."
        case .linearSpectrum: "A row of bars, low notes on the left."
        case .text: "Your own words over a ring of bars."
        }
    }

    /// The spectra have a glow; Text has a message.
    var usesGlow: Bool { self != .text }
}

/// The choices made in the tutorial (in memory only).
struct GuidedFirstSceneDraft: Equatable, Sendable {
    static let defaultMessage = "Hello"

    var visual: GuidedVisual = .circularSpectrum
    var glow = true
    var message = GuidedFirstSceneDraft.defaultMessage
}

/// The tutorial's position and draft (UIX-001-R2, R4).
struct GuidedFirstSceneFlow: Equatable, Sendable {
    private(set) var step: GuidedFirstSceneStep = .welcome
    var draft = GuidedFirstSceneDraft()

    var canGoBack: Bool { step != .welcome }
    var isLast: Bool { step == .play }
    /// 1-based position for "Step 2 of 5".
    var position: Int { step.rawValue + 1 }
    static let stepCount = GuidedFirstSceneStep.allCases.count

    mutating func next() {
        if let following = GuidedFirstSceneStep(rawValue: step.rawValue + 1) { step = following }
    }

    /// Back keeps the draft.
    mutating func back() {
        if let previous = GuidedFirstSceneStep(rawValue: step.rawValue - 1) { step = previous }
    }
}

/// The stored tutorial state (UIX-001-R7). Absent (nil) = never offered.
enum GuidedFirstSceneState: String, Sendable {
    case pending, finished, skipped
}

/// The launch rule and the harness rule (UIX-001-R1, R13; research UIX-001-D3, D5).
enum GuidedFirstScenePolicy {
    static let key = "guide.firstScene"
    /// Lets a DEBUG harness launch offer the tutorial by the normal rule.
    static let testArgument = "-uitestGuidedFirstScene"

    static func offersAtLaunch(state: GuidedFirstSceneState?, recoveryPending: Bool, suppressed: Bool) -> Bool {
        state == .pending && !recoveryPending && !suppressed
    }

    /// `harness` is false in Release builds without automation.
    static func isSuppressed(arguments: [String], environment: [String: String], harness: Bool) -> Bool {
        guard harness, !arguments.contains(testArgument) else { return false }
        if environment["XCTestConfigurationFilePath"] != nil || environment["PROJECTM_AUTORUN"] != nil { return true }
        return arguments.contains { (argument: String) -> Bool in argument.hasPrefix("-uitest") || argument == "-autostart" }
    }

    static func harnessSuppresses(processInfo: ProcessInfo = .processInfo) -> Bool {
        #if DEBUG || PROJECTM_AUTOMATION
        let harness = true
        #else
        let harness = false
        #endif
        return isSuppressed(arguments: processInfo.arguments, environment: processInfo.environment, harness: harness)
    }
}

/// Owns the stored state and whether the tutorial is shown (contract G3).
@MainActor
@Observable
final class GuidedFirstSceneCoordinator {
    private(set) var isPresented = false
    var flow = GuidedFirstSceneFlow()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let suppressed: Bool

    init(defaults: UserDefaults, suppressed: Bool) {
        self.defaults = defaults
        self.suppressed = suppressed
    }

    var state: GuidedFirstSceneState? {
        defaults.string(forKey: GuidedFirstScenePolicy.key).flatMap(GuidedFirstSceneState.init(rawValue:))
    }

    /// `-uitestResetNotice`: never offered.
    static func reset(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: GuidedFirstScenePolicy.key)
    }

    /// The notice was acknowledged: a new install is offered the tutorial now and until it ends.
    func noticeAcknowledged(recoveryPending: Bool) {
        if state == nil { defaults.set(GuidedFirstSceneState.pending.rawValue, forKey: GuidedFirstScenePolicy.key) }
        presentAtLaunchIfDue(recoveryPending: recoveryPending)
    }

    /// At launch (the notice already acknowledged): shown again while pending.
    func presentAtLaunchIfDue(recoveryPending: Bool) {
        guard GuidedFirstScenePolicy.offersAtLaunch(state: state, recoveryPending: recoveryPending, suppressed: suppressed) else { return }
        open()
    }

    /// From step 1 with the default choices (also the Settings row; never gated).
    func open() {
        flow = GuidedFirstSceneFlow()
        isPresented = true
    }

    /// Skip: closes and records it; nothing else changes (UIX-001-R6).
    func skip() {
        defaults.set(GuidedFirstSceneState.skipped.rawValue, forKey: GuidedFirstScenePolicy.key)
        isPresented = false
    }

    /// Play: closes, records it and returns the draft to apply (UIX-001-R5).
    func finish() -> GuidedFirstSceneDraft {
        defaults.set(GuidedFirstSceneState.finished.rawValue, forKey: GuidedFirstScenePolicy.key)
        isPresented = false
        return flow.draft
    }
}
