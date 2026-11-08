// ExportView.swift — tester-initiated diagnostics export (FR-021). Metadata only; leaves the
// device only if the tester shares it from the system share sheet.
import AudioCore
import CaptureKit
import CaptureUI
import Diagnostics
import SwiftUI

struct ExportView: View {
    let manager: CaptureManager
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var files: [URL] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(UIStrings.exportNotePlaceholder, text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: note) { _, new in
                            if new.count > DiagnosticsSnapshot.maxNoteLength {
                                note = String(new.prefix(DiagnosticsSnapshot.maxNoteLength))
                            }
                        }
                    Text("\(note.count)/\(DiagnosticsSnapshot.maxNoteLength)").font(.caption).foregroundStyle(.secondary)
                } footer: {
                    Text("The export contains metadata only: no audio, no device identifiers.")
                }
                Section {
                    Button("Create export") { create() }
                    if !files.isEmpty {
                        ShareLink(items: files) { Label("Share files", systemImage: "square.and.arrow.up") }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Export diagnostics")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(UIStrings.cancel) { dismiss() } } }
        }
    }

    private func create() {
        guard let mode = manager.activeMode else { return }
        let input = DiagnosticsInput(
            sourceMode: mode, finalState: manager.state, stopReason: manager.stopReason,
            hasVerifiedActiveAudio: manager.hasVerifiedActiveAudio, statistics: manager.statistics,
            durationSeconds: manager.sessionSeconds,
            formats: manager.formatsSeen.map { ($0.format, $0.firstSeenSeconds) },
            peakDBFSMax: manager.sessionPeakMaxDBFS, rmsDBFSMean: manager.sessionRMSMeanDBFS,
            transitions: manager.transitions,
            lifecycle: manager.lifecycleLog.map { ($0.atSeconds, $0.event) },
            stopDetail: manager.stopDetail)
        do {
            let snapshot = try DiagnosticsSnapshot.build(from: input, note: note,
                                                         device: DiagnosticsEnvironment.device(),
                                                         app: DiagnosticsEnvironment.app())
            files = try DiagnosticsExporter.write(snapshot)
            error = nil
        } catch {
            self.error = "Export failed: \(error.localizedDescription)"
        }
    }
}
