// OneHandedControls.swift — ACC-009 (specs/244-acc-009-one-handed-mode; R2-R5, R7, R8; contract C1, C3): the
// one-handed layout's cluster of critical targets and its Settings section.
//
// While a hand is chosen (iPhone only), the controls card leaves out Stop, Pause/Resume, Previous, Next, Random,
// Presets, Settings, Black out, Tap tempo and the cue arrows (ControlsOverlay, TempoControls, ShowCueRow), and this
// layer draws them as square targets at `OneHandedLayout`'s frames in the thumb zone of the chosen side, with the
// standard identifiers, labels, values and hints (research ACC-009-D4). With the UIX-005 pad on, the pad's own layer
// draws its four targets at the same layout's pad frames (PerformancePad.swift), so this layer draws only the main
// group. The layer reports the edge band the layout reserves; VisualizerView insets the status stack (controls card,
// HUD, rehearsal panel, badges) by it, so nothing sits under the cluster.
// Targets show symbols only and offer the Large Content Viewer (PerformancePadButton, as UIX-005-R9, R10).
import ShowControl
import SwiftUI

extension OneHandedLayout {
    /// The layout both the cluster and the pad compute for the same safe area (they must agree, ACC-009-R7).
    /// `readoutHeight`: the pad's readout strip (Dynamic Type scaled), kept only while the pad is on.
    static func forArea(_ area: CGRect, hand: OneHandedHand, scaledBase: CGFloat, padOn: Bool, regular: Bool,
                        actions: [CriticalAction], readoutHeight: CGFloat) -> OneHandedLayout {
        let pad: Double? = padOn ? (regular ? PerformanceLayout.regularTarget : PerformanceLayout.compactTarget) : nil
        let readouts: Double = padOn ? min(Double(readoutHeight), maximumReadoutHeight) : 0
        return OneHandedLayout(width: Double(area.width), height: Double(area.height), hand: hand,
                               baseTarget: Double(scaledBase), padTarget: pad, actions: actions, readoutHeight: readouts)
    }

    /// The readout strip's cap (two lines of footnote text at the larger accessibility sizes).
    static let maximumReadoutHeight: Double = 88
}

/// One critical target's look and effect.
struct OneHandedItem {
    let title: String
    let icon: String
    var value: String? = nil
    var hint: String? = nil
    var enabled: Bool = true
    let perform: () -> Void
}

/// The cluster's layer: fills the safe area, draws the main group (and the pad group when the pad is off).
struct OneHandedControlsLayer: View {
    let coordinator: AppCoordinator
    let hand: OneHandedHand
    /// The edge band the cluster reserves (ACC-009-R5).
    let onReservedInsets: (EdgeInsets) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalClass
    @Environment(\.verticalSizeClass) private var verticalClass
    /// The Dynamic Type base side (research ACC-009-D5; clamped to 44…56 by the layout).
    @ScaledMetric(relativeTo: .title3) private var scaledBase: CGFloat = 44
    /// The pad's readout strip (the pad layer uses the same metric).
    @ScaledMetric(relativeTo: .footnote) private var readoutHeight: CGFloat = 44
    @State private var area: CGRect = .zero
    /// The layer's own size (layout space): a sheet's presentation transform moves the global frame without always
    /// reporting it back, which left the cluster 88 pt low after Settings closed (UI test, 2026-11-14).
    @State private var size: CGSize = .zero

    private var layout: OneHandedLayout {
        let context: CriticalActionContext = coordinator.oneHandedContext
        let regular: Bool = horizontalClass == .regular && verticalClass == .regular
        return OneHandedLayout.forArea(CGRect(origin: .zero, size: size), hand: hand, scaledBase: scaledBase, padOn: context.padOn, regular: regular,
                                       actions: CriticalAction.displayed(context), readoutHeight: readoutHeight)
    }

    private var reserved: PerformanceLayout.Insets { layout.reservedInsets }

    var body: some View {
        let current: OneHandedLayout = layout
        return ZStack(alignment: .topLeading) {
            ForEach(drawn(current)) { (entry: Placed) in
                target(entry.action, side: entry.rect.width)
                    .position(x: entry.rect.midX, y: entry.rect.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGRect.self) { (proxy: GeometryProxy) -> CGRect in proxy.frame(in: .global) }
            action: { (frame: CGRect) in area = frame }
        .onGeometryChange(for: CGSize.self) { (proxy: GeometryProxy) -> CGSize in proxy.size }
            action: { (new: CGSize) in size = new }
        .onChange(of: reserved, initial: true) { (_: PerformanceLayout.Insets, new: PerformanceLayout.Insets) in
            onReservedInsets(EdgeInsets(top: new.top, leading: new.leading, bottom: new.bottom, trailing: new.trailing))
        }
        .onDisappear { onReservedInsets(EdgeInsets()) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("oneHandedControls")
        .overlay(alignment: .topLeading) { zoneProbe(current) }
    }

    struct Placed: Identifiable {
        let action: CriticalAction
        let rect: OneHandedLayout.Rect
        var id: CriticalAction { action }
    }

    /// The frames this layer draws: with the pad on, its layer draws the pad group.
    private func drawn(_ layout: OneHandedLayout) -> [Placed] {
        let padOn: Bool = coordinator.performanceLayout
        return layout.frames.compactMap { (entry: (action: CriticalAction, rect: OneHandedLayout.Rect)) -> Placed? in
            padOn && entry.action.isPadAction ? nil : Placed(action: entry.action, rect: entry.rect)
        }
    }

    private func target(_ action: CriticalAction, side: Double) -> some View {
        let item: OneHandedItem = OneHandedItems.item(action, coordinator: coordinator)
        let button = PerformancePadButton(title: item.title, icon: item.icon, side: side, identifier: action.identifier,
                                          value: item.value, hint: item.hint, action: item.perform)
        return button.disabled(!item.enabled)
    }

    /// Contract C3 (`-uitestDiagnostics` only): the thumb zone in window coordinates, "x,y,w,h", for the UI tests.
    @ViewBuilder private func zoneProbe(_ layout: OneHandedLayout) -> some View {
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {
            let zone: OneHandedLayout.Rect = layout.zone
            let parts: [Double] = [Double(area.minX) + zone.x, Double(area.minY) + zone.y, zone.width, zone.height]
            let value: String = parts.map { (v: Double) -> String in String(format: "%.1f", v) }.joined(separator: ",")
            Text(value)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("oneHandedZone")
                .accessibilityValue(value)
        }
    }
}

/// The critical targets' titles, symbols and effects: the same as the standard controls (ControlsOverlay,
/// TempoControls, ShowCueRow), so the switch changes where they are, not what they do (ACC-009-R8).
@MainActor
enum OneHandedItems {
    static func item(_ action: CriticalAction, coordinator: AppCoordinator) -> OneHandedItem {
        switch action {
        case .cuePrevious, .cueNext, .tapTempo, .blackout: padItem(action, coordinator: coordinator)
        case .previous, .next, .random, .presets: presetItem(action, coordinator: coordinator)
        case .pauseResume, .settings, .stop: sessionItem(action, coordinator: coordinator)
        }
    }

    private static func padItem(_ action: CriticalAction, coordinator: AppCoordinator) -> OneHandedItem {
        switch action {
        case .cuePrevious:
            let enabled: Bool = coordinator.show.list.canGoPrevious
            return OneHandedItem(title: "Previous cue", icon: "chevron.backward", enabled: enabled) { () -> Void in
                coordinator.showPreviousCue()
            }
        case .cueNext:
            let enabled: Bool = coordinator.show.list.canGoNext
            return OneHandedItem(title: "Next cue", icon: "chevron.forward", enabled: enabled) { () -> Void in
                coordinator.showNextCue()
            }
        case .tapTempo:
            let value: String = coordinator.tempo.tapValue
            return OneHandedItem(title: "Tap tempo", icon: "hand.tap", value: value,
                                 hint: "Tap in time with the music, four times, to set the tempo") { () -> Void in
                coordinator.tapTempo()
            }
        default:
            return blackoutItem(coordinator.externalDisplay)
        }
    }

    /// OUT-010: one tap blacks out, one tap restores (as the card's Black out).
    private static func blackoutItem(_ external: ExternalDisplayCoordinator) -> OneHandedItem {
        let requested: Bool = external.isBlackoutRequested
        let hint: String = requested ? "Shows the visualization on the output again" : "Makes the output black"
        return OneHandedItem(title: requested ? "Restore output" : "Black out output", icon: requested ? "eye" : "eye.slash",
                             value: external.blackoutPhase.accessibilityValue, hint: hint) { () -> Void in
            external.toggleBlackout()
        }
    }

    private static func presetItem(_ action: CriticalAction, coordinator: AppCoordinator) -> OneHandedItem {
        switch action {
        case .previous:
            return OneHandedItem(title: "Previous", icon: "backward.fill", hint: "Plays the previous preset in the list") { () -> Void in
                coordinator.previous()
            }
        case .next:
            return OneHandedItem(title: "Next", icon: "forward.fill", hint: "Plays the next preset in the list") { () -> Void in
                coordinator.next()
            }
        case .random:
            return OneHandedItem(title: "Random", icon: "shuffle", hint: "Plays a random preset from the list") { () -> Void in
                coordinator.random()
            }
        default:
            return OneHandedItem(title: "Presets", icon: "list.bullet", hint: "Opens the preset browser") { () -> Void in
                coordinator.showPresetBrowser = true
            }
        }
    }

    private static func sessionItem(_ action: CriticalAction, coordinator: AppCoordinator) -> OneHandedItem {
        switch action {
        case .pauseResume:
            let paused: Bool = coordinator.userPaused
            return OneHandedItem(title: paused ? "Resume" : "Pause", icon: paused ? "play.fill" : "pause.fill") { () -> Void in
                coordinator.togglePause()
            }
        case .settings:
            return OneHandedItem(title: "Settings", icon: "gearshape") { () -> Void in coordinator.showSettings = true }
        default:
            return OneHandedItem(title: "Stop", icon: "stop.fill") { () -> Void in coordinator.stop() }
        }
    }
}

/// ACC-009-R1: Settings → One-handed layout (Off, Left hand, Right hand), iPhone only.
struct OneHandedSection: View {
    @Bindable var setting: OneHandedSetting

    var body: some View {
        Section {
            OneHandedRow(setting: setting, hand: nil, title: "Off", identifier: "oneHanded.off")
            OneHandedRow(setting: setting, hand: .left, title: "Left hand", identifier: "oneHanded.left")
            OneHandedRow(setting: setting, hand: .right, title: "Right hand", identifier: "oneHanded.right")
        } header: {
            Text(OneHandedSetting.title)
        } footer: {
            Text(OneHandedSetting.footer)
        }
    }
}

private struct OneHandedRow: View {
    @Bindable var setting: OneHandedSetting
    let hand: OneHandedHand?
    let title: String
    let identifier: String

    var body: some View {
        let selected: Bool = setting.hand == hand
        Button {
            setting.hand = hand
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}
