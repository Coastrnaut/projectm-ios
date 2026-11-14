// SplitEditorHost.swift — UIX-007 (specs/205-uix-007-split-preview-editor, contract split-editor.md):
// on iPad in regular width, Settings opens in an editor pane beside the live output instead of a sheet.
//
// * `SplitEditorHost` measures the whole window and builds `SplitEditorLayout` (ShowControl). It lays
//   the backdrop (black and the visual) out at the full window size, and the visualizer's other layers
//   with, while Settings is open and the split fits, the divider and the editor as a trailing safe-area
//   inset (research UIX-007-D4): the status stack, controls and badges lay out in the output pane at
//   their real size (compact width there); the editor lies above the views that ignore the safe area.
// * The visual is never re-laid out (D1): `.splitOutputScaled()` only draws it scaled (render-only
//   transforms) into the layout's output rect, so its aspect ratio is the window's for every editor
//   width, and the drawable, recordings and OUT-004's device shape are unchanged (R3, R4).
// * `SplitEditorDivider`: drag (live, snap on release, stored), adjustable VoiceOver element (R5, R6).
// * DEBUG `-uitestDiagnostics`: the `splitOutputFrame` probe reads the device slot's frame from UIKit (C4).
// Bodies stay small (Xcode 26 type-check budget).
import ShowControl
import SwiftUI
import UIKit

/// Where the visual is drawn: its full size and the uniform scale and offset into the output rect.
struct SplitOutputPlacement: Equatable {
    var fullSize: CGSize
    var scale: CGFloat
    var origin: CGPoint

    static func identity(_ size: CGSize) -> SplitOutputPlacement {
        SplitOutputPlacement(fullSize: size, scale: 1, origin: .zero)
    }
}

extension EnvironmentValues {
    /// UIX-007: the visual's placement (nil outside a `SplitEditorHost`: the visual is left as it is).
    @Entry var splitOutputPlacement: SplitOutputPlacement? = nil
    /// UIX-007-R8: closes the split editor (Settings' Done calls it instead of `dismiss`); nil in a sheet.
    @Entry var splitEditorClose: (@MainActor () -> Void)? = nil
}

private struct SplitOutputScaled: ViewModifier {
    @Environment(\.splitOutputPlacement) private var placement: SplitOutputPlacement?

    func body(content: Content) -> some View {
        if let placement {
            // Render-only transforms (layout is unchanged): the host lays the backdrop out at the full
            // window size, outside the editor's inset, so the visual keeps its frame and is only drawn
            // scaled into the output rect. The same modifiers whether split or not (scale 1, origin 0)
            // keep its identity.
            content
                .scaleEffect(placement.scale, anchor: .topLeading)
                .offset(x: placement.origin.x, y: placement.origin.y)
        } else {
            content
        }
    }
}

extension View {
    /// UIX-007-R3, R4: draws the visual at its full window size, scaled uniformly into the output rect.
    func splitOutputScaled() -> some View { modifier(SplitOutputScaled()) }
}

struct SplitEditorHost<Backdrop: View, Content: View, Editor: View>: View {
    /// The black background and the visual: always the full window, never inset (research UIX-007-D4).
    let backdrop: Backdrop
    /// Everything else (status, controls, overlays): laid out in the output pane while the editor shows.
    let content: Content
    /// Settings is open (`AppCoordinator.showSettings`).
    let isOpen: Bool
    let setting: SplitEditorSetting
    let motion: MotionPolicy
    /// Whether the split can show the editor now (regular width and wide enough): Settings is a sheet otherwise.
    let onAvailabilityChange: (Bool) -> Void
    let close: @MainActor () -> Void
    @ViewBuilder let editor: () -> Editor

    @Environment(\.horizontalSizeClass) private var sizeClass: UserInterfaceSizeClass?
    /// The editor width while a drag is in progress (nil otherwise).
    @State private var dragWidth: Double?

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            hosted(window: Self.windowSize(proxy))
        }
        .ignoresSafeArea()
    }

    /// The whole window: the reader ignores the safe area, so its size is the window's.
    private static func windowSize(_ proxy: GeometryProxy) -> CGSize { proxy.size }

    private func layout(_ window: CGSize) -> SplitEditorLayout {
        SplitEditorLayout(containerWidth: Double(window.width), containerHeight: Double(window.height),
                          editorWidth: dragWidth ?? setting.width)
    }

    private func available(_ layout: SplitEditorLayout) -> Bool { sizeClass == .regular && layout.fits }

    private func hosted(window: CGSize) -> some View {
        let layout: SplitEditorLayout = layout(window)
        let available: Bool = available(layout)
        let shown: Bool = available && isOpen
        return ZStack(alignment: .topLeading) {
            backdrop
                .frame(width: window.width, height: window.height)
                .environment(\.splitOutputPlacement, shown ? Self.placement(layout, window: window) : .identity(window))
            insetContent(layout, shown: shown)
        }
        .onAppear { onAvailabilityChange(available) }
        .onChange(of: available) { (_: Bool, now: Bool) -> Void in onAvailabilityChange(now) }
    }

    private func insetContent(_ layout: SplitEditorLayout, shown: Bool) -> some View {
        content
            // The output pane is narrower than the window: the controls and the pad use their compact
            // layouts there, so nothing outgrows the pane and pushes the editor off screen (UIX-007-R9).
            .environment(\.horizontalSizeClass, shown ? .compact : sizeClass)
            .safeAreaInset(edge: .trailing, spacing: 0) { inset(layout, shown: shown) }
            .overlay { probe }
    }

    static func placement(_ layout: SplitEditorLayout, window: CGSize) -> SplitOutputPlacement {
        let rect: SplitEditorLayout.Rect = layout.outputRect
        return SplitOutputPlacement(fullSize: window, scale: CGFloat(layout.scale), origin: CGPoint(x: rect.x, y: rect.y))
    }

    @ViewBuilder private func inset(_ layout: SplitEditorLayout, shown: Bool) -> some View {
        if shown {
            HStack(spacing: 0) {
                SplitEditorDivider(layout: layout, width: layout.editorWidth,
                                   onDrag: { (width: Double) -> Void in dragWidth = width },
                                   onRelease: { (width: Double) -> Void in release(width, layout: layout) },
                                   onStep: { (width: Double) -> Void in setting.width = width })
                editorPane(width: layout.editorWidth)
            }
            .ignoresSafeArea(.container, edges: .vertical)
            .transition(.move(edge: .trailing))
        }
    }

    private func editorPane(width: Double) -> some View {
        VStack(spacing: 0) { editor() }
            .environment(\.splitEditorClose, close)
            .frame(width: CGFloat(width))
            .background(Color(uiColor: .systemGroupedBackground))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("splitEditorPane")
    }

    /// R5: the released width snaps (animated, instant with Reduce Motion) and is remembered.
    private func release(_ width: Double, layout: SplitEditorLayout) {
        let snapped: Double = layout.snapped(width)
        withAnimation(motion.decoration(MotionPolicy.controlsFade)) {
            dragWidth = nil
            setting.width = snapped
        }
    }

    @ViewBuilder private var probe: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") { SplitOutputProbe() }
        #endif
    }
}

/// The divider: a 24 pt hit area with a 1 pt line and a grip (UIX-007-R5, R6; research D7).
struct SplitEditorDivider: View {
    let layout: SplitEditorLayout
    let width: Double
    let onDrag: (Double) -> Void
    let onRelease: (Double) -> Void
    let onStep: (Double) -> Void

    @State private var startWidth: Double?

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Rectangle().fill(Color(uiColor: .separator)).frame(width: 1)
            Capsule().fill(Color(uiColor: .tertiaryLabel)).frame(width: 5, height: 44)
        }
        .frame(width: CGFloat(SplitEditorLayout.dividerWidth))
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .gesture(drag)
        .accessibilityElement()
        .accessibilityLabel("Editor width")
        .accessibilityValue(Self.value(width))
        .accessibilityHint("Swipe up or down to change the editor's width.")
        .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) -> Void in step(direction) }
        .accessibilityIdentifier("splitEditorDivider")
    }

    /// Dragging left widens the editor (it is on the trailing side).
    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { (value: DragGesture.Value) -> Void in
                let start: Double = startWidth ?? width
                if startWidth == nil { startWidth = width }
                onDrag(start - Double(value.translation.width))
            }
            .onEnded { (value: DragGesture.Value) -> Void in
                let start: Double = startWidth ?? width
                startWidth = nil
                onRelease(start - Double(value.translation.width))
            }
    }

    private func step(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: onStep(layout.nextSnap(after: width))
        case .decrement: onStep(layout.previousSnap(before: width))
        @unknown default: break
        }
    }

    /// "400 points, Standard" at a snap point, else "437 points".
    static func value(_ width: Double) -> String {
        let points: String = "\(Int(width.rounded())) points"
        guard let name = SplitEditorLayout.snapName(for: width) else { return points }
        return points + ", " + name
    }
}

#if DEBUG
/// C4: "x,y,w,h|W,H|bw,bh": the device slot's frame in window coordinates (transforms applied), the
/// window's size and the slot's own bounds size; "none" without a slot.
private struct SplitOutputProbe: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let value: String = Self.measure()
            Text(value)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("splitOutputFrame")
                .accessibilityValue(value)
        }
    }

    @MainActor static func measure() -> String {
        let windows: [UIWindow] = UIApplication.shared.connectedScenes
            .compactMap { (scene: UIScene) -> UIWindowScene? in scene as? UIWindowScene }
            .flatMap { (scene: UIWindowScene) -> [UIWindow] in scene.windows }
        for window in windows {
            guard let slot = deviceSlot(in: window) else { continue }
            let frame: CGRect = slot.convert(slot.bounds, to: window)
            let parts: [CGFloat] = [frame.minX, frame.minY, frame.width, frame.height]
            let rect: String = parts.map(format).joined(separator: ",")
            let size: String = format(window.bounds.width) + "," + format(window.bounds.height)
            let bounds: String = format(slot.bounds.width) + "," + format(slot.bounds.height)
            return rect + "|" + size + "|" + bounds
        }
        return "none"
    }

    @MainActor private static func deviceSlot(in view: UIView) -> VisualSlotView? {
        if let slot = view as? VisualSlotView, slot.role == .device { return slot }
        for child in view.subviews {
            if let found = deviceSlot(in: child) { return found }
        }
        return nil
    }

    private static func format(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }
}
#endif
