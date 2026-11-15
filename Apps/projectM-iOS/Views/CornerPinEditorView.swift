// CornerPinEditorView.swift — OUT-007-T07 (spec specs/264-out-007-corner-pin, contract C4; research OUT-007-D7):
// the full-screen corner-pin editor opened from Settings › External Display › Corner pin….
//
// * The canvas shows the external display's shape (dashed) and the corrected picture's outline, with four
//   draggable handles (44 pt targets). A drag moves its corner to the finger; `CornerPin.moving` clamps it to
//   the allowed range and refuses a shape that would fold, so the last valid pin stays (OUT-007-R4).
// * VoiceOver: each handle is one element ("Top left", value "3 % across, 0 % down") with four named actions
//   (Move left, right, up, down; one nudge step each). Below the canvas a corner picker and four nudge buttons
//   do the same for everyone, and Reset restores the identity (OUT-007-R5).
// * Open: the coordinator's calibration flag is on, so a connected display shows the test card through the
//   current warp; Done or dismissal turns it off (the live visual returns).
import PresentationLifecycle
import SwiftUI

struct CornerPinEditorView: View {
    @Bindable var setting: ExternalOutputSetting
    /// The display's shape (width ÷ height).
    let aspect: Double
    let onDone: () -> Void

    @State private var selected: CornerPin.Corner = .topLeft

    /// The canvas shows output coordinates −0.3…1.3 in both directions (the display is the middle 62.5 %).
    static let worldMin = -0.3
    static let worldSpan = 1.6

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas
                probe
                controls
            }
            .navigationTitle(ExternalOutputSetting.cornerPinEditorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneItem }
        }
        .onAppear { setting.external?.beginCalibration() }
        .onDisappear { setting.external?.endCalibration() }
    }

    private var doneItem: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: onDone)
                .accessibilityIdentifier("cornerPinDone")
        }
    }

    /// DEBUG (UI tests): the coordinator's `cornerPinSummary` while the editor covers the visualizer's probe.
    @ViewBuilder private var probe: some View {
        #if DEBUG
        let calibrating: Bool = setting.external?.isCalibrating == true   // observed: re-renders when the card shows
        let summary: String = setting.external?.cornerPinSummary ?? "none"
        let text: String = setting.cornerPin.stored + "|" + summary + (calibrating ? "|calibrating" : "|idle")
        Text(text)
            .font(.caption2)
            .frame(height: 1)
            .opacity(0.01)
            .accessibilityIdentifier("cornerPinProbe")
            .accessibilityValue(text)
        #endif
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { (proxy: GeometryProxy) in
            let frame: CGRect = Self.worldFrame(in: proxy.size, aspect: aspect)
            ZStack(alignment: .topLeading) {
                outlines(frame)
                ForEach(CornerPin.Corner.allCases, id: \.self) { (corner: CornerPin.Corner) in
                    handle(corner, frame: frame)
                }
            }
            .coordinateSpace(name: "cornerPinCanvas")
        }
        .background(Color(white: 0.12))
        .frame(maxWidth: .infinity)
        .frame(minHeight: 240)
        .clipped()
    }

    /// The rectangle (in canvas points) that shows world coordinates −0.3…1.3, with the display's shape.
    static func worldFrame(in size: CGSize, aspect: Double) -> CGRect {
        let inset: CGFloat = 12
        let width: CGFloat = max(size.width - inset * 2, 1), height: CGFloat = max(size.height - inset * 2, 1)
        let shape = CGFloat(max(aspect, 0.1))
        let fitted: CGSize = width / height > shape ? CGSize(width: height * shape, height: height)
            : CGSize(width: width, height: width / shape)
        let origin = CGPoint(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2)
        return CGRect(origin: origin, size: fitted)
    }

    static func canvasPoint(_ p: CornerPinPoint, in frame: CGRect) -> CGPoint {
        let u = CGFloat((p.x - worldMin) / worldSpan), v = CGFloat((p.y - worldMin) / worldSpan)
        return CGPoint(x: frame.minX + u * frame.width, y: frame.minY + v * frame.height)
    }

    static func outputPoint(_ c: CGPoint, in frame: CGRect) -> CornerPinPoint {
        let u = Double((c.x - frame.minX) / max(frame.width, 1)), v = Double((c.y - frame.minY) / max(frame.height, 1))
        return CornerPinPoint(x: worldMin + u * worldSpan, y: worldMin + v * worldSpan)
    }

    private func outlines(_ frame: CGRect) -> some View {
        let display: [CornerPinPoint] = CornerPin.identity.corners
        let quad: [CornerPinPoint] = setting.cornerPin.corners
        return ZStack {
            Self.path(display, frame).stroke(Color.gray, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            Self.path(quad, frame).fill(Color.teal.opacity(0.25))
            Self.path(quad, frame).stroke(Color.teal, lineWidth: 2)
        }
        .accessibilityHidden(true)
    }

    static func path(_ points: [CornerPinPoint], _ frame: CGRect) -> Path {
        var path = Path()
        let mapped: [CGPoint] = points.map { (p: CornerPinPoint) -> CGPoint in canvasPoint(p, in: frame) }
        path.addLines(mapped)
        path.closeSubpath()
        return path
    }

    private func handle(_ corner: CornerPin.Corner, frame: CGRect) -> some View {
        let point: CornerPinPoint = setting.cornerPin.point(corner)
        let position: CGPoint = Self.canvasPoint(point, in: frame)
        let isSelected: Bool = corner == selected
        return Circle()
            .fill(isSelected ? Color.yellow : Color.white)
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(Color.black, lineWidth: 2))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(position)
            .gesture(drag(corner, frame: frame))
            .accessibilityElement()
            .accessibilityLabel(ExternalOutputSetting.title(corner))
            .accessibilityValue(ExternalOutputSetting.spokenValue(corner, point))
            .accessibilityIdentifier("cornerPinHandle." + corner.rawValue)
            .accessibilityActions { moveActions(corner) }
    }

    private func drag(_ corner: CornerPin.Corner, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("cornerPinCanvas"))
            .onChanged { (value: DragGesture.Value) -> Void in
                selected = corner
                let target: CornerPinPoint = Self.outputPoint(value.location, in: frame)
                setting.cornerPin = setting.cornerPin.moving(corner, to: target)
            }
    }

    @ViewBuilder private func moveActions(_ corner: CornerPin.Corner) -> some View {
        ForEach(Nudge.allCases, id: \.self) { (nudge: Nudge) in
            Button(nudge.actionName) { apply(nudge, to: corner) }
        }
    }

    // MARK: - Controls

    enum Nudge: String, CaseIterable {
        case left, right, up, down

        var actionName: String {
            switch self {
            case .left: "Move left"
            case .right: "Move right"
            case .up: "Move up"
            case .down: "Move down"
            }
        }

        var symbol: String { "arrow." + rawValue }

        var delta: (Double, Double) {
            let step: Double = CornerPin.nudgeStep
            switch self {
            case .left: return (-step, 0)
            case .right: return (step, 0)
            case .up: return (0, -step)
            case .down: return (0, step)
            }
        }
    }

    private func apply(_ nudge: Nudge, to corner: CornerPin.Corner) {
        let d: (Double, Double) = nudge.delta
        setting.cornerPin = setting.cornerPin.nudging(corner, dx: d.0, dy: d.1)
    }

    private var controls: some View {
        Form {
            Section {
                cornerPicker
                nudgeRow
                Button("Reset", role: .destructive) { setting.cornerPin = .identity }
                    .accessibilityIdentifier("cornerPinReset")
            } footer: {
                Text(ExternalOutputSetting.cornerPinFooter)
            }
        }
        .frame(maxHeight: 320)
    }

    private var cornerPicker: some View {
        Picker("Corner", selection: $selected) {
            ForEach(CornerPin.Corner.allCases, id: \.self) { (corner: CornerPin.Corner) in
                Text(ExternalOutputSetting.title(corner)).tag(corner)
            }
        }
        .accessibilityIdentifier("cornerPinCornerPicker")
    }

    private var nudgeRow: some View {
        HStack(spacing: 12) {
            ForEach(Nudge.allCases, id: \.self) { (nudge: Nudge) in
                Button { apply(nudge, to: selected) } label: {
                    Image(systemName: nudge.symbol)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(nudge.actionName)
                .accessibilityIdentifier("cornerPinNudge." + nudge.rawValue)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
