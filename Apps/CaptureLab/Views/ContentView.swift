// ContentView.swift — chooser + live diagnostics + controls (tasks T034; FR-007, FR-015, FR-055, FR-080, FR-083).
import AudioCore
import CaptureKit
import CaptureUI
import SwiftUI
import UIKit

struct ContentView: View {
    @Bindable var model: CaptureLabModel
    @State private var showExport = false
    @State private var showChooser = true

    private var manager: CaptureManager { model.manager }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                StatusBanner(mode: manager.activeMode, state: manager.state, reason: manager.stopReason,
                             prolongedSilence: manager.prolongedSilenceHint, onAction: handle)
                    .padding(.horizontal)

                if showChooser {
                    SourceChooserView(availability: Dictionary(uniqueKeysWithValues: AudioSourceMode.allCases.map {
                        ($0, manager.availability(of: $0))
                    })) { mode in
                        showChooser = false
                        model.select(mode)
                    }
                } else {
                    DiagnosticsView(manager: manager)
                }
            }
            .navigationTitle("CaptureLab")
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(UIStrings.chooseSource) { showChooser = true }
                    Spacer()
                    Button(UIStrings.stop) { Task { await manager.stop() } }
                        .disabled(!(manager.state.isRunning || manager.state == .paused || manager.state == .interrupted))
                    Spacer()
                    Button("Export") { showExport = true }
                        .disabled(manager.activeMode == nil)
                }
            }
            .sheet(isPresented: $model.showMicrophoneExplainer) {
                MicrophoneExplainerView(onContinue: model.microphoneExplainerContinue,
                                        onCancel: { model.showMicrophoneExplainer = false; showChooser = true })
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showExport) {
                ExportView(manager: manager)
            }
        }
    }

    private func handle(_ action: BannerAction) {
        switch action {
        case .chooseSource: showChooser = true
        case .restart: Task { await manager.restart() }       // re-presents the picker for capture (FR-055)
        case .resume: Task { await manager.resume() }
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
    }
}
