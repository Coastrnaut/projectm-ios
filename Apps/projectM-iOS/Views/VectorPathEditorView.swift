// VectorPathEditorView.swift — SHD-008-T06 (specs/279-shd-008-vector-path-editor, contract P5; research SHD-008-D6,
// D8): the closed-path editor opened from the layer inspector's mask section and the particle emitter's spawn section.
//
// * The canvas shows the unit square (dashed) and the path. While drawing, a tap adds a point; every point is a
//   draggable 44 pt handle. Edits go through `VectorPathDraft`: once the path is closed, an edit that would make it
//   invalid (crossing itself, too small, too few points) is refused and the last valid path stays (SHD-008-R3).
// * VoiceOver: each point is one element ("Point 2", value "25 % across, 40 % down") with Move left/right/up/down
//   and Delete point actions; "Add point" adds one at the centre for people who cannot tap a spot. A nudge row moves
//   the selected point for everyone. The inline message (`vectorPathMessage`) shows why an edit was refused or why
//   the drawing cannot close yet; refusals are also announced through the parameter announcer lane (SHD-008-R4).
// * Each newly committed valid path is handed to `onCommit` (the mask or the emitter stores it at once).
// Parameters only: a path is numbers (SHD-011). Bodies stay small (Xcode 26 type-check budget).
import SwiftUI
import VisualGenerators

struct VectorPathEditorView: View {
    let title: String
    let onCommit: (VectorPath) -> Void

    @State private var draft: VectorPathDraft
    @Environment(\.parameterAnnouncer) private var announcer

    init(title: String, path: VectorPath, onCommit: @escaping (VectorPath) -> Void) {
        self.title = title
        self.onCommit = onCommit
        _draft = State(initialValue: VectorPathDraft(path: path))
    }

    var body: some View {
        VStack(spacing: 0) {
            canvas
            controls
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft.committed) { (_: VectorPath?, path: VectorPath?) -> Void in
            if let path { onCommit(path) }
        }
        .onChange(of: draft.refusal) { (_: String?, text: String?) -> Void in
            if let text { announcer?.announce(text, kind: .parameter) }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { (proxy: GeometryProxy) in
            let frame: CGRect = Self.square(in: proxy.size)
            ZStack(alignment: .topLeading) {
                tapSurface(frame)
                outline(frame)
                ForEach(Array(draft.points.indices), id: \.self) { (index: Int) in
                    handle(index, frame: frame)
                }
            }
            .coordinateSpace(name: "vectorPathCanvas")
        }
        .background(Color(white: 0.12))
        .frame(maxWidth: .infinity)
        .frame(minHeight: 260)
        .clipped()
    }

    /// The largest centred square inside `size`, inset by 22 pt so edge handles stay reachable.
    static func square(in size: CGSize) -> CGRect {
        let inset: CGFloat = 22
        let side: CGFloat = max(min(size.width, size.height) - inset * 2, 1)
        return CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    }

    static func canvasPoint(_ p: VectorPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + CGFloat(p.x) * frame.width, y: frame.minY + CGFloat(p.y) * frame.height)
    }

    static func unitPoint(_ c: CGPoint, in frame: CGRect) -> VectorPoint {
        let x: Double = Double((c.x - frame.minX) / max(frame.width, 1))
        let y: Double = Double((c.y - frame.minY) / max(frame.height, 1))
        return VectorPoint(x: x, y: y)
    }

    private func tapSurface(_ frame: CGRect) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.001))
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(coordinateSpace: .named("vectorPathCanvas")).onEnded { (value: SpatialTapGesture.Value) -> Void in
                guard !draft.isClosed else { return }
                draft.add(Self.unitPoint(value.location, in: frame))
            })
            .accessibilityElement()
            .accessibilityLabel("Path canvas")
            .accessibilityValue(draft.isClosed ? "Closed" : "Drawing, \(draft.points.count) points")
            .accessibilityIdentifier("vectorPathCanvas")
    }

    private func outline(_ frame: CGRect) -> some View {
        let mapped: [CGPoint] = draft.points.map { (p: VectorPoint) -> CGPoint in Self.canvasPoint(p, in: frame) }
        let invalid: Bool = !draft.isClosed && draft.closeIssue != nil
        let stroke: Color = invalid ? Color.orange : Color.teal
        return ZStack {
            Path(frame).stroke(Color.gray, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            Self.polygon(mapped, closed: draft.isClosed).fill(draft.isClosed ? Color.teal.opacity(0.25) : Color.clear)
            Self.polygon(mapped, closed: draft.isClosed || !invalid).stroke(stroke, lineWidth: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func polygon(_ points: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        path.addLines(points)
        if closed { path.closeSubpath() }
        return path
    }

    private func handle(_ index: Int, frame: CGRect) -> some View {
        let point: VectorPoint = draft.points[index]
        let isSelected: Bool = draft.selected == index
        return Circle()
            .fill(isSelected ? Color.yellow : Color.white)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Color.black, lineWidth: 2))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(Self.canvasPoint(point, in: frame))
            .gesture(drag(index, frame: frame))
            .accessibilityElement()
            .accessibilityLabel("Point \(index + 1)")
            .accessibilityValue(Self.spokenValue(point))
            .accessibilityIdentifier("vectorPathPoint.\(index + 1)")
            .accessibilityActions { pointActions(index) }
    }

    static func spokenValue(_ p: VectorPoint) -> String {
        let across: Int = Int((p.x * 100).rounded())
        let down: Int = Int((p.y * 100).rounded())
        return "\(across) % across, \(down) % down"
    }

    private func drag(_ index: Int, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("vectorPathCanvas"))
            .onChanged { (value: DragGesture.Value) -> Void in
                draft.selected = index
                draft.move(index, to: Self.unitPoint(value.location, in: frame))
            }
    }

    @ViewBuilder private func pointActions(_ index: Int) -> some View {
        ForEach(PathNudge.allCases, id: \.self) { (nudge: PathNudge) in
            Button(nudge.actionName) { apply(nudge, to: index) }
        }
        Button("Delete point") { draft.delete(index) }
    }

    private func apply(_ nudge: PathNudge, to index: Int) {
        let d: (Double, Double) = nudge.delta
        draft.selected = index
        draft.nudge(index, dx: d.0, dy: d.1)
    }

    // MARK: - Controls

    private var controls: some View {
        Form {
            Section {
                message
                editButtons
                nudgeRow
            } footer: {
                Text("Tap the canvas to add points, then Close path. A path that crosses itself cannot be closed.")
            }
        }
        .frame(maxHeight: 360)
    }

    private var message: some View {
        Text(draft.status)
            .foregroundStyle(draft.refusal != nil || (!draft.isClosed && draft.closeIssue != nil) ? Color.orange : Color.secondary)
            .accessibilityIdentifier("vectorPathMessage")
    }

    @ViewBuilder private var editButtons: some View {
        if draft.isClosed {
            Button("Start over") { draft.startOver() }
                .accessibilityIdentifier("vectorPathStartOver")
        } else {
            drawingButtons
        }
        Button("Delete point", role: .destructive) { deleteSelected() }
            .disabled(draft.selected == nil)
            .accessibilityIdentifier("vectorPathDelete")
    }

    @ViewBuilder private var drawingButtons: some View {
        Button("Close path") { draft.close() }
            .disabled(!draft.canClose)
            .accessibilityIdentifier("vectorPathClose")
        Button("Add point at centre") { draft.add(VectorPoint(x: 0.5, y: 0.5)) }
            .accessibilityIdentifier("vectorPathAdd")
        Button("Undo last point") { draft.removeLast() }
            .disabled(draft.points.isEmpty)
            .accessibilityIdentifier("vectorPathUndoPoint")
    }

    private func deleteSelected() {
        guard let index = draft.selected else { return }
        draft.delete(index)
    }

    private var nudgeRow: some View {
        HStack(spacing: 12) {
            ForEach(PathNudge.allCases, id: \.self) { (nudge: PathNudge) in
                Button { if let index = draft.selected { apply(nudge, to: index) } } label: {
                    Image(systemName: nudge.symbol)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(draft.selected == nil)
                .accessibilityLabel(nudge.actionName)
                .accessibilityIdentifier("vectorPathNudge." + nudge.rawValue)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// One nudge step in each direction (VectorPathDraft.nudgeStep).
enum PathNudge: String, CaseIterable {
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
        let step: Double = VectorPathDraft.nudgeStep
        switch self {
        case .left: return (-step, 0)
        case .right: return (step, 0)
        case .up: return (0, -step)
        case .down: return (0, step)
        }
    }
}
