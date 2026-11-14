// BulkPresetImportViews.swift — "Import Folder or Archive…" in My Presets (roadmap PRE-013,
// specs/174-pre-013-bulk-import; PRE-013-R1, R7, R9; contract C4).
//
// * `BulkImportSection`: the button (its own `fileImporter` for one folder or one `.zip`), and while an
//   import runs, the progress ("n of N files", running counts) with Cancel.
// * `BulkImportSummaryView`: the summary sheet — the one-line summary, the count of each outcome and
//   one row per file (path, outcome, reason), optionally only the skipped and failed files.
// Announcements are made by BulkPresetImportCoordinator on the library lane; these views post none.
import PresetLibrary
import SwiftUI

struct BulkImportSection: View {
    @Bindable var userPresets: UserPresetsCoordinator
    @State private var picking = false

    private var bulk: BulkPresetImportCoordinator { userPresets.bulk }

    private var disabled: Bool {
        bulk.isRunning || userPresets.isImporting || userPresets.isExporting || userPresets.unavailableMessage != nil
    }

    var body: some View {
        Section {
            if bulk.isRunning {
                progressRow
            } else {
                importButton
            }
        } footer: {
            Text("Imports every .milk preset in a folder or a .zip archive. Copies of presets you already have are skipped.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: BulkPresetImportCoordinator.pickerTypes,
                      allowsMultipleSelection: false) { (result: Result<[URL], any Error>) in
            let picked: Result<URL, any Error> = result.flatMap { (urls: [URL]) -> Result<URL, any Error> in
                urls.first.map { (url: URL) -> Result<URL, any Error> in .success(url) } ?? .failure(CocoaError(.userCancelled))
            }
            Task { await bulk.importPicked(picked) }
        }
    }

    private var importButton: some View {
        Button {
            picking = true
        } label: {
            Label("Import Folder or Archive…", systemImage: "folder.badge.plus")
        }
        .disabled(disabled)
        .accessibilityIdentifier("bulkImport")
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: bulk.progress?.fraction ?? 0)
            Text(bulk.progressText)
                .accessibilityIdentifier("bulkImportProgressText")
            Button(bulk.isCancelling ? "Cancelling…" : "Cancel", role: .cancel) { bulk.cancel() }
                .disabled(bulk.isCancelling)
                .accessibilityIdentifier("bulkImportCancel")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bulkImportProgress")
    }
}

struct BulkImportSummaryView: View {
    let report: BulkImportReport
    let onDone: () -> Void
    @State private var problemsOnly = false

    private var shownItems: [BulkImportItem] {
        guard problemsOnly else { return report.items }
        return report.items.filter { (item: BulkImportItem) -> Bool in item.kind != .added }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                countsSection
                itemsSection
            }
            .navigationTitle(report.sourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone).accessibilityIdentifier("bulkImportDone")
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            Text(report.summary)
                .accessibilityIdentifier("bulkImportSummary")
        }
    }

    @ViewBuilder
    private var countsSection: some View {
        if report.refusal == nil {
            Section("Results") {
                ForEach(BulkImportKind.allCases, id: \.self) { (kind: BulkImportKind) in
                    LabeledContent(Self.title(kind), value: PresetImportLimits.grouped(report.counts[kind]))
                        .accessibilityIdentifier("bulkCount:\(kind.rawValue)")
                }
                if report.notHandled > 0 {
                    LabeledContent("Not handled", value: PresetImportLimits.grouped(report.notHandled))
                }
            }
        }
    }

    @ViewBuilder
    private var itemsSection: some View {
        if !report.items.isEmpty {
            Section("Files") {
                Toggle("Skipped and failed only", isOn: $problemsOnly)
                ForEach(shownItems) { (item: BulkImportItem) in
                    BulkImportItemRow(item: item)
                }
            }
        }
    }

    nonisolated static func title(_ kind: BulkImportKind) -> String {
        switch kind {
        case .added: return "Added"
        case .duplicate: return "Skipped, duplicate"
        case .invalid: return "Skipped, invalid"
        case .tooLarge: return "Skipped, too large"
        case .unsupported: return "Skipped, not a preset"
        case .failed: return "Failed"
        }
    }
}

private struct BulkImportItemRow: View {
    let item: BulkImportItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.path)
            Text(BulkImportSummaryView.title(item.kind) + ". " + item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bulkItem:\(item.path)")
    }
}
