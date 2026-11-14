// ParameterInspectorView.swift — the context parameter inspector (UIX-003-R1 to R10; contracts/parameter-
// inspector.md P1-P3).
//
// * `.parameterInspectorEntry(_:open:)`: a context menu item "Inspect" and a VoiceOver action of the same
//   name on a Settings control that edits a registry parameter (research UIX-003-D4).
// * `.parameterInspectorSheet(...)`: the sheet over Settings; in DEBUG, `-uitestInspectParameter <id>` opens
//   it once when Settings appears (R10).
// * The sheet: About (name, ID, group), Details (unit, range, step, default), Value (the kind's edit control
//   and Reset; none for a read-only parameter) and Modulation (polled at 10 Hz by a TimelineView only while
//   a reader is set; a Gauge only when Reduce Motion is off). Rows stack at large text sizes (ACC-006) and
//   each row is one VoiceOver element with a spoken value and unit (R9). No animation.
import ParameterGraph
import SwiftUI

// MARK: - Entry (R1)

private struct ParameterInspectorEntryModifier: ViewModifier {
    let id: ParameterID?
    let menu: Bool
    let action: Bool
    let open: (ParameterID) -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if let id, menu, action {
            content.contextMenu { inspectButton(id) }.accessibilityAction(named: "Inspect") { open(id) }
        } else if let id, menu {
            content.contextMenu { inspectButton(id) }
        } else if let id, action {
            content.accessibilityAction(named: "Inspect") { open(id) }
        } else {
            content
        }
    }

    private func inspectButton(_ id: ParameterID) -> some View {
        Button("Inspect", systemImage: "info.circle") { open(id) }
            .accessibilityIdentifier("inspect." + id.rawValue)
    }
}

extension View {
    /// UIX-003-R1: "Inspect" (context menu and VoiceOver action) opens the inspector for `id`; nil adds nothing.
    /// A slider row puts the menu on the whole row (`action: false`) and the action on its slider element
    /// (`menu: false`), whose children ACC-005 hides from VoiceOver.
    func parameterInspectorEntry(_ id: ParameterID?, menu: Bool = true, action: Bool = true,
                                 open: @escaping (ParameterID) -> Void) -> some View {
        modifier(ParameterInspectorEntryModifier(id: id, menu: menu, action: action, open: open))
    }

    /// UIX-003: the inspector sheet for `item` over `settings`.
    func parameterInspectorSheet(_ item: Binding<InspectedParameter?>, settings: AppSettings, history: SceneHistoryCoordinator?,
                                 announcer: AccessibilityAnnouncer?,
                                 reading: (@MainActor (ParameterID) -> ParameterModulationReading?)?) -> some View {
        modifier(ParameterInspectorSheetModifier(item: item, settings: settings, history: history, announcer: announcer, reading: reading))
    }
}

private struct ParameterInspectorSheetModifier: ViewModifier {
    @Binding var item: InspectedParameter?
    let settings: AppSettings
    let history: SceneHistoryCoordinator?
    let announcer: AccessibilityAnnouncer?
    let reading: (@MainActor (ParameterID) -> ParameterModulationReading?)?
    @State private var launchRequestHandled = false

    func body(content: Content) -> some View {
        content
            .sheet(item: $item) { (selected: InspectedParameter) in sheet(selected) }
            .onAppear { openLaunchRequest() }
    }

    @ViewBuilder private func sheet(_ selected: InspectedParameter) -> some View {
        if let descriptor = ParameterInspectorCatalog.descriptor(selected.id) {
            let target: ParameterInspectorTarget? = ParameterInspectorTargets.target(for: selected.id, settings: settings)
            ParameterInspectorView(descriptor: descriptor, target: target, reader: reader(for: selected.id),
                                   endCoalescing: { [history] () -> Void in history?.endCoalescing() },
                                   announce: { [announcer] (text: String) -> Void in announcer?.announce(text, kind: .parameter) })
        }
    }

    /// The live reading bound to `id`, or nil without a source.
    private func reader(for id: ParameterID) -> (@MainActor () -> ParameterModulationReading?)? {
        guard let read = reading else { return nil }
        let bound: @MainActor () -> ParameterModulationReading? = { () -> ParameterModulationReading? in read(id) }
        return bound
    }

    private func openLaunchRequest() {
        #if DEBUG
        guard !launchRequestHandled else { return }
        launchRequestHandled = true
        if item == nil, let requested = UITestParameterInspector.requested { item = requested }
        #endif
    }
}

// MARK: - Sheet (R2-R9)

struct ParameterInspectorView: View {
    let descriptor: ParameterDescriptor
    /// Nil: read-only (no edit control, no Reset; R6).
    let target: ParameterInspectorTarget?
    /// Nil: no live source (previews, no native visual): "Not modulated".
    let reader: (@MainActor () -> ParameterModulationReading?)?
    let endCoalescing: @MainActor () -> Void
    let announce: @MainActor (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var summary: ParameterInspectorSummary { ParameterInspectorSummary(descriptor) }

    var body: some View {
        NavigationStack {
            List {
                aboutSection
                detailsSection
                valueSection
                ParameterModulationSection(descriptor: descriptor, reader: reader)
            }
            .navigationTitle(descriptor.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("parameterInspector.done")
                }
            }
            .accessibilityIdentifier("parameterInspector")
        }
    }

    private var aboutSection: some View {
        Section("Parameter") {
            ParameterInspectorRow(title: "Name", value: summary.name, id: "parameterInspector.name")
            ParameterInspectorRow(title: "ID", value: summary.id.rawValue, id: "parameterInspector.id")
            ParameterInspectorRow(title: "Group", value: summary.group, id: "parameterInspector.group")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            ParameterInspectorRow(title: "Unit", value: summary.unit, id: "parameterInspector.unit")
            ParameterInspectorRow(title: "Range", value: summary.range, spoken: summary.spokenRange, id: "parameterInspector.range")
            if let step = summary.step {
                ParameterInspectorRow(title: "Step", value: step, spoken: summary.spokenStep, id: "parameterInspector.step")
            }
            ParameterInspectorRow(title: "Default", value: summary.defaultText, spoken: summary.spokenDefault, id: "parameterInspector.default")
        }
    }

    @ViewBuilder private var valueSection: some View {
        Section {
            if let target {
                let current: ParameterValue = target.get()
                ParameterInspectorRow(title: "Value", value: ParameterValueText.display(current, descriptor: descriptor),
                                      spoken: ParameterValueText.spoken(current, descriptor: descriptor), id: "parameterInspector.value")
                ParameterInspectorEditor(descriptor: descriptor, target: target, endCoalescing: endCoalescing)
                Button("Reset to Default") { reset(target) }
                    .accessibilityHint("Sets " + descriptor.displayName + " to " + summary.spokenDefault)
                    .accessibilityIdentifier("parameterInspector.reset")
            } else {
                Text("This setting has no control in this version, so it can't be changed or reset here.")
                    .accessibilityIdentifier("parameterInspector.readOnly")
            }
        } header: {
            Text("Value")
        }
    }

    private func reset(_ target: ParameterInspectorTarget) {
        let text: String = ParameterInspectorReset.reset(descriptor, target: target, endCoalescing: endCoalescing)
        announce(text)   // UIX-003-R5: the parameter lane
    }
}

/// One label and value; side by side, or stacked when they do not fit (ACC-006-R1). One VoiceOver element.
private struct ParameterInspectorRow: View {
    let title: String
    let value: String
    var spoken: String?
    let id: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 8)
                Text(value).monospacedDigit().foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken ?? value)
        .accessibilityIdentifier(id)
    }
}

/// The edit control of the parameter's kind, writing through the target (R3).
private struct ParameterInspectorEditor: View {
    let descriptor: ParameterDescriptor
    let target: ParameterInspectorTarget
    let endCoalescing: @MainActor () -> Void

    @ViewBuilder var body: some View {
        if let choices = choicesList {
            choicePicker(choices)
        } else if case .boolean = descriptor.kind {
            Toggle(descriptor.displayName, isOn: boolBinding)
                .accessibilityIdentifier("parameterInspector.toggle")
        } else if let bounds = descriptor.kind.numericBounds {
            slider(bounds)
        }
    }

    private var choicesList: [ParameterValue]? {
        if let choices = target.choices { return choices }
        let cases: [ParameterEnumCase] = descriptor.kind.enumCases
        return cases.isEmpty ? nil : cases.map { (c: ParameterEnumCase) -> ParameterValue in .enumeration(c.id) }
    }

    private func choicePicker(_ choices: [ParameterValue]) -> some View {
        let selection = Binding<ParameterValue>(get: { () -> ParameterValue in target.get() },
                                                set: { (v: ParameterValue) -> Void in
                                                    target.set(v)
                                                    endCoalescing()
                                                })
        return Picker(descriptor.displayName, selection: selection) {
            ForEach(choices, id: \.self) { (choice: ParameterValue) in
                Text(ParameterValueText.display(choice, descriptor: descriptor)).tag(choice)
            }
        }
        .accessibilityIdentifier("parameterInspector.picker")
    }

    private var boolBinding: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in target.get().boolValue ?? false },
                      set: { (b: Bool) -> Void in
                          target.set(.boolean(b))
                          endCoalescing()
                      })
    }

    private func slider(_ bounds: ClosedRange<Double>) -> some View {
        let spec: AccessibleParameterSpec = sliderSpec(bounds)
        let numeric = ParameterTarget(get: { () -> Double in target.get().numericValue ?? bounds.lowerBound },
                                      set: { (d: Double) -> Void in target.set(.continuous(d)) })
        let value = Binding<Double>(get: { () -> Double in numeric.get() }, set: { (d: Double) -> Void in numeric.set(d) })
        return Slider(value: value, in: bounds) { (editing: Bool) in
            if !editing { endCoalescing() }   // a drag is one undo step (SCN-010-R4)
        }
        .accessibleParameter(spec, target: numeric, didStep: endCoalescing)
    }

    private func sliderSpec(_ bounds: ClosedRange<Double>) -> AccessibleParameterSpec {
        let span: Double = bounds.upperBound - bounds.lowerBound
        let hint: Double = descriptor.kind.stepHint ?? span / 100
        let step: Double = ParameterStepper.tidy(max(hint, span / 100))
        let unit: SpokenUnit = ParameterValueText.spokenUnit(descriptor.unit, step: descriptor.kind.stepHint)
        return AccessibleParameterSpec(id: "parameterInspector.slider", label: descriptor.displayName, range: bounds,
                                       step: step, unit: unit)
    }
}

/// R7, R8: what drives the parameter; polled at 10 Hz only while a reader is set and the sheet is open.
private struct ParameterModulationSection: View {
    let descriptor: ParameterDescriptor
    let reader: (@MainActor () -> ParameterModulationReading?)?

    var body: some View {
        Section {
            if let reader {
                TimelineView(.periodic(from: .now, by: ParameterInspectorTiming.refreshSeconds)) { (_: TimelineViewDefaultContext) in
                    ParameterModulationRows(descriptor: descriptor, reading: reader())
                }
            } else {
                ParameterModulationRows(descriptor: descriptor, reading: nil)
            }
        } header: {
            Text("Modulation")
        } footer: {
            Text("Audio bindings and MIDI controls change the value the visual uses; Reset changes only your own value.")
        }
    }
}

private struct ParameterModulationRows: View {
    let descriptor: ParameterDescriptor
    let reading: ParameterModulationReading?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder var body: some View {
        if let reading {
            let text: String = ParameterValueText.display(reading.effective, unit: descriptor.unit, step: descriptor.kind.stepHint)
            let spoken: String = ParameterValueText.spoken(reading.effective, unit: descriptor.unit, step: descriptor.kind.stepHint)
            let suffix: String = reading.limitedBySafety ? ", limited by Sensory safety" : ""
            ParameterInspectorRow(title: "Effective value", value: text + suffix, spoken: spoken + suffix, id: "parameterInspector.modulation")
            if !reduceMotion, let bounds = descriptor.kind.numericBounds {
                Gauge(value: min(max(reading.effective, bounds.lowerBound), bounds.upperBound), in: bounds) { EmptyView() }
                    .accessibilityHidden(true)   // the row above reads the value
            }
            ForEach(Array(reading.sources.enumerated()), id: \.offset) { (entry: (offset: Int, element: String)) in
                Text(entry.element)
                    .accessibilityLabel("Source, " + entry.element)
                    .accessibilityIdentifier("parameterInspector.source.\(entry.offset)")
            }
        } else {
            Text("Not modulated")
                .accessibilityIdentifier("parameterInspector.modulation")
        }
    }
}
