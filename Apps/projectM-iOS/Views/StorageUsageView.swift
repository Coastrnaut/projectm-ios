// StorageUsageView.swift — FILE-009: Settings › Storage. Nine categories and a total, each the space its
// files take on this device (FILE-009-R1, R3), a Refresh button, a busy row while measuring and a note
// when the walk was incomplete (R6). Read-only: clearing caches is FILE-010, erasing data FILE-011 (R7).
// Free space on the device is deliberately not shown (privacy manifest; spec Clarifications).
import LocalPortability
import SwiftUI

struct StorageUsageView: View {
    @State private var model: StorageUsageModel

    init(model: StorageUsageModel = StorageUsageModel(locations: StorageLocations.forCurrentLaunch())) {
        _model = State(initialValue: model)
    }

    static let incompleteNote = "Some files could not be counted; sizes may be higher."

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
                    .accessibilityIdentifier("storageRefresh")
            }
        }
        .onAppear { model.refresh() }
        .onDisappear { model.cancel() }
    }
}
