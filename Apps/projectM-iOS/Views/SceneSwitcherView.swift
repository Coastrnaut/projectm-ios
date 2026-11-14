// SceneSwitcherView.swift — UIX-002: the quick scene switcher overlay (spec UIX-002-R1 to R5, R9,
// R10; contract C1, C2; research UIX-002-D1, D4, D5).
//
// * `SceneSwitcherLayer`: placed once in the visualizer's ZStack above the controls. It shows the
//   card while the switcher is open and Settings is closed, and (DEBUG, `-uitestDiagnostics`) the
//   `sceneSwitcherProbe` element, which outlives the card so tests read the latency after a choice.
// * The card: a dim backdrop (a tap closes), "Scenes" with Close (Escape through `.cancelAction`), a
//   search field focused on open, the result count and a lazy list. Up and Down Arrow in the field
//   move the highlight, Return chooses it, Escape closes (the field's key handler while it is focused). The list is its own subtree, so its updates never
//   recreate the field (focus and text stay).
// * Device UI only: like the controls, it is never drawn into the visual's slot (external display,
//   saved frames, recordings).
// * Accessibility: entry labels and values, the Selected trait on the highlight, wrapping at
//   accessibility sizes; the appearance fades through MotionPolicy (instant with Reduce Motion).
//   Announcements go through the coordinator's announcer, never a direct post (ACC-011-R11).
import SwiftUI

struct SceneSwitcherLayer: View {
    let coordinator: AppCoordinator

    var body: some View {
        let shown: Bool = coordinator.sceneSwitcher.isOpen && !coordinator.showSettings
        ZStack {
            if shown {
                SceneSwitcherView(coordinator: coordinator)
                    .transition(.opacity)
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {   // UIX-002-R8, contract C4
                let value: String = coordinator.sceneSwitcher.probeText
                Text(value)
                    .font(.caption2)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("sceneSwitcherProbe")
                    .accessibilityValue(value)
            }
            #endif
        }
        .reduceMotionAware(MotionPolicy.controlsFade, value: shown, policy: coordinator.motion)
    }
}

struct SceneSwitcherView: View {
    let coordinator: AppCoordinator
    @FocusState private var fieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The list's content height, so the card is no taller than its entries.
    @State private var listHeight: CGFloat = 0

    private var model: SceneSwitcherModel { coordinator.sceneSwitcher }

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            let maxList: CGFloat = max(120, proxy.size.height * 0.55)
            ZStack(alignment: .top) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.closeSceneSwitcher() }
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("sceneSwitcherBackdrop")
                card(maxList: maxList)
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
        }
        .onAppear {
            fieldFocused = true
            // An overlay inserted in this transaction may not accept focus yet (research UIX-002-D5).
            Task { @MainActor () -> Void in fieldFocused = true }
        }
    }

    private func card(maxList: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            field
            Text(countText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sceneSwitcherCount")
            list(maxHeight: maxList)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sceneSwitcher")
    }

    private var header: some View {
        HStack {
            Text("Scenes")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("Close") { coordinator.closeSceneSwitcher() }
                .keyboardShortcut(.cancelAction)   // Escape (contract C2)
                .accessibilityIdentifier("sceneSwitcherClose")
        }
    }

    private var queryBinding: Binding<String> {
        Binding(get: { () -> String in coordinator.sceneSwitcher.query },
                set: { (text: String) in
                    guard text != coordinator.sceneSwitcher.query else { return }
                    coordinator.sceneSwitcher.query = text
                    coordinator.switcherQueryChanged()
                })
    }

    private var field: some View {
        TextField("Search scenes", text: queryBinding)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($fieldFocused)
            .onSubmit {
                coordinator.chooseHighlightedSwitcherScene()
                // Nothing matched: the text and focus stay (spec US2 scenario 4).
                if coordinator.sceneSwitcher.isOpen { fieldFocused = true }
            }
            .onKeyPress(.downArrow) { () -> KeyPress.Result in
                coordinator.moveSwitcherHighlight(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) { () -> KeyPress.Result in
                coordinator.moveSwitcherHighlight(by: -1)
                return .handled
            }
            // Escape while typing: the focused field sees the key first (the Close button's
            // `.cancelAction` covers Escape when the field is not focused).
            .onKeyPress(.escape) { () -> KeyPress.Result in
                coordinator.closeSceneSwitcher()
                return .handled
            }
            .accessibilityLabel("Search scenes")
            .accessibilityIdentifier("sceneSwitcherField")
    }

    private var countText: String {
        let entries: [SceneSwitcherEntry] = coordinator.sceneSwitcherEntries
        let count: Int = model.results(entries).count
        return AccessibilityAnnouncer.sceneSwitcherCountText(count)
    }

    private func list(maxHeight: CGFloat) -> some View {
        let results: [SceneSwitcherEntry] = model.results(coordinator.sceneSwitcherEntries)
        let highlighted: UUID? = model.highlightedCueID
        return ScrollViewReader { (reader: ScrollViewProxy) in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(results) { (entry: SceneSwitcherEntry) in
                        row(entry, isHighlighted: entry.cueID == highlighted)
                            .id(entry.cueID)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { (geometry: GeometryProxy) -> CGFloat in geometry.size.height }
                    action: { (height: CGFloat) in listHeight = height }
            }
            .frame(height: min(max(listHeight, 1), maxHeight))
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: highlighted) { (_: UUID?, id: UUID?) in
                if let id { reader.scrollTo(id) }
            }
        }
    }

    private var nameLines: Int? { typeSize.isAccessibilitySize ? nil : 2 }

    private func row(_ entry: SceneSwitcherEntry, isHighlighted: Bool) -> some View {
        let subtitle: String = rowSubtitle(entry)
        let traits: AccessibilityTraits = isHighlighted ? .isSelected : []
        let fill: Color = isHighlighted ? Color.accentColor.opacity(0.28) : Color.clear
        return Button { coordinator.chooseSwitcherScene(entry.cueID) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label)
                        .font(.body)
                        .lineLimit(nameLines)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nameLines)
                }
                Spacer(minLength: 4)
                if entry.isActive {
                    Image(systemName: "play.fill").font(.caption)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.label)
        .accessibilityValue(entry.accessibilityValue)
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("sceneSwitcherEntry.\(entry.number)")
    }

    /// "Cue 3", "Cue 3 · Drop copy", "Cue 3 · Scene missing".
    private func rowSubtitle(_ entry: SceneSwitcherEntry) -> String {
        var parts: [String] = ["Cue \(entry.number)"]
        if let name = entry.sceneName { parts.append(name) }
        if entry.isMissing { parts.append("Scene missing") }
        return parts.joined(separator: " · ")
    }
}
