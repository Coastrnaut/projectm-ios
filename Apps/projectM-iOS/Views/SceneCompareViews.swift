// SceneCompareViews.swift — SCN-009: the A/B compare's views (specs/222-scn-009-scene-ab-compare; R1, R7, R8;
// contract C5).
//
// * `SceneCompareRow`: "Compare A/B…" under the Snapshots rows in Settings › Visual; opens the setup sheet.
// * `SceneCompareSetupSheet`: pick A (Current scene or a snapshot) and B (a snapshot), then Start Compare.
// * `SceneCompareBar`: "Comparing A/B" in the visualizer's top status stack, with or without the controls: two large
//   A and B buttons (the shown one prominent and selected) and Done, which turns the row into "Finish Compare?":
//   Keep A, Keep B, Cancel Compare (Back returns). In place, not an alert, so it never hides the output. No animation:
//   a switch is a cut.
import SwiftUI

/// A usable snapshot the sheet offers.
struct SceneCompareOption: Hashable, Identifiable {
    let choice: SceneCompareChoice
    let name: String
    var id: SceneCompareChoice { choice }
}

struct SceneCompareRow: View {
    let compare: SceneCompareCoordinator
    let snapshots: SceneSnapshotCoordinator
    @State private var choosing = false

    private var usable: [SceneCompareOption] {
        snapshots.rows.filter { (r: SceneSnapshotRow) -> Bool in r.isUsable }
            .map { (r: SceneSnapshotRow) -> SceneCompareOption in SceneCompareOption(choice: .snapshot(r.index), name: r.name) }
    }

    var body: some View {
        Button { choosing = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Compare A/B…")
                Text(usable.isEmpty ? "Save a snapshot first." : "Switch the output between two states. Nothing is saved until you keep one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(usable.isEmpty || compare.isActive)
        .accessibilityLabel("Compare A/B")
        .accessibilityHint(usable.isEmpty ? "Save a snapshot first." : "Chooses two states to switch between.")
        .accessibilityIdentifier("sceneCompareOpen")
        .sheet(isPresented: $choosing) {
            SceneCompareSetupSheet(compare: compare, options: usable)
        }
    }
}

struct SceneCompareSetupSheet: View {
    let compare: SceneCompareCoordinator
    let options: [SceneCompareOption]
    @State private var a: SceneCompareChoice = .current
    @State private var b: Int = 0
    @Environment(\.dismiss) private var dismiss

    private var bChoices: [(index: Int, name: String)] {
        options.compactMap { (o: SceneCompareOption) -> (index: Int, name: String)? in
            if case let .snapshot(index) = o.choice { return (index, o.name) }
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                pickers
                Section {
                    Button("Start Compare", action: start)
                        .disabled(a == .snapshot(b))
                        .accessibilityIdentifier("sceneCompareStart")
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Compare A/B")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear(perform: chooseDefaults)
        }
    }

    @ViewBuilder private var pickers: some View {
        Section {
            Picker("A", selection: $a) {
                Text(SceneCompareCoordinator.currentName).tag(SceneCompareChoice.current)
                ForEach(options) { (o: SceneCompareOption) in Text(o.name).tag(o.choice) }
            }
            .accessibilityIdentifier("sceneCompareA")
            Picker("B", selection: $b) {
                ForEach(bChoices, id: \.index) { (c: (index: Int, name: String)) in Text(c.name).tag(c.index) }
            }
            .accessibilityIdentifier("sceneCompareB")
        }
    }

    private var footer: String {
        if a == .snapshot(b) { return SceneCompareCoordinator.sameStateRefusal }
        return compare.status.flatMap { (s: String) -> String? in s.hasPrefix(SceneCompareCoordinator.title) ? nil : s }
            ?? "The output switches at once. The scene is saved only when you keep A or B."
    }

    /// Two snapshots: the first two; one: the current scene against it.
    private func chooseDefaults() {
        let indices: [Int] = bChoices.map { (c: (index: Int, name: String)) -> Int in c.index }
        if indices.count >= 2 {
            a = .snapshot(indices[0])
            b = indices[1]
        } else if let first = indices.first {
            a = .current
            b = first
        }
    }

    private func start() {
        if compare.start(a: a, b: b) == nil { dismiss() }
    }
}

struct SceneCompareBar: View {
    let compare: SceneCompareCoordinator

    var body: some View {
        if let session = compare.session {
            VStack(spacing: 8) {
                header(session)
                HStack(spacing: 8) {   // Done sits in the row, below the status-bar area (taps there go to the system)
                    if compare.isConfirmingFinish { finishRow(session) } else { sideRow(session) }
                    doneButton
                }
            }
            .padding(10)
            .frame(maxWidth: 420)
            .statusBadgeBackground(RoundedRectangle(cornerRadius: 14))   // ACC-003-R9
        }
    }

    private func header(_ session: SceneCompareSession) -> some View {
        HStack {
            Label(SceneCompareCoordinator.title, systemImage: "rectangle.split.2x1")
                .font(.footnote.weight(.semibold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SceneCompareCoordinator.title)
                .accessibilityValue(session.spoken(session.shown))
                .accessibilityIdentifier("sceneCompareBar")
            Spacer(minLength: 0)
        }
    }

    /// Done opens the finish row in place (Back returns to the switch).
    private var doneButton: some View {
        let finishing: Bool = compare.isConfirmingFinish
        return Button(finishing ? "Back" : "Done") { compare.isConfirmingFinish = !finishing }
            .font(.callout.weight(.semibold))
            .frame(minHeight: 44)
            .buttonStyle(.bordered)
            .accessibilityHint(finishing ? "Returns to the A and B switch." : "Keep A, keep B or cancel Compare.")
            .accessibilityIdentifier("sceneCompareDone")
    }

    @ViewBuilder private func sideRow(_ session: SceneCompareSession) -> some View {
        sideButton(.a, session: session)
        sideButton(.b, session: session)
    }

    @ViewBuilder private func sideButton(_ side: SceneCompareSide, session: SceneCompareSession) -> some View {
        let label: String = side.rawValue + "  " + session.name(side)
        let shown: Bool = session.shown == side
        let button = Button { compare.show(side) } label: {
            Text(label)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(session.spoken(side))
        .accessibilityAddTraits(shown ? .isSelected : [])
        .accessibilityHint(shown ? "Shown now." : "Shows this state at once.")
        .accessibilityIdentifier(side == .a ? "sceneCompareSideA" : "sceneCompareSideB")
        if shown { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }

    /// "Finish Compare?": Keep A, Keep B (each saves the scene once) or Cancel Compare (restores the scene as it was).
    @ViewBuilder private func finishRow(_ session: SceneCompareSession) -> some View {
        finishButton("Keep A", id: "sceneCompareKeepA", label: "Keep A, " + session.aName) { compare.keep(.a) }
        finishButton("Keep B", id: "sceneCompareKeepB", label: "Keep B, " + session.bName) { compare.keep(.b) }
        finishButton("Cancel", id: "sceneCompareCancel", label: "Cancel Compare, return to the scene as it was") { compare.cancel() }
    }

    private func finishButton(_ title: String, id: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
        .accessibilityHint("Finishes Compare.")
        .accessibilityIdentifier(id)
    }
}
