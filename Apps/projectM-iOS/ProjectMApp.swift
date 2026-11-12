// ProjectMApp.swift — the visualizer app (Stage 2; tasks T080, T082). The screen follows
// AppCoordinator: photosensitivity notice (first launch) → source chooser → full-screen visualizer.
// The chooser also lists the user's imported audio and opens the Files picker for it (AUD-001).
import CaptureUI
import SwiftUI
import UniformTypeIdentifiers

@main
struct ProjectMApp: App {
    @State private var coordinator = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
                .onChange(of: scenePhase) { _, phase in coordinator.sceneBecame(active: phase == .active) }
        }
    }
}

struct RootView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        switch coordinator.screen {
        case .notice:
            PhotosensitivityNoticeView { coordinator.acknowledgeNotice() }
                .onAppear { automationNoticeAppeared() }
        case .chooser:
            NavigationStack {
                SourceChooserView(availability: coordinator.availability, onSelect: { coordinator.select($0) }, extraSections: {
                    // AUD-001: imported tracks, played as In-App Playback.
                    ImportedAudioSection(tracks: coordinator.audioLibrary.tracks,
                                         isImporting: coordinator.audioLibrary.isImporting,
                                         unavailableMessage: coordinator.audioLibrary.unavailableMessage,
                                         onImport: { coordinator.importAudio() },
                                         onPlay: { coordinator.play($0) },
                                         onRemove: { coordinator.removeImported($0) })
                })
                .navigationTitle("Choose source")
            }
            .onAppear { automationChooserAppeared() }
            // AUD-001-R1: the system Files picker, audio types only. The picked URLs are used once,
            // to copy the files into the app's library, and are not kept.
            .fileImporter(isPresented: $coordinator.showAudioImporter, allowedContentTypes: [.audio],
                          allowsMultipleSelection: true) { coordinator.audioPicked($0) }
            .alert(UIStrings.importAlertTitle, isPresented: importResultShown) {
                Button(UIStrings.ok) { coordinator.audioLibrary.resultMessage = nil }
            } message: {
                Text(coordinator.audioLibrary.resultMessage ?? "")
            }
            .sheet(isPresented: $coordinator.showMicrophoneExplainer) {
                MicrophoneExplainerView(onContinue: { coordinator.microphoneExplainerContinue() },
                                        onCancel: { coordinator.showMicrophoneExplainer = false })
            }
        case .visualizer:
            VisualizerView(coordinator: coordinator)
        }
    }

    /// The import result alert (AUD-001-R6): shown while there is a message.
    private var importResultShown: Binding<Bool> {
        Binding(get: { coordinator.audioLibrary.resultMessage != nil },
                set: { if !$0 { coordinator.audioLibrary.resultMessage = nil } })
    }

    private func automationChooserAppeared() {
        #if DEBUG || PROJECTM_AUTOMATION
        AutomationRunner.chooserAppeared(coordinator)   // SC-015 cold-launch timing
        #endif
    }

    private func automationNoticeAppeared() {
        #if DEBUG || PROJECTM_AUTOMATION
        AutomationRunner.noticeAppeared(coordinator)
        #endif
    }
}
