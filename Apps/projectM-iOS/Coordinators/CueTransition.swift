// CueTransition.swift — a cue's stored transition to the CMP-014 spec the show drives (SCN-007-R5, R6;
// contract specs/158-scn-007-transition-presets/contracts/show-cue-transition.md X4, X5).
//
// * `spec(for:)` is exact: the cue's type becomes the CMP-014 style, its duration the spec's duration (the
//   same Double) and its MOD-004 curve the spec's curve. No transition, or a type this version does not
//   know, is a cut (today's behaviour).
// * `resolved` applies the safety settings to the spec (never to the stored values): Reduce Motion makes
//   any transition a cut (CMP-014-R10); otherwise Reduce flashing spreads a cut or a transition shorter than
//   0.5 s over 0.5 s (a cut becomes a linear crossfade), and the FX-019 flash guard still measures every
//   frame the bus shows.
// * `CueTransitionDriving` receives the resolved spec just before a cue's scene is applied. The app's driver,
//   `CueTransitionStage` (XFADE, specs/167-cue-transitions-on-screen), freezes the shown compositor's frame for a
//   non-instant spec and, once the scene is applied, blends it out on the compositor shown then (Photo, Video, Text,
//   Camera outgoing). A transition from or to a native visual or projectM stays a cut (outcome `unsupported`).
// * `CueEasingPreset` names the editor's easing choices (exponent 2) and shows any other curve as Custom.
import Compositor
import Foundation
import Metal
import ParameterGraph
import ShowControl

/// Receives the transition of each cue the show applies (the bus, a recorder, a test spy).
@MainActor
protocol CueTransitionDriving: AnyObject {
    func driveTransition(_ spec: SceneTransitionSpec, toScene sceneID: String)
}

/// XFADE: a visual host whose output passes through a CMP-001 compositor (its frames are encoded on `queue`).
@MainActor
protocol CompositorVisualHost: AnyObject {
    var compositor: Compositor { get }
    var queue: MTLCommandQueue { get }
}

/// XFADE-R1, R8: the app's driver. `driveTransition` (before the scene is applied) records the spec and, for a
/// non-instant one, freezes the shown compositor's frame on that host's queue; `sceneApplied()` (after the apply)
/// starts the transition on the compositor shown then. A cut freezes nothing (the output path is unchanged).
@MainActor
final class CueTransitionStage: CueTransitionDriving {
    enum Outcome: String {
        /// No cue applied yet.
        case none
        /// An instant spec (a cut, or Reduce Motion): today's change.
        case cut
        /// The frozen frame is blended out on the shown compositor.
        case blended
        /// The outgoing or incoming visual is not compositor-backed (native, projectM): a cut.
        case unsupported
    }

    private(set) var last: SceneTransitionSpec?
    private(set) var lastSceneID: String?
    private(set) var outcome: Outcome = .none
    /// The compositor host shown now (nil: a native visual, projectM, or no visualizer).
    var shownHost: () -> (any CompositorVisualHost)? = { () -> (any CompositorVisualHost)? in nil }
    private var pending: (frame: FrozenOutputFrame, spec: SceneTransitionSpec)?
    /// The compositor running the last transition (DEBUG probe, tests).
    private(set) weak var target: Compositor?

    func driveTransition(_ spec: SceneTransitionSpec, toScene sceneID: String) {
        last = spec
        lastSceneID = sceneID
        pending = nil   // an unapplied frame goes back to the pool (FrozenOutputFrame.deinit)
        guard !spec.isInstant else {
            outcome = .cut
            return
        }
        guard let host = shownHost(), let commands = host.queue.makeCommandBuffer(),
              let frame = host.compositor.freezeShownFrame(commandBuffer: commands) else {
            outcome = .unsupported
            return
        }
        commands.label = "XFADE freeze"
        commands.commit()
        pending = (frame, spec)
    }

    /// The scene was applied: the transition starts on the compositor shown now, or the frame is dropped (a cut).
    func sceneApplied() {
        guard let pending else { return }
        self.pending = nil
        guard let host = shownHost() else {
            outcome = .unsupported
            return
        }
        host.compositor.beginOutputTransition(from: pending.frame, spec: pending.spec, reduceMotion: false)   // already resolved
        target = host.compositor
        outcome = .blended
    }

    /// XFADE-R9 (DEBUG probe): "outcome=blended frames=59 progress=1.00 holds=no".
    var probe: String {
        let frames: Int = target?.outputTransitionBlendedFrames ?? 0
        let raw: Double = target?.outputTransitionProgress ?? 1
        let progress: String = String(format: "%.2f", raw)
        let holds: String = (target?.holdsOutputTransitionTextures ?? false) ? "yes" : "no"
        return "outcome=\(outcome.rawValue) frames=\(frames) progress=\(progress) holds=\(holds)"
    }
}

enum CueTransitionResolver {
    /// SCN-007-R6: with Reduce flashing, no scene change is shorter than this.
    static let reduceFlashingMinimumSeconds: Double = 0.5

    /// The CMP-014 style of a known type (nil for an unknown one).
    static func style(_ type: ShowTransitionType) -> SceneTransitionStyle? {
        switch type {
        case .cut: .cut
        case .crossfade: .crossfade
        case .dipToBlack: .dipToBlack
        case .unknown: nil
        }
    }

    /// The exact CMP-014 spec of a cue's transition; nil or an unknown type is a cut.
    static func spec(for transition: ShowCueTransition?) -> SceneTransitionSpec {
        guard let transition, let style = style(transition.type) else { return .cut }
        // The model validated the duration and the curve with CMP-014's bounds, so this cannot throw.
        return (try? SceneTransitionSpec(style: style, durationSeconds: transition.durationSeconds, easing: .linear,
                                         curve: transition.easing)) ?? .cut
    }

    /// The spec to drive under the safety settings (SCN-007-R6).
    static func resolved(_ transition: ShowCueTransition?, reduceMotion: Bool, reduceFlashing: Bool) -> SceneTransitionSpec {
        let exact: SceneTransitionSpec = spec(for: transition)
        if reduceMotion { return exact.resolved(reduceMotion: true) }   // CMP-014-R10: a cut
        guard reduceFlashing, exact.isInstant || exact.durationSeconds < reduceFlashingMinimumSeconds else { return exact }
        let wasCut: Bool = exact.style == .cut
        let style: SceneTransitionStyle = wasCut ? .crossfade : exact.style
        let curve: MappingCurve? = wasCut ? .linear : exact.curve
        return (try? SceneTransitionSpec(style: style, durationSeconds: reduceFlashingMinimumSeconds, easing: .linear,
                                         curve: curve)) ?? exact
    }

    /// "Crossfade 1.5 s, Ease Out"; nil without a transition.
    static func summary(_ transition: ShowCueTransition?) -> String? {
        guard let transition else { return nil }
        guard transition.type.isKnown else { return transition.type.displayName }
        if transition.type == .cut { return transition.type.displayName }
        let seconds: String = durationText(transition.durationSeconds)
        let easing: String = CueEasingPreset(transition.easing).displayName(transition.easing)
        return "\(transition.type.displayName) \(seconds) s, \(easing)"
    }

    /// Up to two decimals ("1.5", "0.3", "10").
    static func durationText(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

/// The editor's easing choices.
enum CueEasingPreset: String, CaseIterable, Identifiable {
    case linear, easeIn, easeOut, easeInOut, custom

    var id: String { rawValue }

    static let exponent: Double = 2

    init(_ curve: MappingCurve) {
        switch curve {
        case .linear: self = .linear
        case let .easeIn(p) where p == Self.exponent: self = .easeIn
        case let .easeOut(p) where p == Self.exponent: self = .easeOut
        case let .easeInOut(p) where p == Self.exponent: self = .easeInOut
        default: self = .custom
        }
    }

    /// The preset's curve (nil for Custom, which keeps the stored curve).
    var curve: MappingCurve? {
        switch self {
        case .linear: .linear
        case .easeIn: .easeIn(exponent: Self.exponent)
        case .easeOut: .easeOut(exponent: Self.exponent)
        case .easeInOut: .easeInOut(exponent: Self.exponent)
        case .custom: nil
        }
    }

    var title: String {
        switch self {
        case .linear: "Linear"
        case .easeIn: "Ease In"
        case .easeOut: "Ease Out"
        case .easeInOut: "Ease In-Out"
        case .custom: "Custom"
        }
    }

    /// The title, with the curve's text form for Custom.
    func displayName(_ curve: MappingCurve) -> String { self == .custom ? "Custom (\(curve.textForm))" : title }
}
