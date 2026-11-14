// CueTransitionView.swift — Settings → Show → a cue's Transition sheet (SCN-007-R9).
//
// A Form with three controls: the type (Default, Cut, Crossfade, Dip to Black; an unknown stored type is
// listed as itself), the duration (0…10 s in 0.1 s steps, ACC-005 `.accessibleParameter`) and the easing
// (Linear, Ease In, Ease Out, Ease In-Out; Custom only when the stored curve is another MOD-004 curve).
// "Default" removes the transition (the scene appears at once). Duration and easing are disabled for
// Default and Cut. Every change saves the show at once and applies nothing. Navigation-link pickers keep
// each choice on its own full-width row, so the sheet reads well at the largest accessibility sizes.
import ParameterGraph
import ShowControl
import SwiftUI

struct CueTransitionView: View {
    let show: ShowCoordinator
    let cueID: UUID
    let dismiss: () -> Void
    @State private var duration: Double = ShowCueTransition.defaultCrossfade.durationSeconds

    static let durationSpec = AccessibleParameterSpec(id: "cueTransitionDurationSlider", label: "Duration",
                                                      range: 0...ShowCueTransition.maximumSeconds, step: 0.1, unit: .seconds)
    static let defaultTag = "default"

    private var cue: ShowCue? { show.list.cues.first { (c: ShowCue) -> Bool in c.id == cueID } }
    private var transition: ShowCueTransition? { cue?.transition }
    /// Duration and easing apply only to a known, non-cut type.
    private var shapesTransition: Bool {
        guard let type = transition?.type else { return false }
        return type != .cut
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    typePicker
                    durationRow
                    easingPicker
                } header: {
                    Text(cue?.label ?? "Cue")
                } footer: {
                    Text("Default and Cut show the scene at once. Reduce Motion makes every transition a cut; Reduce flashing spreads a cut or a short transition over half a second.")
                }
            }
            .navigationTitle("Transition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("cueTransitionDone")
                }
            }
        }
        .onAppear { duration = transition?.durationSeconds ?? ShowCueTransition.defaultCrossfade.durationSeconds }
        .accessibilityIdentifier("cueTransitionSheet")
    }

    // MARK: Type

    private var typeTags: [(tag: String, title: String)] {
        var tags: [(tag: String, title: String)] = [(Self.defaultTag, "Default")]
        for type in ShowTransitionType.known { tags.append((type.text, type.displayName)) }
        if let type = transition?.type, !type.isKnown { tags.append((type.text, type.displayName)) }
        return tags
    }

    private var typeBinding: Binding<String> {
        Binding<String>(get: { () -> String in transition?.type.text ?? Self.defaultTag },
                        set: { (tag: String) in setType(tag) })
    }

    private var typePicker: some View {
        Picker("Type", selection: typeBinding) {
            ForEach(typeTags, id: \.tag) { (item: (tag: String, title: String)) in
                Text(item.title).tag(item.tag)
            }
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier("cueTransitionType")
    }

    private func setType(_ tag: String) {
        guard tag != Self.defaultTag else {
            show.setTransition(cueID, to: nil)
            return
        }
        guard let type = ShowTransitionType(text: tag) else { return }
        let base: ShowCueTransition = transition ?? ShowCueTransition.defaultCrossfade
        if let updated = try? base.with(type: type) { show.setTransition(cueID, to: updated) }
    }

    // MARK: Duration

    private var durationTarget: ParameterTarget {
        ParameterTarget(get: { () -> Double in duration }, set: { (value: Double) in commitDuration(value) })
    }

    private var durationRow: some View {
        let readout: String = CueTransitionResolver.durationText(duration) + " s"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Duration")
                Spacer()
                Text(readout).monospacedDigit().foregroundStyle(.secondary).accessibilityIdentifier("cueTransitionDurationValue")
            }
            .accessibilityElement(children: .contain)
            Slider(value: $duration, in: Self.durationSpec.range,
                   onEditingChanged: { (editing: Bool) in if !editing { commitDuration(duration) } })
                .accessibleParameter(Self.durationSpec, target: durationTarget)
        }
        .disabled(!shapesTransition)
    }

    /// Snaps to the 0.1 s grid (so 1.5 is stored as 1.5, not 1.5000000000000002) and saves.
    private func commitDuration(_ value: Double) {
        let tenths: Double = (value * 10).rounded()
        let snapped: Double = min(max(tenths / 10, 0), ShowCueTransition.maximumSeconds)
        duration = snapped
        guard let transition, transition.durationSeconds != snapped,
              let updated = try? transition.with(durationSeconds: snapped) else { return }
        show.setTransition(cueID, to: updated)
    }

    // MARK: Easing

    private var easingPresets: [CueEasingPreset] {
        let stored: CueEasingPreset = transition.map { (t: ShowCueTransition) -> CueEasingPreset in CueEasingPreset(t.easing) } ?? .linear
        return CueEasingPreset.allCases.filter { (preset: CueEasingPreset) -> Bool in preset != .custom || stored == .custom }
    }

    private var easingBinding: Binding<CueEasingPreset> {
        Binding<CueEasingPreset>(get: { () -> CueEasingPreset in transition.map { (t: ShowCueTransition) -> CueEasingPreset in CueEasingPreset(t.easing) } ?? .linear },
                                 set: { (preset: CueEasingPreset) in setEasing(preset) })
    }

    private var easingPicker: some View {
        Picker("Easing", selection: easingBinding) {
            ForEach(easingPresets) { (preset: CueEasingPreset) in
                Text(easingTitle(preset)).tag(preset)
            }
        }
        .pickerStyle(.navigationLink)
        .disabled(!shapesTransition)
        .accessibilityIdentifier("cueTransitionEasing")
    }

    private func easingTitle(_ preset: CueEasingPreset) -> String {
        guard preset == .custom, let curve = transition?.easing else { return preset.title }
        return preset.displayName(curve)
    }

    private func setEasing(_ preset: CueEasingPreset) {
        guard let curve = preset.curve, let transition, let updated = try? transition.with(easing: curve) else { return }
        show.setTransition(cueID, to: updated)
    }
}
