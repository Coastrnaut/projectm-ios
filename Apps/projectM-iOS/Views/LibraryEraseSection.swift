// LibraryEraseSection.swift — FILE-011 (contract E7; FILE-011-R1, R2, R10): Settings › Storage › Erase.
// The section (Erase Data…, the pending erase with Cancel Erase, the last result), the sheet (six
// categories with counts and sizes, Select All, Back Up Library First…) and the destructive
// confirmation naming the chosen categories. Standard rows and wrapping text, so Dynamic Type and
// VoiceOver apply; nothing animates. Small bodies (CI's Xcode 26).
import LibraryBackup
import SwiftUI

struct LibraryEraseSection: View {
    @Bindable var model: LibraryEraseCoordinator

    var body: some View {
        Section {
            Button("Erase Data…", role: .destructive) { model.openSheet() }
                .disabled(!model.canStart)
                .accessibilityIdentifier("libraryEraseButton")
            if model.pending == nil && model.isRestorePending() {
                Text(LibraryEraseCoordinator.restorePendingNote).font(.footnote).accessibilityIdentifier("libraryEraseRestoreNote")
            }
            if let pending = model.pending { pendingRows(pending) }
            if let message = model.message {
                Text(message).font(.footnote).accessibilityIdentifier("libraryEraseMessage")
            }
        } header: {
            Text("Erase")
        } footer: {
            Text(LibraryEraseCoordinator.footer)
        }
        .onAppear { model.refresh() }
    }

    private func pendingRows(_ pending: Set<LibraryEraseCategory>) -> some View {
        Group {
            Text(LibraryEraseCoordinator.pendingText + " " + LibraryEraseCoordinator.pendingDetail(pending))
                .accessibilityIdentifier("libraryErasePending")
            Button("Cancel Erase") { model.cancelErase() }
                .accessibilityIdentifier("libraryEraseCancelPending")
        }
    }
}

/// The sheet, attached to the screen's List (presentations on a lazily built row are unreliable).
struct LibraryErasePresentation: ViewModifier {
    @Bindable var model: LibraryEraseCoordinator
    let backUp: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $model.showSheet) {
            LibraryEraseSheet(model: model, backUp: backUp)
        }
    }
}

extension View {
    /// FILE-011: the Erase sheet (nil: none).
    @ViewBuilder
    func libraryErasePresentation(_ backup: LibraryBackupCoordinator?) -> some View {
        if let backup {
            modifier(LibraryErasePresentation(model: backup.erase, backUp: { () -> Void in backup.backUp() }))
        } else {
            self
        }
    }
}

struct LibraryEraseSheet: View {
    @Bindable var model: LibraryEraseCoordinator
    let backUp: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            List {
                categorySection
                actionSection
            }
            .navigationTitle("Erase Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert(LibraryEraseCoordinator.confirmationTitle(model.selection), isPresented: $model.showConfirmation) {
                Button("Erase at Next Launch", role: .destructive) { model.requestErase() }
                    .accessibilityIdentifier("libraryEraseConfirm")
                Button("Cancel", role: .cancel) { model.showConfirmation = false }
                    .accessibilityIdentifier("libraryEraseConfirmCancel")
            } message: {
                Text(LibraryEraseCoordinator.confirmationMessage(model.selection, inventory: model.inventory))
            }
        }
    }

    private var categorySection: some View {
        Section {
            ForEach(LibraryEraseCategory.allCases, id: \.self) { (category: LibraryEraseCategory) in
                LibraryEraseCategoryRow(category: category, item: model.inventory?.item(category),
                                        selected: model.selection.contains(category)) { model.toggle(category) }
            }
        } header: {
            Text("Choose what to erase")
        } footer: {
            Text(LibraryEraseCoordinator.footer)
        }
    }

    private var actionSection: some View {
        Section {
            Button(model.allSelected ? "Deselect All" : "Select All") { model.toggleAll() }
                .accessibilityIdentifier("libraryEraseSelectAll")
            Button("Back Up Library First…") {
                model.dismissSheet()
                backUp()
            }
            .accessibilityIdentifier("libraryEraseBackUpFirst")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { model.dismissSheet() }.accessibilityIdentifier("libraryEraseDismiss")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Erase…", role: .destructive) { model.continueTapped() }
                .disabled(model.selection.isEmpty)
                .accessibilityIdentifier("libraryEraseContinue")
        }
    }
}

/// One category: a checkmark, the title and "<count> items, <size>"; VoiceOver reads
/// "<title>, <count> items, <size>, selected".
struct LibraryEraseCategoryRow: View {
    let category: LibraryEraseCategory
    let item: LibraryEraseInventory.Item?
    let selected: Bool
    let action: @MainActor () -> Void

    var body: some View {
        let detail: String = LibraryEraseCoordinator.detail(item)
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.red : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).foregroundStyle(Color.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.title)
        .accessibilityValue(detail)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("libraryEraseRow." + category.rawValue)
    }
}
