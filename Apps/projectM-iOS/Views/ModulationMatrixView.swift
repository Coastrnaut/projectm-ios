// ModulationMatrixView.swift — MOD-012: Settings › Modulation (MOD-012-R1, R2, R6, R10; contract modulation-matrix M5).
//
// One section per destination (first-appearance order), its layers in fold order. Each layer: an on/off switch
// (`modulationRouteEnabled.<target>.<layer>`) and a link to its detail (`modulationRoute.<target>.<layer>`), with
// the VoiceOver actions "Move Up" and "Move Down"; Edit mode drags layers within their section. Threshold triggers
// and macros are listed read-only. No create or delete: routes come with scenes. Bodies stay small (type-check budget).
import ParameterGraph
import SwiftUI

/// The Settings row that opens the matrix.
struct ModulationMatrixLinkSection: View {
    let coordinator: AppCoordinator

    var body: some View {
        Section {
            NavigationLink {
                ModulationMatrixView(coordinator: coordinator)
            } label: {
                label
            }
            .accessibilityIdentifier("modulationLink")
        } footer: {
            Text("What audio and LFOs drive, per setting: turn routes on or off, reorder and inspect them.")
        }
    }

    private var label: some View {
        let matrix: ModulationMatrixCoordinator = coordinator.modulationMatrix
        let value: String = matrix.countText
        let count: Text = Text(verbatim: value)
        let title: Text = Text("Modulation")
        return LabeledContent { count } label: { title }
    }
}

struct ModulationMatrixView: View {
    let coordinator: AppCoordinator

    static let emptyText = "No routes. Routes come with scenes: open a scene that modulates a setting to see them here."
    static let footer = "Layers apply top to bottom, each kept in range, then the sensory safety limit. A route turned off is kept in the scene but not applied."

    private var matrix: ModulationMatrixCoordinator { coordinator.modulationMatrix }

    var body: some View {
        List {
            probeSection
            if matrix.routes.isEmpty { emptySection } else { groupSections }
            ModulationReadOnlySections(coordinator: coordinator)
        }
        .navigationTitle("Modulation")
        .toolbar { editToolbar }
        .accessibilityIdentifier("modulationMatrix")
    }

    @ToolbarContentBuilder private var editToolbar: some ToolbarContent {
        if !matrix.routes.isEmpty { ToolbarItem(placement: .primaryAction) { EditButton() } }
    }

    private var emptySection: some View {
        Section { Text(Self.emptyText).foregroundStyle(.secondary) }
    }

    private var groupSections: some View {
        ForEach(matrix.groups, id: \.target) { (group: ModulationRouteGroup) in
            ModulationGroupSection(group: group, coordinator: coordinator, isLast: group.target == matrix.groups.last?.target,
                                   footer: Self.footer)
        }
    }

    @ViewBuilder private var probeSection: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(UITestModulationMatrixFixture.argument) {
            Section("Probe") { ModulationProbeRow(coordinator: coordinator) }
        }
        #endif
    }
}

private struct ModulationGroupSection: View {
    let group: ModulationRouteGroup
    let coordinator: AppCoordinator
    let isLast: Bool
    let footer: String

    var body: some View {
        Section {
            ForEach(Array(group.layers.enumerated()), id: \.offset) { (item: (offset: Int, element: AudioFeatureBinding)) in
                ModulationRouteRow(binding: item.element, layer: item.offset, count: group.layers.count, coordinator: coordinator)
            }
            .onMove { (from: IndexSet, to: Int) in
                coordinator.modulationMatrix.move(target: group.target, fromOffsets: from, toOffset: to)
            }
        } header: {
            Text(ModulationRouteText.destinationName(group.target))
        } footer: {
            if isLast { Text(footer) }
        }
    }
}

private struct ModulationRouteRow: View {
    let binding: AudioFeatureBinding
    let layer: Int
    let count: Int
    let coordinator: AppCoordinator

    private var key: String { binding.target.rawValue + "." + String(layer) }
    private var title: String { "\(layer + 1). " + ModulationRouteText.routeTitle(binding) }

    var body: some View {
        HStack(spacing: 12) {
            enabledSwitch
            link
        }
        .accessibilityActions { moveActions }
    }

    private var enabledSwitch: some View {
        let matrix: ModulationMatrixCoordinator = coordinator.modulationMatrix
        let target: ParameterID = binding.target
        let layer: Int = layer
        let isOn = Binding<Bool>(get: { () -> Bool in binding.isEnabled },
                                 set: { (on: Bool) -> Void in matrix.setEnabled(on, target: target, layer: layer) })
        return Toggle(title, isOn: isOn)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("modulationRouteEnabled." + key)
    }

    private var link: some View {
        NavigationLink {
            ModulationRouteDetailView(binding: binding, layer: layer, coordinator: coordinator)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(ModulationRouteText.summary(binding)).font(.caption).foregroundStyle(.secondary)
            }
            .opacity(binding.isEnabled ? 1 : 0.5)
        }
        .accessibilityIdentifier("modulationRoute." + key)
        .accessibilityValue(binding.isEnabled ? "On" : "Off")
    }

    @ViewBuilder private var moveActions: some View {
        let matrix: ModulationMatrixCoordinator = coordinator.modulationMatrix
        let target: ParameterID = binding.target
        let layer: Int = layer
        if layer > 0 {
            Button("Move Up") { matrix.move(target: target, from: layer, to: layer - 1) }
        }
        if layer < count - 1 {
            Button("Move Down") { matrix.move(target: target, from: layer, to: layer + 1) }
        }
    }
}

/// MOD-012-R2: threshold triggers and macros, read-only.
private struct ModulationReadOnlySections: View {
    let coordinator: AppCoordinator

    private var triggers: [ThresholdTriggerBinding] {
        coordinator.nativeVisual?.triggers ?? coordinator.sceneAutosave?.triggerBindings ?? []
    }

    var body: some View {
        if !triggers.isEmpty {
            Section("Triggers (from the scene)") {
                ForEach(Array(triggers.enumerated()), id: \.offset) { (item: (offset: Int, element: ThresholdTriggerBinding)) in
                    Text(Self.triggerText(item.element))
                }
            }
        }
        if !coordinator.macros.isEmpty {
            Section("Macros (from the scene)") {
                ForEach(coordinator.macros.live, id: \.index) { (item: (index: Int, macro: ParameterMacro)) in
                    Text(Self.macroText(item.macro))
                }
            }
        }
    }

    static func triggerText(_ trigger: ThresholdTriggerBinding) -> String {
        let level: String = String(format: "above %.0f%%", trigger.settings.high * 100)
        return trigger.source.inspectorName + " " + level + " → " + trigger.action.rawValue
    }

    static func macroText(_ macro: ParameterMacro) -> String {
        let names: [String] = macro.targets.map { (t: MacroTarget) -> String in ModulationRouteText.destinationName(t.parameter) }
        return macro.name + " → " + names.joined(separator: ", ")
    }
}

#if DEBUG
/// DEBUG (ModulationMatrixUITests): "<target>=<value>" per destination, modulated before the sensory safety clamp.
private struct ModulationProbeRow: View {
    let coordinator: AppCoordinator

    var body: some View {
        let routes: [AudioFeatureBinding] = coordinator.modulationMatrix.routes   // observed: refreshes on every edit
        let values: [(target: ParameterID, value: Double)] = routes.isEmpty ? [] : coordinator.modulationProbeValues()
        let parts: [String] = values.map { (v: (target: ParameterID, value: Double)) -> String in
            v.target.rawValue + "=" + String(format: "%.4f", v.value)
        }
        let text: String = parts.joined(separator: " ")
        Text(text)
            .font(.caption.monospaced())
            .accessibilityIdentifier("modulationProbe")
            .accessibilityLabel(text)
    }
}
#endif
