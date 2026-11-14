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
// * SCN-005: a row of tag chips under the field (when the show has tags; AND; in memory), each row's
//   tags in its subtitle and value, and a tag button after each row (plus the VoiceOver action "Tags")
//   that opens the Tags sheet (`SceneTagsView`).
// * SCN-006: each row starts with its scene's preview picture (placeholder until one exists).
import ShowControl
import SwiftUI

struct SceneSwitcherLayer: View {
    let coordinator: AppCoordinator

    // Split into typed parts (QA-009, 2026-11-14): as one expression the ZStack took 193-215 ms to type-check
    // (-warn-long-expression-type-checking; CI's Xcode 26 limit is 200 ms).
    var body: some View {
        let open: Bool = coordinator.sceneSwitcher.isOpen
        let settingsShown: Bool = coordinator.showSettings
        let shown: Bool = open && !settingsShown
        let layer = ZStack {
            card(shown)
            probe
        }
        return layer.reduceMotionAware(MotionPolicy.controlsFade, value: shown, policy: coordinator.motion)
    }

    @ViewBuilder private func card(_ shown: Bool) -> some View {
        if shown {
            SceneSwitcherView(coordinator: coordinator)
                .transition(.opacity)
        }
    }

    @ViewBuilder private var probe: some View {
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
}

struct SceneSwitcherView: View {
    let coordinator: AppCoordinator
    @FocusState private var fieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The list's content height, so the card is no taller than its entries.
    @State private var listHeight: CGFloat = 0
    /// SCN-005: the scene whose Tags sheet is open.
    @State private var tagging: SceneTagsTarget?

    private var model: SceneSwitcherModel { coordinator.sceneSwitcher }

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            let maxList: CGFloat = max(120, proxy.size.height * 0.55)
            ZStack(alignment: .top) {
                // QA-009 (2026-11-14): `.accessibilityHidden(true)` did not keep the tappable backdrop out of the
                // accessibility tree: it stayed an unlabelled element across the screen ("Element has no description"
                // in the audit). It is now described as what it does, a button that closes the switcher.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.closeSceneSwitcher() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Close scenes")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { coordinator.closeSceneSwitcher() }
                    .accessibilityIdentifier("sceneSwitcherBackdrop")
                card(maxList: maxList)
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
        }
        .sheet(item: $tagging) { (target: SceneTagsTarget) in
            SceneTagsView(show: coordinator.show, sceneID: target.sceneID,
                          changed: { () -> Void in coordinator.switcherTagsEdited() },
                          done: { () -> Void in tagging = nil })
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
            tagChips
            Text(countText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sceneSwitcherCount")
            list(maxHeight: maxList)
        }
        .padding(14)
        .overlaySurface(RoundedRectangle(cornerRadius: 16))   // ACC-008-R2
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
                set: { (typed: String) in
                    // The wrapping field (accessibility sizes) takes Return as a newline: it chooses instead.
                    let submitted: Bool = typed.contains("\n")
                    let text: String = submitted ? typed.replacingOccurrences(of: "\n", with: "") : typed
                    if text != coordinator.sceneSwitcher.query {
                        coordinator.sceneSwitcher.query = text
                        coordinator.switcherQueryChanged()
                    }
                    if submitted { submit() }
                })
    }

    private func submit() {
        guard coordinator.sceneSwitcher.isOpen else { return }   // one Return, one choice
        coordinator.chooseHighlightedSwitcherScene()
        // Nothing matched: the text and focus stay (spec US2 scenario 4).
        if coordinator.sceneSwitcher.isOpen { fieldFocused = true }
    }

    /// ACC-006-R1: at accessibility sizes the query wraps over up to three lines, as the preset editor's
    /// name does; a one-line field clipped its placeholder at AX3 and AX5 (audit, 2026-11-14). A query is
    /// one line: Return chooses (queryBinding). Standard sizes keep the one-line field.
    @ViewBuilder private var fieldBase: some View {
        if typeSize.isAccessibilitySize {
            TextField(text: queryBinding, prompt: prompt, axis: .vertical) { Text("Search scenes") }.lineLimit(1...3)
        } else {
            TextField(text: queryBinding, prompt: prompt) { Text("Search scenes") }
        }
    }

    /// QA-009 (2026-11-14): the placeholder in the secondary style. The system placeholder grey on the card's dark
    /// surface failed the contrast audit (about 2:1); the secondary label colour reads about 6:1 there.
    private var prompt: Text { Text("Search scenes").foregroundStyle(.secondary) }

    private var field: some View {
        fieldBase
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($fieldFocused)
            .onSubmit { submit() }
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

    // MARK: - SCN-005 tag chips

    @ViewBuilder private var tagChips: some View {
        let vocabulary: [String] = coordinator.show.tagVocabulary
        if !vocabulary.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(vocabulary, id: \.self) { (tag: String) in chip(tag) }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filter by tag")
            .accessibilityIdentifier("sceneSwitcherTags")
        }
    }

    private func chip(_ tag: String) -> some View {
        let selected: Bool = model.isSelected(tag: tag)
        let count: Int = coordinator.show.sceneCount(withTag: tag)
        let value: String = count == 1 ? "1 scene" : "\(count) scenes"
        let traits: AccessibilityTraits = selected ? .isSelected : []
        let fill: Color = selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15)
        return Button { coordinator.toggleSwitcherTag(tag) } label: {
            HStack(spacing: 4) {
                Image(systemName: selected ? "checkmark" : "tag").font(.caption2).accessibilityHidden(true)
                Text(tag).font(.footnote)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag)
        .accessibilityValue(value)
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("sceneSwitcherTag.\(tag)")
    }

    private func openTags(_ entry: SceneSwitcherEntry) {
        guard let cue = coordinator.show.list.cues.first(where: { (c: ShowCue) -> Bool in c.id == entry.cueID }) else { return }
        tagging = SceneTagsTarget(sceneID: cue.sceneID)
    }

    private func tagButton(_ entry: SceneSwitcherEntry) -> some View {
        Button { openTags(entry) } label: {
            Image(systemName: entry.tags.isEmpty ? "tag" : "tag.fill")
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tags for \(entry.label)")
        .accessibilityIdentifier("sceneSwitcherTagsButton.\(entry.number)")
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
                        HStack(spacing: 4) {
                            row(entry, isHighlighted: entry.cueID == highlighted)
                            tagButton(entry)   // SCN-005
                        }
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
            HStack(alignment: .center, spacing: 8) {
                // QA-009 (2026-11-14): the thumbnail and the play mark are decorative (the row's value says
                // "current"); exposed, they read "Stack Of Rectangles" and "Play" inside the row, and the current
                // row could not be hit-tested as one control.
                ScenePreviewView(sceneID: entry.sceneID, model: coordinator.scenePreviews)   // SCN-006
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label)
                        .font(.body)
                        .lineLimit(nameLines)
                    // QA-009 (2026-11-14): on the highlighted row's accent fill the secondary grey failed the
                    // contrast audit ("Cue 1"); the highlighted row's subtitle uses the primary colour.
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? .primary : .secondary)
                        .lineLimit(nameLines)
                }
                Spacer(minLength: 4)
                if entry.isActive {
                    Image(systemName: "play.fill").font(.caption).accessibilityHidden(true)
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
        .accessibilityAction(named: "Tags") { openTags(entry) }   // SCN-005
        .accessibilityIdentifier("sceneSwitcherEntry.\(entry.number)")
    }

    /// "Cue 3", "Cue 3 · Drop copy", "Cue 3 · Scene missing", "Cue 3 · Set A / Encore" (SCN-004).
    private func rowSubtitle(_ entry: SceneSwitcherEntry) -> String {
        var parts: [String] = ["Cue \(entry.number)"]
        if let name = entry.sceneName { parts.append(name) }
        if entry.isMissing { parts.append("Scene missing") }
        if let path = entry.folderPath { parts.append(path) }   // SCN-004
        if !entry.tags.isEmpty { parts.append(entry.tags.joined(separator: ", ")) }   // SCN-005
        return parts.joined(separator: " · ")
    }
}
