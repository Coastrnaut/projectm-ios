// StorageUsageView.swift — FILE-009: Settings › Storage. Nine categories and a total, each the space its
// files take on this device (FILE-009-R1, R3), a Refresh button, a busy row while measuring and a note
// when the walk was incomplete (R6). Read-only: clearing caches is FILE-010, erasing data FILE-011 (R7).
// Free space on the device is deliberately not shown (privacy manifest; spec Clarifications).
// FILE-010: Clear Caches… (contracts/cache-cleanup.md C4): a confirmation stating the space to be freed and
// what is kept, then the cleared size and a failure note; the user-data rows never change.
import LocalPortability
import SwiftUI

struct StorageUsageView: View {
    @State private var model: StorageUsageModel

    init(model: StorageUsageModel? = nil, filesInUse: @escaping @MainActor () -> Set<String> = { () -> Set<String> in [] }) {
        _model = State(initialValue: model ?? StorageUsageModel(locations: StorageLocations.forCurrentLaunch(), filesInUse: filesInUse))
    }

    static let incompleteNote = "Some files could not be counted; sizes may be higher."
    static let keptNote = "Photos, videos, scenes, the show, presets, imported audio and settings are kept."
    static let cleanupFailedNote = "Some files could not be removed."

    /// The confirmation's message (FILE-010-R2).
    static func confirmationMessage(_ plan: CacheCleanupPlan) -> String {
        let size = format(plan.bytesToFree)
        var text = (plan.isComplete ? "Frees \(size). " : "Frees about \(size). ") + keptNote
        if !plan.keptInUse.isEmpty { text += " Files in use are kept." }
        return text
    }

    static func promptTitle(_ prompt: StorageUsageModel.CleanupPrompt?) -> String {
        if case .nothingToClear = prompt { return "Nothing to Clear" }
        return "Clear Caches?"
    }

    static func cleanedNote(_ result: CacheCleanupResult) -> String { "Cleared \(format(result.bytesFreed))." }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func value(_ bytes: Int64?) -> String {
        guard let bytes else { return "Calculating…" }
        return Self.format(bytes)
    }

    /// One row read by VoiceOver as "<title>, <size>".
    private func row(_ title: String, bytes: Int64?, id: String, bold: Bool = false) -> some View {
        let text = value(bytes)
        return HStack {
            Text(title).fontWeight(bold ? .semibold : .regular)
            Spacer()
            Text(text).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(text)
        .accessibilityIdentifier(id)
    }

    var body: some View {
        let report = model.report
        List {
            if model.isMeasuring {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Calculating…").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("storageMeasuring")
                }
            }
            Section {
                ForEach(StorageCategory.allCases, id: \.self) { (category: StorageCategory) in
                    row(category.title, bytes: report?.usage(category).spaceUsed, id: "storage.\(category.rawValue)")
                }
                row("Total", bytes: report?.total.spaceUsed, id: "storage.total", bold: true)
            } footer: {
                Text("The space this app's own data takes on this device. The app and its bundled presets are not included.")
            }
            if let report, !report.isComplete {
                Section {
                    Text(Self.incompleteNote).accessibilityIdentifier("storageIncomplete")
                }
            }
            cleanupSection
            #if DEBUG
            if UITestStorageFixture.isEnabled {
                Section {
                    Button("Add Test Recording") { UITestStorageFixture.addRecording() }
                        .accessibilityIdentifier("storageAddFixture")
                }
            }
            #endif
        }
        .navigationTitle("Storage")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") { model.refresh() }
                    .disabled(model.isClearing)
                    .accessibilityIdentifier("storageRefresh")
            }
        }
        .alert(Self.promptTitle(model.cleanupPrompt),
               isPresented: Binding(get: { () -> Bool in model.cleanupPrompt != nil },
                                    set: { (shown: Bool) in if !shown { model.dismissCleanup() } }),
               presenting: model.cleanupPrompt) { (prompt: StorageUsageModel.CleanupPrompt) in
            switch prompt {
            case .confirm(let plan):
                Button("Clear", role: .destructive) { model.confirmCleanup(plan) }
                    .accessibilityIdentifier("storageClearConfirm")
                Button("Cancel", role: .cancel) { model.dismissCleanup() }
            case .nothingToClear:
                Button("OK", role: .cancel) { model.dismissCleanup() }
            }
        } message: { (prompt: StorageUsageModel.CleanupPrompt) in
            switch prompt {
            case .confirm(let plan): Text(Self.confirmationMessage(plan))
            case .nothingToClear(let keptInUse): Text(keptInUse ? "The remaining files are in use." : "There are no caches to clear.")
            }
        }
        .onAppear { model.refresh() }
        .onDisappear { model.cancel() }
    }

    /// FILE-010-R1, R6, R9.
    private var cleanupSection: some View {
        Section {
            Button {
                model.prepareCleanup()
            } label: {
                HStack {
                    Text("Clear Caches…")
                    if model.isPlanningCleanup || model.isClearing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!model.canClearCaches)
            .accessibilityIdentifier("storageClearCaches")
            if let result = model.lastCleanup {
                Text(Self.cleanedNote(result)).accessibilityIdentifier("storageCleanupResult")
                if !result.failed.isEmpty {
                    Text(Self.cleanupFailedNote).accessibilityIdentifier("storageCleanupFailed")
                }
            }
        } footer: {
            Text("Removes leftover recordings, share and export copies, and caches the system can rebuild. \(Self.keptNote)")
        }
    }
}
