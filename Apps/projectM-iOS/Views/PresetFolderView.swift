// PresetFolderView.swift — one pack or folder of the preset library (feature 002 T220; FR-112).
// Subfolders first, then the presets at this level; All A-Z is sectioned by letter with a section
// index. A locked pack shows an "Unlock all" row that opens the purchase sheet (FR-106).
import PresetLibrary
import SwiftUI

/// A pack or folder: its subfolders, then the presets at this level. All A-Z is sectioned by letter.
struct PresetFolderView: View {
    @Bindable var presets: PresetCoordinator
    let node: PresetNode
    let onChoose: (IndexedPreset, PresetScope) -> Void
    /// Closes the whole browser (Done is on every level, not only the home).
    let onDone: () -> Void

    var body: some View {
        List {
            if node.scope == .all {
                ForEach(letterSections, id: \.letter) { section in
                    Section(section.letter) {
                        ForEach(section.presets) { preset in
                            PresetRow(presets: presets, preset: preset, showsPack: false) { onChoose(preset, .all) }
                        }
                    }
                    .sectionIndexLabel(section.letter)
                }
            } else {
                if node.locked && !presets.unlocked {
                    Button {
                        presets.purchaseRequested = true
                    } label: {
                        Label("Unlock all \(unlockCount.formatted()) presets", systemImage: "lock.open")
                    }
                    .accessibilityIdentifier("unlockBanner")
                }
                ForEach(node.children) { child in
                    NavigationLink(value: child) {
                        FolderRow(title: child.title, count: child.presetCount, locked: child.locked && !presets.unlocked)
                    }
                    .accessibilityIdentifier("node:\(child.id)")
                }
                ForEach(presets.presets(in: node)) { preset in
                    PresetRow(presets: presets, preset: preset, showsPack: false) { onChoose(preset, node.scope) }
                }
            }
        }
        .listSectionIndexVisibility(node.scope == .all ? .visible : .automatic)
        .navigationTitle(node.title)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
        #if DEBUG || PROJECTM_AUTOMATION
        .overlay(alignment: .bottomLeading) { if FrameMeter.isEnabled { FrameMeterLabel() } }   // SC-103 (T238)
        #endif
    }

    private var unlockCount: Int {
        presets.library?.packs.filter(\.locked).reduce(0) { $0 + $1.presetCount } ?? 0
    }

    private var letterSections: [(letter: String, presets: [IndexedPreset])] {
        guard let library = presets.library else { return [] }
        let all = library.members(of: .all, unlocked: true, favorites: [], excluded: [])
        var sections: [(letter: String, presets: [IndexedPreset])] = []
        for preset in all {
            let first = preset.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).first
            let letter = first.map { $0.isLetter ? String($0).uppercased() : "#" } ?? "#"
            if sections.last?.letter == letter {
                sections[sections.count - 1].presets.append(preset)
            } else {
                sections.append((letter, [preset]))
            }
        }
        return sections
    }
}
