// ParameterShelfView.swift — UIX-004: the favorite parameter shelf (UIX-004-R1, R3, R4, R6, R8, R9;
// specs/151-uix-004-parameter-shelf, contracts/parameter-shelf.md P1-P3).
//
// * `\.parameterShelf`: the shelf in the environment (set on Settings), so UIX-003's Inspect menu and sheet can
//   offer Pin to Shelf / Remove from Shelf (research UIX-004-D4).
// * `ParameterShelfPinButton`: that button; at the limit it is disabled and reads "Shelf Full (8)".
// * `ParameterShelfStrip`: the strip inside the visualizer's controls (research D5): pins in order, a horizontal
//   scroll at standard sizes, stacked at accessibility sizes (ACC-006; the controls scroll there), and the
//   missing-pins note with Remove. Nothing is drawn while the shelf is empty.
// * `ParameterShelfControl`: a compact control built from the registry descriptor (slider with ACC-005's
//   `.accessibleParameter`, toggle, or menu picker), writing through UIX-003's target (the Settings path).
// * `ParameterShelfSection`: Settings › Parameter Shelf: order (Edit, drag, delete; VoiceOver Move up, Move down,
//   Remove from Shelf), the note and the limit. No animation is added anywhere.
import ParameterGraph
import SwiftUI

extension EnvironmentValues {
    /// UIX-004: the shelf behind Pin to Shelf (nil: no shelf, e.g. previews).
    @Entry var parameterShelf: ParameterShelf? = nil
}

// MARK: - Pin button (P1)

struct ParameterShelfPinButton: View {
    let shelf: ParameterShelf
    let id: ParameterID
    /// Nil: `shelfPin.<id>` / `shelfUnpin.<id>` (the context menu).
    var identifier: String?

    var body: some View {
        let pinned: Bool = shelf.isPinned(id)
        let full: Bool = !pinned && !shelf.canPin
        let title: String = pinned ? "Remove from Shelf" : (full ? ParameterShelf.fullTitle : "Pin to Shelf")
        let icon: String = pinned ? "pin.slash" : "pin"
        let defaultID: String = (pinned ? "shelfUnpin." : "shelfPin.") + id.rawValue
        Button(title, systemImage: icon) { shelf.toggle(id) }
            .disabled(full)
            .accessibilityIdentifier(identifier ?? defaultID)
    }
}

extension ParameterShelf {
    /// The VoiceOver action's name for `id`, or nil when it cannot be pinned (read-only, or the shelf is full).
    func actionTitle(_ id: ParameterID) -> String? {
        if isPinned(id) { return "Remove from Shelf" }
        guard ParameterShelf.isPinnable(id), canPin else { return nil }
        return "Pin to Shelf"
    }
}

// MARK: - Overlay strip (P2)

struct ParameterShelfStrip: View {
    let shelf: ParameterShelf
    let settings: AppSettings
    /// Ends one undo step (a drag, a swipe or a choice; SCN-010-R4).
    let endCoalescing: @MainActor () -> Void
    /// Restarts the controls' auto-hide.
    let touched: @MainActor () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if !shelf.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                controls
                if let note = shelf.missingNote { missingNote(note) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("parameterShelf")
            Divider()
        }
    }

    @ViewBuilder private var controls: some View {
        let pins: [ParameterID] = shelf.pinned
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) { row(pins) }
        } else if !pins.isEmpty {
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 14) { row(pins) }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row(_ pins: [ParameterID]) -> some View {
        ForEach(pins, id: \.self) { (id: ParameterID) in
            ParameterShelfControl(id: id, settings: settings, endCoalescing: endCoalescing, touched: touched)
        }
    }

    private func missingNote(_ note: String) -> some View {
        HStack(spacing: 8) {
            Text(note)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shelf.missingNote")
            Spacer(minLength: 4)
            Button("Remove") {
                touched()
                shelf.removeMissing()
            }
            .font(.caption)
            .accessibilityLabel("Remove unavailable pins")
            .accessibilityIdentifier("shelf.removeMissing")
        }
    }
}

/// One pinned control, from the registry descriptor; nothing for an ID that is no longer editable.
struct ParameterShelfControl: View {
    let id: ParameterID
    let settings: AppSettings
    let endCoalescing: @MainActor () -> Void
    let touched: @MainActor () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The control's width at standard sizes (scaled with the text).
    @ScaledMetric(relativeTo: .caption) private var width: CGFloat = 170

    private var identifier: String { "shelf." + id.rawValue }

    var body: some View {
        if let descriptor = ParameterInspectorCatalog.descriptor(id),
           let target = ParameterInspectorTargets.quantizedTarget(for: id, settings: settings) {   // MOD-017
            VStack(alignment: .leading, spacing: 2) {
                control(descriptor, target)
                QueuedChangeLabel(quantizer: settings.parameterQuantizer, id: id)   // MOD-017-R9
            }
            .frame(width: typeSize.isAccessibilitySize ? nil : width, alignment: .leading)
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
        }
    }

    @ViewBuilder private func control(_ descriptor: ParameterDescriptor, _ target: ParameterInspectorTarget) -> some View {
        if let choices = ParameterShelfControlSpec.choices(descriptor, target: target) {
            picker(descriptor, target, choices)
        } else if case .boolean = descriptor.kind {
            toggle(descriptor, target)
        } else if let bounds = descriptor.kind.numericBounds {
            slider(descriptor, target, bounds)
        }
    }

    private func edited() {
        endCoalescing()
        touched()
    }

    private func caption(_ descriptor: ParameterDescriptor, _ target: ParameterInspectorTarget) -> some View {
        let value: String = ParameterValueText.display(target.get(), descriptor: descriptor)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Text(descriptor.displayName).lineLimit(1)
                Spacer(minLength: 4)
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.displayName)
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .accessibilityHidden(true)   // the control reads the name and value
    }

    private func slider(_ descriptor: ParameterDescriptor, _ target: ParameterInspectorTarget,
                        _ bounds: ClosedRange<Double>) -> some View {
        let spec: AccessibleParameterSpec = ParameterShelfControlSpec.slider(descriptor, bounds: bounds, id: identifier)
        let numeric = ParameterTarget(get: { () -> Double in target.get().numericValue ?? bounds.lowerBound },
                                      set: { (d: Double) -> Void in target.set(.continuous(d)) })
        let value = Binding<Double>(get: { () -> Double in numeric.get() },
                                    set: { (d: Double) -> Void in
                                        numeric.set(d)
                                        touched()
                                    })
        let finish: @MainActor () -> Void = { () -> Void in edited() }
        return VStack(alignment: .leading, spacing: 2) {
            caption(descriptor, target)
            Slider(value: value, in: bounds) { (editing: Bool) in
                if !editing { finish() }   // a drag is one undo step
            }
            .accessibleParameter(spec, target: numeric, didStep: finish)
        }
    }

    private func toggle(_ descriptor: ParameterDescriptor, _ target: ParameterInspectorTarget) -> some View {
        let isOn = Binding<Bool>(get: { () -> Bool in target.get().boolValue ?? false },
                                 set: { (b: Bool) -> Void in
                                     target.set(.boolean(b))
                                     edited()
                                 })
        return Toggle(descriptor.displayName, isOn: isOn)
            .font(.caption)
            .accessibilityIdentifier(identifier)
    }

    private func picker(_ descriptor: ParameterDescriptor, _ target: ParameterInspectorTarget,
                        _ choices: [ParameterValue]) -> some View {
        let selection = Binding<ParameterValue>(get: { () -> ParameterValue in target.get() },
                                                set: { (v: ParameterValue) -> Void in
                                                    target.set(v)
                                                    edited()
                                                })
        return VStack(alignment: .leading, spacing: 2) {
            Text(descriptor.displayName).font(.caption).accessibilityHidden(true)
            Picker(descriptor.displayName, selection: selection) {
                ForEach(choices, id: \.self) { (choice: ParameterValue) in
                    Text(ParameterValueText.display(choice, descriptor: descriptor)).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(identifier)
        }
    }
}

// MARK: - Settings section (P3)

struct ParameterShelfSection: View {
    let shelf: ParameterShelf

    var body: some View {
        Section {
            if shelf.pinned.isEmpty {
                Text("No pinned controls. Long press a Glow, Bars, Orientation or Spacing control and choose Pin to Shelf.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("shelf.empty")
            }
            ForEach(shelf.pinned, id: \.self) { (id: ParameterID) in row(id) }
                .onMove { (source: IndexSet, destination: Int) in shelf.move(fromOffsets: source, toOffset: destination) }
                .onDelete { (offsets: IndexSet) in shelf.remove(atOffsets: offsets) }
            if let note = shelf.missingNote {
                HStack {
                    Text(note).accessibilityIdentifier("shelfSettings.missingNote")
                    Spacer(minLength: 8)
                    Button("Remove") { shelf.removeMissing() }
                        .accessibilityLabel("Remove unavailable pins")
                        .accessibilityIdentifier("shelfSettings.removeMissing")
                }
            }
        } header: {
            HStack {
                Text("Parameter Shelf")
                Spacer()
                if shelf.pinned.count > 1 { EditButton().accessibilityIdentifier("shelf.edit") }
            }
        } footer: {
            Text(ParameterShelf.footer)
        }
        .id("parameterShelf")
    }

    private func row(_ id: ParameterID) -> some View {
        let name: String = ParameterInspectorCatalog.descriptor(id)?.displayName ?? id.rawValue
        return Text(name)
            .accessibilityIdentifier("shelfRow." + id.rawValue)
            .accessibilityAction(named: "Move up") { shelf.moveUp(id) }
            .accessibilityAction(named: "Move down") { shelf.moveDown(id) }
            .accessibilityAction(named: "Remove from Shelf") { shelf.unpin(id) }
    }
}
