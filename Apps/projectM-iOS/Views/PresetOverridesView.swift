// PresetOverridesView.swift — PRE-016 "Adjust Parameters…" sheet (spec PRE-016-R12 to R15; contract C4).
//
// One row per allowed parameter: its name, the current value, the preset's original value, a slider
// (ACC-005 `.accessibleParameter`) and, when adjusted, a per-row restore. "Reset to Original" removes
// every adjustment. The value follows the finger; the adjustment is stored (and the preset on screen
// reloaded) once, when the drag ends or after one VoiceOver step (spec Clarifications).
// Bodies are split into small typed functions for CI's type-check budget.
import PresetLibrary
import SwiftUI

/// Presents the sheet from a preset row (kept out of the row's `body` for the type-check budget).
struct PresetOverridesSheet: ViewModifier {
    @Binding var isPresented: Bool
    let presets: PresetCoordinator
    let preset: IndexedPreset

    /// R12: playable, unlocked presets only (a locked one asks for the purchase instead).
    @MainActor static func canAdjust(_ preset: IndexedPreset, presets: PresetCoordinator) -> Bool {
        presets.overrides != nil && !presets.isLocked(preset) && presets.isPlayable(preset)
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            if let overrides = presets.overrides { PresetOverridesView(overrides: overrides, preset: preset) }
        }
    }
}

struct PresetOverridesView: View {
    let overrides: PresetOverridesCoordinator
    let preset: IndexedPreset
    @Environment(\.dismiss) private var dismiss
    /// Nil until read; the engine defaults stand in when the bytes cannot be read.
    @State private var originals: [PresetOverrideParameter: Double]?
    /// Values under the finger, not yet stored.
    @State private var drafts: [PresetOverrideParameter: Double] = [:]

    var body: some View {
        NavigationStack {
            Form {
                noteSection
                resetSection   // on screen without scrolling, above the eight rows
                Section { parameterRows }
            }
            .navigationTitle(preset.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneButton }
        }
        .accessibilityIdentifier("presetOverrides")
        .task { originals = await overrides.originals(for: preset) }
    }

    // MARK: - Sections

    private var noteSection: some View {
        Section {
            Text(PresetOverridesCoordinator.note).font(.footnote)
            if let unavailable = overrides.unavailableText { Text(unavailable).font(.footnote) }
            if let message = overrides.message {
                Text(message).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("presetOverridesMessage")
            }
        }
    }

    @ViewBuilder private var parameterRows: some View {
        ForEach(PresetOverrideParameter.allCases, id: \.self) { (parameter: PresetOverrideParameter) in
            row(parameter)
        }
    }

    private var resetSection: some View {
        let adjusted: Bool = overrides.hasOverrides(preset)
        return Section {
            Button(role: .destructive) {
                drafts = [:]
                Task { await overrides.resetAll(preset) }
            } label: {
                Text("Reset to Original")
            }
            .disabled(!adjusted)
            .accessibilityIdentifier("presetOverridesResetAll")
        }
    }

    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }.accessibilityIdentifier("presetOverridesDone")
        }
    }

    // MARK: - Rows

    private func original(_ parameter: PresetOverrideParameter) -> Double {
        originals?[parameter] ?? parameter.engineDefault
    }

    private func stored(_ parameter: PresetOverrideParameter) -> Double? {
        overrides.overrides(for: preset)[parameter.key]
    }

    private func current(_ parameter: PresetOverrideParameter) -> Double {
        drafts[parameter] ?? stored(parameter) ?? original(parameter)
    }

    private func row(_ parameter: PresetOverrideParameter) -> some View {
        let shown: String = PresetTextOverlay.valueText(current(parameter))
        let originalText: String = "Original " + PresetTextOverlay.valueText(original(parameter))
        let adjusted: Bool = stored(parameter) != nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(parameter.label).accessibilityHidden(true)   // the slider reads the name and value
                Spacer()
                Text(shown).monospacedDigit().accessibilityIdentifier("presetOverrideValue.\(parameter.key)")
            }
            Text(originalText).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("presetOverrideOriginal.\(parameter.key)")
            slider(parameter)
            if adjusted { restoreButton(parameter) }
        }
    }

    private func spec(_ parameter: PresetOverrideParameter) -> AccessibleParameterSpec {
        let decimals: Int = parameter.step < 0.01 ? 3 : 2
        return AccessibleParameterSpec(id: "presetOverride.\(parameter.key)", label: parameter.label, range: parameter.range,
                                       step: parameter.step, unit: .number(decimals: decimals))
    }

    private func slider(_ parameter: PresetOverrideParameter) -> some View {
        let range: ClosedRange<Double> = parameter.range
        let target = ParameterTarget(get: { () -> Double in min(max(current(parameter), range.lowerBound), range.upperBound) },
                                     set: { (value: Double) -> Void in drafts[parameter] = value })
        let value = Binding<Double>(get: { () -> Double in target.get() }, set: { (d: Double) -> Void in target.set(d) })
        let finish: @MainActor () -> Void = { () -> Void in commit(parameter) }
        return Slider(value: value, in: range) { (editing: Bool) in
            if !editing { finish() }   // one drag is one stored change
        }
        .disabled(overrides.unavailableText != nil)
        .accessibleParameter(spec(parameter), target: target, didStep: finish)
    }

    private func restoreButton(_ parameter: PresetOverrideParameter) -> some View {
        Button("Restore " + parameter.label) {
            drafts[parameter] = nil
            Task { await overrides.reset(parameter, preset: preset) }
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .accessibilityIdentifier("presetOverrideReset.\(parameter.key)")
    }

    private func commit(_ parameter: PresetOverrideParameter) {
        guard let value = drafts[parameter] else { return }
        Task { @MainActor in
            await overrides.set(value, for: parameter, preset: preset)
            if drafts[parameter] == value { drafts[parameter] = nil }
        }
    }
}
