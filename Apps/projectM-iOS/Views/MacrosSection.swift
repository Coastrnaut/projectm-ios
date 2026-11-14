// MacrosSection.swift — MOD-010: Settings › Macros (MOD-010-R10; research MOD-010-D5; contract M5).
//
// Shown only when the current scene has a usable macro. Per macro: an ACC-005 slider (`macro.<index>`, labelled with
// the macro's name, spoken as a percent, 1% steps) that sets the macro through `MacroCoordinator` (the Settings write
// path), and under it each target's name and current value, read-only (`macroTarget.<index>.<parameter ID>`). A drag,
// or one accessibility step, is one undo step (SCN-010). There is no editor: macros come from scenes.
import ParameterGraph
import SwiftUI

struct MacrosSection: View {
    let macros: MacroCoordinator
    let settings: AppSettings
    /// Ends one undo step (the drag ended or one step was taken).
    let endCoalescing: @MainActor () -> Void

    static let footer = "A macro moves several settings at once, each along its own curve. Macros come with the scene."

    var body: some View {
        Section {
            ForEach(macros.live, id: \.index) { (item: (index: Int, macro: ParameterMacro)) in
                MacroRow(index: item.index, macro: item.macro, macros: macros, settings: settings, endCoalescing: endCoalescing)
            }
        } header: {
            Text("Macros")
        } footer: {
            Text(Self.footer)
        }
    }
}

private struct MacroRow: View {
    let index: Int
    let macro: ParameterMacro
    let macros: MacroCoordinator
    let settings: AppSettings
    let endCoalescing: @MainActor () -> Void

    private var spec: AccessibleParameterSpec {
        AccessibleParameterSpec(id: "macro.\(index)", label: macro.name, range: 0...1, step: 0.01, unit: .percent(decimals: 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption
            slider
            targetRows
        }
    }

    private var caption: some View {
        let percent: String = ParameterValueText.display(macro.normalizedValue, unit: .normalized, step: 0.01)
        return HStack {
            Text(macro.name)
            Spacer(minLength: 8)
            Text(percent).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)   // the slider reads the name and value
    }

    private var slider: some View {
        let index: Int = index
        let macros: MacroCoordinator = macros
        let numeric = ParameterTarget(get: { () -> Double in macros.macros[index]?.normalizedValue ?? 0 },
                                      set: { (d: Double) -> Void in macros.setValue(d, at: index) })
        let value = Binding<Double>(get: { () -> Double in numeric.get() },
                                    set: { (d: Double) -> Void in numeric.set(d) })
        let finish: @MainActor () -> Void = endCoalescing
        return Slider(value: value, in: 0...1) { (editing: Bool) in
            if !editing { finish() }   // a drag is one undo step
        }
        .accessibleParameter(spec, target: numeric, didStep: finish)
    }

    @ViewBuilder private var targetRows: some View {
        ForEach(macro.targets, id: \.parameter) { (target: MacroTarget) in
            MacroTargetRow(index: index, parameter: target.parameter, settings: settings)
        }
    }
}

/// "Intensity: 10%", read-only.
private struct MacroTargetRow: View {
    let index: Int
    let parameter: ParameterID
    let settings: AppSettings

    private var text: String {
        guard let descriptor = ParameterInspectorCatalog.descriptor(parameter) else { return parameter.rawValue }
        guard let target = ParameterInspectorTargets.target(for: parameter, settings: settings) else {
            return descriptor.displayName + ": " + MacroCoordinator.unavailableValue
        }
        let value: String = ParameterValueText.display(target.get(), descriptor: descriptor)
        return descriptor.group.displayName + " " + descriptor.displayName + ": " + value
    }

    var body: some View {
        let text: String = text
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityLabel(text)
            .accessibilityIdentifier("macroTarget.\(index).\(parameter.rawValue)")
    }
}
