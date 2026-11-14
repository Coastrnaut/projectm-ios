// PerformancePad.swift — UIX-005 (specs/193-uix-005-performance-controls; contract
// contracts/performance-pad.md): the performance layout's pad of large targets.
//
// While the performance layout is on, the pad stays on the visualizer with or without the controls
// (UIX-005-R2): Previous cue, Next cue, Tap tempo and Blackout, each a square of at least 60 pt (72 pt
// when both size classes are regular), with a cue readout and a tempo readout (R3). `PerformanceLayout`
// (ShowControl) picks the arrangement from the safe area's shape: a bottom bar (two rows of two when
// one row does not fit) or two side columns that keep the visual centre clear (R4). The layer reports
// the edges it uses, so VisualizerView insets the status stack and the controls never sit under it.
// Targets keep their size at every text size and show symbols only (captions failed the audit's
// clipped-text check at the largest standard sizes); every target has a VoiceOver label and offers the
// Large Content Viewer (R9, R10; research UIX-005-D4). Readouts scale with
// Dynamic Type and wrap to two lines (then truncate); in a side column the readout gives way to the
// targets (lower layout priority), so the targets stay on screen in a landscape iPhone at AX5.
// The pad is drawn on the device only (R11).
import PerformanceControl
import PresentationLifecycle
import ShowControl
import SwiftUI

/// UIX-005-R7, R8 (research UIX-005-D5): the Blackout target's state for an output phase. Live or
/// fading in: black out, with the B key (SHOW-014's corner button is hidden while the pad shows).
/// Blacked out: restore (the badge's Restore keeps B). A restore that waits: disabled.
struct PerformancePadBlackout: Equatable {
    let title: String
    let icon: String
    let isEnabled: Bool
    /// The tap blacks out (true) or restores (false).
    let blacksOut: Bool
    /// The target carries the B key in this phase.
    let carriesBKey: Bool
    let value: String

    static func make(_ phase: OutputBlackout.Phase) -> PerformancePadBlackout {
        if phase.offersEmergencyBlackout {
            return PerformancePadBlackout(title: "Black out output", icon: "eye.slash", isEnabled: true,
                                          blacksOut: true, carriesBKey: true, value: phase.accessibilityValue)
        }
        if phase.offersRestore {
            return PerformancePadBlackout(title: "Restore output", icon: "eye", isEnabled: true,
                                          blacksOut: false, carriesBKey: false, value: phase.accessibilityValue)
        }
        return PerformancePadBlackout(title: "Restoring output", icon: "eye", isEnabled: false,
                                      blacksOut: false, carriesBKey: false, value: phase.accessibilityValue)
    }

    /// The tap's effect: OUT-010's blackout, the same call as SHOW-014's emergency button.
    @MainActor func perform(_ external: ExternalDisplayCoordinator) {
        guard isEnabled else { return }
        external.setBlackout(blacksOut)
    }
}

/// The pad's layer: fills the safe area, draws the arrangement, reports the edges it reserves.
///
/// It takes the cue list, the tempo and the output rather than the whole AppCoordinator: the first
/// member lookup on AppCoordinator in a file costs about 220 ms of type-checking (CI budget 200 ms).
/// Its actions step the show and record taps directly, never through the controls' wrappers that
/// show the controls (UIX-005-R5, R6; research UIX-005-D6).
struct PerformancePadLayer: View {
    let show: ShowCoordinator
    let tempo: TempoCoordinator
    let external: ExternalDisplayCoordinator
    /// SHOW-002-R9: the timed advance's countdown for the cue readout (nil in previews).
    var advance: ShowAutoAdvanceCoordinator? = nil
    /// The edges the pad uses (UIX-005-R4, research UIX-005-D3).
    let onReservedInsets: (EdgeInsets) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalClass
    @Environment(\.verticalSizeClass) private var verticalClass
    @State private var area: CGRect = .zero
    @State private var barHeight: CGFloat = 0

    private var layout: PerformanceLayout {
        let regular: Bool = horizontalClass == .regular && verticalClass == .regular
        return PerformanceLayout(width: Double(area.width), height: Double(area.height), regular: regular)
    }

    private var reserved: PerformanceLayout.Insets { layout.reservedInsets(barHeight: Double(barHeight)) }

    var body: some View {
        ZStack { arranged }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { (proxy: GeometryProxy) -> CGRect in proxy.frame(in: .global) }
                action: { (frame: CGRect) in area = frame }
            .onChange(of: reserved, initial: true) { (_: PerformanceLayout.Insets, new: PerformanceLayout.Insets) in
                onReservedInsets(EdgeInsets(top: new.top, leading: new.leading, bottom: new.bottom, trailing: new.trailing))
            }
            .onDisappear { onReservedInsets(EdgeInsets()) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Performance controls")
            .accessibilityIdentifier("performancePad")
            .overlay(alignment: .topLeading) { safeAreaProbe }
    }

    @ViewBuilder private var arranged: some View {
        switch layout.arrangement {
        case .sideColumns: columns
        case .bottomBar, .bottomGrid: bar
        }
    }

    // MARK: Arrangements

    private var bar: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            barContent
                .onGeometryChange(for: CGFloat.self) { (proxy: GeometryProxy) -> CGFloat in proxy.size.height }
                    action: { (height: CGFloat) in barHeight = height }
        }
        .padding(.horizontal, layout.margin)
    }

    private var barContent: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                cueReadout
                Spacer(minLength: 0)
                tempoReadout
            }
            if layout.arrangement == .bottomGrid {
                VStack(spacing: layout.spacing) {
                    HStack(spacing: layout.spacing) { previousTarget; nextTarget }
                    HStack(spacing: layout.spacing) { tapTarget; blackoutTarget }
                }
            } else {
                HStack(spacing: layout.spacing) { previousTarget; nextTarget; tapTarget; blackoutTarget }
            }
        }
    }

    private var columns: some View {
        HStack(spacing: 0) {
            column { cueReadout.layoutPriority(-1); previousTarget; nextTarget }
            Spacer(minLength: 0)
            column { tempoReadout.layoutPriority(-1); tapTarget; blackoutTarget }
        }
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: layout.spacing) { content() }
            .frame(width: layout.target)
            .padding(.horizontal, layout.margin)
            .frame(maxHeight: .infinity)
    }

    // MARK: Targets

    private var previousTarget: some View {
        let list: ShowCueList = show.list
        let enabled: Bool = list.canGoPrevious
        let button = PerformancePadButton(title: "Previous cue", icon: "chevron.backward",
                                          side: layout.target, identifier: "perfPreviousCue",
                                          action: { () -> Void in show.previous() })
        return button.disabled(!enabled)
    }

    private var nextTarget: some View {
        let list: ShowCueList = show.list
        let enabled: Bool = list.canGoNext
        let button = PerformancePadButton(title: "Next cue", icon: "chevron.forward",
                                          side: layout.target, identifier: "perfNextCue",
                                          action: { () -> Void in show.next() })
        return button.disabled(!enabled)
    }

    private var tapTarget: some View {
        let value: String = tempo.tapValue
        return PerformancePadButton(title: "Tap tempo", icon: "hand.tap", side: layout.target,
                                    identifier: "perfTapTempo", value: value,
                                    hint: "Tap in time with the music, four times, to set the tempo",
                                    action: { () -> Void in tempo.tap() })
    }

    private var blackoutTarget: some View {
        let external: ExternalDisplayCoordinator = self.external
        let state: PerformancePadBlackout = .make(external.blackoutPhase)
        let button = PerformancePadButton(title: state.title, icon: state.icon, side: layout.target,
                                          identifier: "perfBlackout", value: state.value,
                                          action: { () -> Void in state.perform(external) })
        return button.disabled(!state.isEnabled).modifier(BlackoutKey(active: state.carriesBKey))
    }

    /// SHOW-014-R6 moved here while the pad shows (UIX-005-R8): B blacks out while live or fading in.
    private struct BlackoutKey: ViewModifier {
        let active: Bool

        @ViewBuilder func body(content: Content) -> some View {
            if active {
                content.keyboardShortcut("b", modifiers: [])
            } else {
                content
            }
        }
    }

    // MARK: Readouts

    private var cueReadout: some View {
        let list: ShowCueList = show.list
        var top: String
        let bottom: String
        if let cue = list.activeCue {
            top = list.positionText
            bottom = cue.label
        } else if show.hasCues {
            top = "Standby"
            bottom = list.cues.count == 1 ? "1 cue" : "\(list.cues.count) cues"
        } else {
            top = "No cues"
            bottom = "Show"
        }
        var spoken: String = show.hasCues ? show.accessibilityValue : "No cues"
        if let countdown = advance?.countdownText, let said = advance?.spokenCountdown {   // SHOW-002-R9
            top += " · \(countdown.replacingOccurrences(of: "Next in ", with: ""))"
            spoken += ", \(said)"
        }
        return PerformanceReadout(top: top, bottom: bottom, label: "Show", value: spoken, identifier: "perfCueReadout",
                                  alignment: .leading)
    }

    private var tempoReadout: some View {
        let readout: TempoReadout = tempo.readout
        return PerformanceReadout(top: TempoCoordinator.readoutText(readout), bottom: TempoCoordinator.stateText(readout),
                                  label: "Tempo", value: TempoCoordinator.accessibilityValue(readout),
                                  identifier: "perfTempoReadout", alignment: .trailing)
    }

    /// Contract C1 (`-uitestDiagnostics` only, research UIX-005-D7): the safe-area frame in window
    /// coordinates, "x,y,w,h", for the UI tests' inside-the-safe-area checks.
    @ViewBuilder private var safeAreaProbe: some View {
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {
            let value: String = [area.minX, area.minY, area.width, area.height]
                .map { (v: CGFloat) -> String in String(format: "%.1f", Double(v)) }
                .joined(separator: ",")
            Text(value)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("performanceSafeArea")
                .accessibilityValue(value)
        }
    }
}

/// One large square target (UIX-005-R3, R9, R10).
struct PerformancePadButton: View {
    let title: String
    let icon: String
    let side: Double
    let identifier: String
    let value: String?
    let hint: String?
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    /// An explicit initializer: the memberwise one with defaults cost about 200 ms to type-check per call.
    init(title: String, icon: String, side: Double, identifier: String, value: String? = nil,
         hint: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.side = side
        self.identifier = identifier
        self.value = value
        self.hint = hint
        self.action = action
    }

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(PadButtonStyle())
            .accessibilityLabel(title)
            .accessibilityValue(value ?? "")
            .accessibilityHint(hint ?? "")
            .accessibilityIdentifier(identifier)
            .accessibilityShowsLargeContentViewer { Label(title, systemImage: icon) }
    }

    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        return Image(systemName: icon)
            .font(.system(size: (side * 0.4).rounded(), weight: .semibold))
            // Disabled: 70 % white, still well above 4.5:1 on the dark surface; VoiceOver reads it as dimmed.
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.7))
            .frame(width: side, height: side)
            .overlaySurface(shape)   // ACC-008-R2
            .contentShape(shape)
    }
}

/// A two-line readout on the overlay surface (cue or tempo).
struct PerformanceReadout: View {
    let top: String
    let bottom: String
    let label: String
    let value: String
    let identifier: String
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(top).font(.footnote.monospacedDigit().bold())
            Text(bottom).font(.footnote)
        }
        .lineLimit(2)
        .truncationMode(.tail)
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlaySurface(RoundedRectangle(cornerRadius: 10))   // ACC-008-R2
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier(identifier)
        .accessibilityShowsLargeContentViewer { Text(top + " " + bottom) }
    }
}

/// The pad's own button style: the label sets its disabled look itself (70 % white); a press dims it.
private struct PadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}
