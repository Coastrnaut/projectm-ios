// CueRehearsalPanel.swift — SHOW-006 the device-only rehearsal panel (specs/237-show-006-cue-rehearsal; R1-R3, R5,
// R6, R8, R10; contract C2-C6).
//
// * Shown in the visualizer's status stack (the device window's SwiftUI layer) while rehearsal is on, with or without
//   the controls (R10). Never on the external display, in a recording or in Save Frame: those read the visual's own
//   Metal output (UIX-013-R8, R9).
// * Title ("Rehearsal · Cue 3 · Drop"), the 16:9 picture (VoiceOver "Preview of cue 3, Drop"), arrows that pick the
//   rehearsed cue without moving the show, Edit (the sandbox draft: glow and spectrum values), Save to Cue, Revert and
//   Close. `.task(id:)` reloads when the show moves the resolved cue.
import ShowControl
import SwiftUI
import VisualEffects
import VisualGenerators

struct CueRehearsalPanel: View {
    let rehearsal: CueRehearsalCoordinator
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            picture
            if editing, rehearsal.draft != nil { CueRehearsalEditor(rehearsal: rehearsal) }
            if let message = rehearsal.saveMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("cueRehearsalSaveMessage")
            }
        }
        .padding(8)
        .frame(maxWidth: 240, alignment: .leading)
        .overlaySurface(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cueRehearsalPanel")
        .task(id: rehearsal.resolvedCueID) { () -> Void in rehearsal.sync() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button { rehearsal.previousTarget() } label: { Image(systemName: "chevron.backward") }
                .accessibilityLabel("Rehearse previous cue")
                .accessibilityIdentifier("cueRehearsalPrevious")
            VStack(alignment: .leading, spacing: 0) {
                Text("Rehearsal").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(rehearsal.titleText)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("cueRehearsalTitle")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rehearsal, " + rehearsal.titleText.replacingOccurrences(of: " · ", with: ", "))
            Spacer(minLength: 4)
            Button { rehearsal.nextTarget() } label: { Image(systemName: "chevron.forward") }
                .accessibilityLabel("Rehearse next cue in list")
                .accessibilityIdentifier("cueRehearsalNext")
            if rehearsal.draft != nil {
                Button { editing.toggle() } label: { Image(systemName: editing ? "slider.horizontal.below.square.filled.and.square" : "slider.horizontal.3") }
                    .accessibilityLabel("Edit rehearsed cue")
                    .accessibilityValue(editing ? "Open" : "Closed")
                    .accessibilityIdentifier("cueRehearsalEdit")
            }
            Button { rehearsal.close() } label: { Image(systemName: "xmark.circle.fill") }
                .accessibilityLabel("Close rehearsal")
                .accessibilityIdentifier("cueRehearsalClose")
        }
        .font(.body)
    }

    @ViewBuilder private var picture: some View {
        let spoken: String = "Preview of " + rehearsal.titleText.replacingOccurrences(of: " · ", with: ", ").lowercasedFirst
        ZStack(alignment: .bottomLeading) {
            Color.black
            pictureContent
            if let note = note {
                Text(note).font(.caption2).padding(3).background(.black.opacity(0.6)).foregroundStyle(.white)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityValue(note ?? "")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("cueRehearsalPicture")
    }

    @ViewBuilder private var pictureContent: some View {
        switch rehearsal.picture {
        case let .rendered(image):
            Image(decorative: image, scale: 1).resizable().scaledToFit()
        case let .stored(image):
            Image(uiImage: image).resizable().scaledToFit()
        case let .message(text):
            Text(text).font(.caption).foregroundStyle(.white.opacity(0.8)).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// "Stored picture" (and the edits note) for cues the renderer does not draw.
    private var note: String? {
        guard case .stored = rehearsal.picture, let draft = rehearsal.draft else { return nil }
        return draft.isEdited ? CueRehearsalCoordinator.editsShowLaterNote : CueRehearsalCoordinator.storedNote
    }
}

/// The sandbox editor (R5, R6): changes only the draft; Save to Cue writes the cue's scene file.
private struct CueRehearsalEditor: View {
    let rehearsal: CueRehearsalCoordinator

    private static func spec(_ base: AccessibleParameterSpec, id: String) -> AccessibleParameterSpec {
        AccessibleParameterSpec(id: id, label: "Glow " + base.label.lowercased(), range: base.range, step: base.step, unit: base.unit)
    }

    private static let intensity = spec(AccessibleParameterCatalog.glowIntensity, id: "cueRehearsalGlowIntensity")
    private static let radius = spec(AccessibleParameterCatalog.glowRadius, id: "cueRehearsalGlowRadius")
    private static let threshold = spec(AccessibleParameterCatalog.glowThreshold, id: "cueRehearsalGlowThreshold")

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            glowToggle
            if rehearsal.draft?.values.glow.enabled == true {
                slider(Self.intensity, \.intensity)
                slider(Self.radius, \.radius)
                slider(Self.threshold, \.threshold)
            }
            barsPicker
            actions
        }
        .font(.caption)
    }

    private var glowToggle: some View {
        let binding = Binding<Bool>(get: { () -> Bool in rehearsal.draft?.values.glow.enabled ?? false },
                                    set: { (on: Bool) -> Void in rehearsal.editDraft { (v: inout SnapshotRenderValues) in v.glow.enabled = on } })
        return Toggle("Glow", isOn: binding).accessibilityIdentifier("cueRehearsalGlow")
    }

    private func target(_ key: WritableKeyPath<BloomParameters, Float>) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in Double(rehearsal.draft?.values.glow[keyPath: key] ?? 0) },
                        set: { (value: Double) -> Void in rehearsal.editDraft { (v: inout SnapshotRenderValues) in v.glow[keyPath: key] = Float(value) } })
    }

    private func slider(_ spec: AccessibleParameterSpec, _ key: WritableKeyPath<BloomParameters, Float>) -> some View {
        let target: ParameterTarget = target(key)
        let value = Binding<Double>(get: { () -> Double in target.get() }, set: { (v: Double) -> Void in target.set(v) })
        return VStack(alignment: .leading, spacing: 0) {
            Text(spec.label).foregroundStyle(.secondary).accessibilityHidden(true)
            Slider(value: value, in: spec.range).accessibleParameter(spec, target: target)
        }
    }

    private var barsPicker: some View {
        let binding = Binding<SpectrumBarCount>(get: { () -> SpectrumBarCount in rehearsal.draft?.values.barCount ?? .b64 },
                                                set: { (bars: SpectrumBarCount) -> Void in
                                                    rehearsal.editDraft { (v: inout SnapshotRenderValues) in v.barCount = bars }
                                                })
        return Picker("Bars", selection: binding) {
            ForEach(SpectrumBarCount.allCases, id: \.self) { (bars: SpectrumBarCount) in Text(String(bars.rawValue)).tag(bars) }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Bars")
        .accessibilityIdentifier("cueRehearsalBars")
    }

    private var actions: some View {
        let edited: Bool = rehearsal.draft?.isEdited ?? false
        return HStack {
            Button("Revert") { rehearsal.revert() }
                .disabled(!edited)
                .accessibilityIdentifier("cueRehearsalRevert")
            Spacer()
            Button("Save to Cue") { rehearsal.saveDraft() }
                .buttonStyle(.borderedProminent)
                .disabled(!edited)
                .accessibilityHint("Saves these values in the cue's scene. The live output does not change.")
                .accessibilityIdentifier("cueRehearsalSave")
        }
    }
}

private extension String {
    /// "Cue 3, Drop" → "cue 3, Drop"; "End of show" → "end of show".
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
