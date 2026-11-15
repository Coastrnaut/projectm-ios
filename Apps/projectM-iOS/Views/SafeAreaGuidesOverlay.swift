// SafeAreaGuidesOverlay.swift — OUT-005 (spec specs/258-out-005-safe-area-guides; contracts C2, C4).
//
// * `SafeAreaGuidesLayer`: the action-safe and title-safe outlines (and the optional centre cross) over the
//   device's visual. It lives in the visualizer's backdrop above the visual, scaled with it into UIX-007's
//   output pane, and never in the visual's own view, a `VisualSlotView` or a compositor: the external
//   display, recordings, Save Frame and offline export read only the visual, so they cannot contain the
//   guides (OUT-005-R1; research D2). Hidden from accessibility and from touches (R7).
// * With an external display showing the visual, the output frame is that display's physical shape (R4).
// * DEBUG `-uitestDiagnostics`: the almost transparent `safeAreaGuidesProbe` (research D5).
// * `SafeAreaGuidesSection`: Settings → Performance (C4). Bodies stay small (Xcode 26 type-check budget).
import PresentationLifecycle
import SwiftUI

struct SafeAreaGuidesLayer: View {
    let setting: SafeAreaGuideSetting
    let external: ExternalDisplayCoordinator
    /// OUT-004's choice (its pixel aspect shapes the external frame); nil in previews and tests.
    var output: ExternalOutputSetting? = nil

    var body: some View {
        if setting.isEnabled {
            GeometryReader { (proxy: GeometryProxy) in
                guides(in: proxy.size)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    /// The output's shape: the external display's (read with the observed values that change it), else the view's.
    private var outputAspect: Double? {
        guard external.showsVisualExternally else { return nil }
        _ = output?.pixelAspect   // observation: a pixel-aspect change redraws the frame
        return external.externalScreenAspect
    }

    @ViewBuilder private func guides(in size: CGSize) -> some View {
        let geometry: SafeAreaGuideGeometry? = SafeAreaGuideGeometry.make(viewWidth: Double(size.width), viewHeight: Double(size.height),
                                                                          outputAspect: outputAspect, choice: setting.choice)
        if let geometry {
            ZStack(alignment: .topLeading) {
                SafeAreaGuideStrokes(geometry: geometry, framed: outputAspect != nil)
                    .accessibilityHidden(true)
                #if DEBUG
                SafeAreaGuidesProbe(geometry: geometry, choice: setting.choice)
                #endif
            }
        }
    }
}

/// The outlines: the output frame (only when it is not the whole view), action-safe solid, title-safe dashed, the cross.
struct SafeAreaGuideStrokes: View {
    let geometry: SafeAreaGuideGeometry
    let framed: Bool

    static let actionColor = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.75)
    static let titleColor = Color(.sRGB, red: 1, green: 0.85, blue: 0.2, opacity: 0.85)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if framed {
                Path(Self.cgRect(geometry.output)).stroke(Self.actionColor.opacity(0.5), lineWidth: 1)
            }
            Path(Self.cgRect(geometry.actionSafe)).stroke(Self.actionColor, lineWidth: 1)
            Path(Self.cgRect(geometry.titleSafe)).stroke(Self.titleColor, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            if let arm = geometry.crossArm {
                Self.cross(geometry.output, arm: arm).stroke(Self.actionColor, lineWidth: 1)
            }
        }
    }

    static func cgRect(_ r: SafeAreaGuideRect) -> CGRect {
        CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
    }

    static func cross(_ frame: SafeAreaGuideRect, arm: Double) -> Path {
        var path = Path()
        let cx: Double = frame.midX, cy: Double = frame.midY
        path.move(to: CGPoint(x: cx - arm, y: cy))
        path.addLine(to: CGPoint(x: cx + arm, y: cy))
        path.move(to: CGPoint(x: cx, y: cy - arm))
        path.addLine(to: CGPoint(x: cx, y: cy + arm))
        return path
    }
}

#if DEBUG
/// UI-test probe (`-uitestDiagnostics` only): "action=93 title=90 cross=no frame=390x844".
private struct SafeAreaGuidesProbe: View {
    let geometry: SafeAreaGuideGeometry
    let choice: SafeAreaGuideChoice

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {
            let text: String = Self.value(geometry, choice)
            Text(text)
                .font(.caption2)
                .opacity(0.01)
                .accessibilityIdentifier("safeAreaGuidesProbe")
                .accessibilityValue(text)
        }
    }

    static func value(_ geometry: SafeAreaGuideGeometry, _ choice: SafeAreaGuideChoice) -> String {
        let frame: String = "\(Int(geometry.output.width.rounded()))x\(Int(geometry.output.height.rounded()))"
        let head: String = "action=\(choice.actionPercent) title=\(choice.drawnTitlePercent)"
        return head + " cross=" + (choice.showsCentreCross ? "yes" : "no") + " frame=" + frame
    }
}
#endif

/// Settings → Performance → Safe-area guides (contract C4).
struct SafeAreaGuidesSection: View {
    @Bindable var setting: SafeAreaGuideSetting

    static let actionSpec = AccessibleParameterSpec(id: "safeAreaActionPercent", label: SafeAreaGuideSetting.actionTitle,
                                                    range: 0.80...1.0, step: 0.01, unit: .percent(decimals: 0))
    static let titleSpec = AccessibleParameterSpec(id: "safeAreaTitlePercent", label: SafeAreaGuideSetting.titleSafeTitle,
                                                   range: 0.70...1.0, step: 0.01, unit: .percent(decimals: 0))

    var body: some View {
        Section {
            Toggle(SafeAreaGuideSetting.title, isOn: $setting.isEnabled)
                .accessibilityIdentifier("safeAreaGuidesToggle")
            if setting.isEnabled { options }
        } header: {
            Text(SafeAreaGuideSetting.sectionTitle)
        } footer: {
            Text(SafeAreaGuideSetting.footer)
        }
    }

    @ViewBuilder private var options: some View {
        percentRow(Self.actionSpec, target: Self.actionTarget(setting), value: setting.actionPercent)
        percentRow(Self.titleSpec, target: Self.titleTarget(setting), value: setting.titlePercent)
        Toggle(SafeAreaGuideSetting.crossTitle, isOn: $setting.showsCentreCross)
            .accessibilityIdentifier("safeAreaCentreCrossToggle")
    }

    static func actionTarget(_ setting: SafeAreaGuideSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in Double(setting.actionPercent) / 100 },
                        set: { (value: Double) -> Void in setting.actionPercent = Int((value * 100).rounded()) })
    }

    static func titleTarget(_ setting: SafeAreaGuideSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in Double(setting.titlePercent) / 100 },
                        set: { (value: Double) -> Void in setting.titlePercent = Int((value * 100).rounded()) })
    }

    private func percentRow(_ spec: AccessibleParameterSpec, target: ParameterTarget, value: Int) -> some View {
        let binding = Binding<Double>(get: { () -> Double in target.get() }, set: { (v: Double) -> Void in target.set(v) })
        let text: String = "\(value) %"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(spec.label)
                Spacer()
                Text(text).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Slider(value: binding, in: spec.range, step: spec.step)
                .accessibleParameter(spec, target: target)
        }
    }
}
