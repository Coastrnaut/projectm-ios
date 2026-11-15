// GridWarpEditorView.swift — OUT-008-T10 (spec specs/309-out-008-grid-warp, contract C4; research OUT-008-D9): the
// full-screen grid-warp editor opened from Settings › External Display › Grid warp…, built like the corner-pin editor.
//
// * The canvas shows the display's shape (dashed), the warped grid (the surface sampled along every control row and
//   column) and one handle per control point (44 pt targets). A drag moves its point to the finger; `GridWarp` clamps
//   it to the allowed range and refuses a mesh that would fold, so the last valid mesh stays (OUT-008-R4) and the
//   reason is shown in red and announced once through the accessibility announcer.
// * VoiceOver: each handle is one element ("Row 2, column 3", value "52 % across, 47.5 % down") with four named actions
//   (Move left, right, up, down; one nudge step each). Below the canvas: the grid size (3 × 3, 5 × 5, 9 × 9; the
//   surface is resampled, else the identity), row and column steppers choosing a point, four nudge buttons, and Reset.
// * Open: the coordinator's editing flag is on, so a connected display draws guide lines along the grid through the
//   warp; Done or dismissal turns it off.
import PresentationLifecycle
import SwiftUI

struct GridWarpEditorView: View {
    @Bindable var setting: ExternalOutputSetting
    /// The display's shape (width ÷ height).
    let aspect: Double
    let onDone: () -> Void

    @State private var row = 0
    @State private var column = 0
    @State private var reason = ""
    @State private var announcer = AccessibilityAnnouncer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas
                probe
                controls
            }
            .navigationTitle(ExternalOutputSetting.gridWarpEditorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneItem }
        }
        .onAppear { setting.external?.beginGridWarpEditing() }
        .onDisappear { setting.external?.endGridWarpEditing() }
    }

    private var doneItem: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: onDone)
                .accessibilityIdentifier("gridWarpDone")
        }
    }

    /// DEBUG (UI tests): the stored mesh and the coordinator's `gridWarpSummary`.
    @ViewBuilder private var probe: some View {
        #if DEBUG
        let editing: Bool = setting.external?.isEditingGridWarp == true   // observed: re-renders when the guides change
        let summary: String = setting.external?.gridWarpSummary ?? "none"
        let text: String = setting.gridWarp.stored + "|" + summary + (editing ? "|editing" : "|idle")
        Text(text)
            .font(.caption2)
            .frame(height: 1)
            .opacity(0.01)
            .accessibilityIdentifier("gridWarpProbe")
            .accessibilityValue(text)
        #endif
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { (proxy: GeometryProxy) in
            let frame: CGRect = CornerPinEditorView.worldFrame(in: proxy.size, aspect: aspect)
            ZStack(alignment: .topLeading) {
                outlines(frame)
                handles(frame)
            }
            .coordinateSpace(name: "gridWarpCanvas")
        }
        .background(Color(white: 0.12))
        .frame(maxWidth: .infinity)
        .frame(minHeight: 240)
        .clipped()
    }

    static func canvasPoint(_ p: GridWarpPoint, in frame: CGRect) -> CGPoint {
        CornerPinEditorView.canvasPoint(CornerPinPoint(x: p.x, y: p.y), in: frame)
    }

    static func picturePoint(_ c: CGPoint, in frame: CGRect) -> GridWarpPoint {
        let p: CornerPinPoint = CornerPinEditorView.outputPoint(c, in: frame)
        return GridWarpPoint(x: p.x, y: p.y)
    }

    private func outlines(_ frame: CGRect) -> some View {
        let display: [CornerPinPoint] = CornerPin.identity.corners
        let lines: Path = Self.gridPath(setting.gridWarp, frame)
        return ZStack {
            CornerPinEditorView.path(display, frame).stroke(Color.gray, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            lines.stroke(Color.teal, lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }

    /// The surface along every control row and column, 8 samples per cell.
    static func gridPath(_ warp: GridWarp, _ frame: CGRect) -> Path {
        var path = Path()
        let steps: Int = 8
        let across: Int = (warp.columns - 1) * steps, down: Int = (warp.rows - 1) * steps
        for r in 0..<warp.rows {
            let v: Double = Double(r) / Double(warp.rows - 1)
            let points: [CGPoint] = (0...across).map { (k: Int) -> CGPoint in
                canvasPoint(warp.map(u: Double(k) / Double(across), v: v), in: frame)
            }
            path.addLines(points)
        }
        for c in 0..<warp.columns {
            let u: Double = Double(c) / Double(warp.columns - 1)
            let points: [CGPoint] = (0...down).map { (k: Int) -> CGPoint in
                canvasPoint(warp.map(u: u, v: Double(k) / Double(down)), in: frame)
            }
            path.addLines(points)
        }
        return path
    }

    private func handles(_ frame: CGRect) -> some View {
        let warp: GridWarp = setting.gridWarp
        let indices: [Int] = Array(0..<(warp.columns * warp.rows))
        return ForEach(indices, id: \.self) { (index: Int) in
            handle(row: index / warp.columns, column: index % warp.columns, frame: frame)
        }
    }

    private func handle(row r: Int, column c: Int, frame: CGRect) -> some View {
        let point: GridWarpPoint = setting.gridWarp.point(row: r, column: c)
        let label: String = ExternalOutputSetting.gridPointTitle(row: r, column: c)
        let value: String = ExternalOutputSetting.spokenValue(point)
        let identifier: String = "gridWarpHandle." + String(r) + "." + String(c)
        return dot(selected: r == row && c == column)
            .position(Self.canvasPoint(point, in: frame))
            .gesture(drag(row: r, column: c, frame: frame))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
            .accessibilityActions { moveActions(row: r, column: c) }
    }

    private func dot(selected: Bool) -> some View {
        Circle()
            .fill(selected ? Color.yellow : Color.white)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(Color.black, lineWidth: 2))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func drag(row r: Int, column c: Int, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("gridWarpCanvas"))
            .onChanged { (value: DragGesture.Value) -> Void in
                row = r
                column = c
                apply(setting.gridWarp.moving(row: r, column: c, to: Self.picturePoint(value.location, in: frame)))
            }
    }

    @ViewBuilder private func moveActions(row r: Int, column c: Int) -> some View {
        ForEach(CornerPinEditorView.Nudge.allCases, id: \.self) { (nudge: CornerPinEditorView.Nudge) in
            Button(nudge.actionName) { self.nudge(nudge, row: r, column: c) }
        }
    }

    // MARK: - Edits

    private func nudge(_ nudge: CornerPinEditorView.Nudge, row r: Int, column c: Int) {
        let d: (Double, Double) = nudge.delta   // the corner pin's step: 0.005 = GridWarp.nudgeStep
        apply(setting.gridWarp.nudging(row: r, column: c, dx: d.0, dy: d.1))
    }

    /// OUT-008-R4: an applied edit replaces the mesh; a refused one keeps it and says why (announced once per reason).
    private func apply(_ edit: GridWarpEdit) {
        switch edit {
        case .applied(let warp):
            setting.gridWarp = warp
            reason = ""
        case .refused(let validity):
            let text: String = ExternalOutputSetting.reason(validity)
            if text != reason { announcer.announce(text, kind: .display) }
            reason = text
        }
    }

    private func resize(_ side: Int) {
        guard side != setting.gridWarp.columns || side != setting.gridWarp.rows else { return }
        setting.gridWarp = setting.gridWarp.resampled(columns: side, rows: side)
        row = min(row, side - 1)
        column = min(column, side - 1)
        reason = ""
    }

    // MARK: - Controls

    private var controls: some View {
        Form {
            Section {
                sizePicker
                pointSteppers
                nudgeRow
                reasonRow
                Button("Reset", role: .destructive) { resetAll() }
                    .accessibilityIdentifier("gridWarpReset")
            } footer: {
                Text(ExternalOutputSetting.gridWarpFooter)
            }
        }
        .frame(maxHeight: 360)
    }

    private func resetAll() {
        setting.gridWarp = .identity(columns: setting.gridWarp.columns, rows: setting.gridWarp.rows)
        reason = ""
    }

    /// The offered sizes, plus a stored square size that is not one of them (a non-square one shows as its own tag 0).
    private var sizes: [Int] {
        let warp: GridWarp = setting.gridWarp
        var list: [Int] = GridWarp.editorSizes
        if warp.columns == warp.rows, !list.contains(warp.columns) { list.append(warp.columns) }
        return list.sorted()
    }

    private var sizeBinding: Binding<Int> {
        Binding<Int>(get: { () -> Int in
            setting.gridWarp.columns == setting.gridWarp.rows ? setting.gridWarp.columns : 0
        }, set: { (side: Int) -> Void in
            if side > 0 { resize(side) }
        })
    }

    private var sizePicker: some View {
        Picker("Grid", selection: sizeBinding) {
            ForEach(sizes, id: \.self) { (side: Int) in
                Text(ExternalOutputSetting.title(gridSize: side)).tag(side)
            }
            if setting.gridWarp.columns != setting.gridWarp.rows {
                Text(String(setting.gridWarp.columns) + " × " + String(setting.gridWarp.rows)).tag(0)
            }
        }
        .accessibilityIdentifier("gridWarpSize")
    }

    private var pointSteppers: some View {
        let rows: Int = setting.gridWarp.rows, columns: Int = setting.gridWarp.columns
        return Group {
            Stepper("Row " + String(min(row, rows - 1) + 1), value: $row, in: 0...(rows - 1))
                .accessibilityIdentifier("gridWarpRow")
            Stepper("Column " + String(min(column, columns - 1) + 1), value: $column, in: 0...(columns - 1))
                .accessibilityIdentifier("gridWarpColumn")
        }
    }

    private var nudgeRow: some View {
        HStack(spacing: 12) {
            ForEach(CornerPinEditorView.Nudge.allCases, id: \.self) { (nudge: CornerPinEditorView.Nudge) in
                Button { self.nudge(nudge, row: row, column: column) } label: {
                    Image(systemName: nudge.symbol)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(nudge.actionName)
                .accessibilityIdentifier("gridWarpNudge." + nudge.rawValue)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var reasonRow: some View {
        if !reason.isEmpty {
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier("gridWarpReason")
        }
    }
}
