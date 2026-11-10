// PurchaseSheet.swift — the full-library purchase (feature 002 FR-106, FR-108; contracts/store.md):
// the localized price, the included packs with counts, Buy, Restore Purchases and Close, and a
// non-modal message for every outcome.
import PresetLibrary
import SwiftUI

struct PurchaseSheet: View {
    let packs: [PresetPackInfo]
    let price: String?
    let state: PurchaseState
    let onBuy: () -> Void
    let onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var lockedPacks: [PresetPackInfo] { packs.filter(\.locked) }
    private var total: Int { lockedPacks.reduce(0) { $0 + $1.presetCount } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Unlock \(total.formatted()) more presets from the projectM team's preset packs. One purchase, yours on every device with your Apple Account, and it works offline.")
                        .accessibilityIdentifier("purchaseSummary")
                }
                Section("Included") {
                    ForEach(lockedPacks) { pack in
                        LabeledContent(pack.title, value: pack.presetCount.formatted())
                    }
                }
                Section {
                    Button {
                        onBuy()
                    } label: {
                        HStack {
                            Text(price.map { "Unlock for \($0)" } ?? "Unlock")
                            if state == .purchasing || state == .loading { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(state == .purchasing || state == .unavailable && price == nil)
                    .accessibilityIdentifier("buyLibrary")
                    Button("Restore Purchases", action: onRestore)
                        .accessibilityIdentifier("restorePurchases")
                } footer: {
                    if let message = state.message {
                        Text(message).accessibilityIdentifier("purchaseMessage")
                    }
                }
            }
            .navigationTitle("Full preset library")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: state) { _, new in if new == .purchased { dismiss() } }
        }
        .accessibilityIdentifier("purchaseSheet")
    }
}
