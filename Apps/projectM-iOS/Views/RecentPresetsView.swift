// RecentPresetsView.swift — the browser's Recently Played list (roadmap PRE-006,
// specs/159-pre-006-recent-history; R4-R6). The presets that stayed on screen for 3 s, most recent first,
// as the browser's standard rows (star, Add to Collection, Tags…); locked presets are marked and open the
// purchase sheet. Choosing one plays it in the current scope (the list reorders itself as presets play,
// so it is not a scope to walk). Clear History asks first and removes the history only.
import PresetLibrary
import SwiftUI

/// The browser's route to the Recently Played list.
enum RecentRoute: Hashable { case list }

struct RecentPresetsView: View {
    @Bindable var presets: PresetCoordinator
    let recent: RecentPresetsCoordinator
    let onChoose: (IndexedPreset, PresetScope) -> Void
    /// Closes the whole browser.
    let onDone: () -> Void
    @State private var confirming = false

    var body: some View {
        let listing: [IndexedPreset] = recent.listing(in: presets.library)
        List {
            if listing.isEmpty {
                Text(recent.isEnabled ? RecentPresetsCoordinator.emptyText : RecentPresetsCoordinator.offText)
                    .accessibilityIdentifier("recentEmpty")
            }
            ForEach(listing) { (preset: IndexedPreset) in
                PresetRow(presets: presets, preset: preset, showsPack: true) { onChoose(preset, presets.scope) }
            }
            if !recent.ids.isEmpty { clearSection }
        }
        .accessibilityIdentifier("recentList")
        .navigationTitle(RecentPresetsCoordinator.title)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
        .recentClearConfirmation(recent, isPresented: $confirming)
    }

    private var clearSection: some View {
        Section {
            Button(RecentPresetsCoordinator.clearTitle, role: .destructive) { confirming = true }
                .accessibilityIdentifier("recentClear")
        }
    }
}

extension View {
    /// PRE-006-R4: the destructive confirmation before Clear History (shared by the list and Settings).
    func recentClearConfirmation(_ recent: RecentPresetsCoordinator, isPresented: Binding<Bool>) -> some View {
        alert(RecentPresetsCoordinator.confirmationTitle, isPresented: isPresented) {
            // No identifier: SwiftUI gives an alert action's identifier to every action of the alert.
            Button(RecentPresetsCoordinator.clearTitle, role: .destructive) { recent.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(RecentPresetsCoordinator.confirmationMessage)
        }
    }
}

/// The browser home's "Recently Played" row (R5, R6).
struct RecentPresetsHomeRow: View {
    let presets: PresetCoordinator
    let recent: RecentPresetsCoordinator

    var body: some View {
        let count: Int = recent.listing(in: presets.library).count
        NavigationLink(value: RecentRoute.list) {
            HStack {
                Text(RecentPresetsCoordinator.title)
                Spacer()
                Text(count.formatted())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(RecentPresetsCoordinator.rowLabel(count: count))
        }
        .accessibilityIdentifier("node:recent")
    }
}
