// ProjectMApp.swift — the visualizer app (Stage 2; tasks T080, T082). The screen follows
// AppCoordinator: photosensitivity notice (first launch) → source chooser → full-screen visualizer.
// The chooser also lists the user's imported audio and opens the Files picker for it (AUD-001)
// and the play queue (AUD-003),
// and offers generated test signals under Diagnostics (AUD-016).
import CaptureKit
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
                // OUT-001: the visualization-only window on a connected display (iOS 27 scene
                // accessory; iOS 26 uses the Info.plist external display role).
                .externalDisplayAccessory(coordinator.externalDisplay)
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
                                         onRemove: { coordinator.removeImported($0) },
                                         queueCount: coordinator.audioLibrary.queue.ids.count,
                                         onShowQueue: { coordinator.openQueue() },
                                         onPlayNext: { coordinator.audioLibrary.playNext($0) },
                                         onAddToQueue: { coordinator.audioLibrary.addToQueue($0) })
                    // AUD-016: generated test signals, one level down; nothing plays until one is tapped.
                    TestSignalsSection { coordinator.playTestSignal($0) }
                })
                .navigationTitle("Choose source")
            }
            // OSC-007-R2: an enabled listener already runs on the chooser, so its badge is shown here too.
            .safeAreaInset(edge: .bottom) { OSCListenerBadge(osc: coordinator.osc).padding(.bottom, 4) }
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
            // AUD-003: the queue, with Play Queue; a row plays that track.
            .sheet(isPresented: $coordinator.showQueue) {
                NavigationStack {
                    PlayQueueView(queue: coordinator.audioLibrary.queue, isPlaying: false,
                                  onPlayQueue: { coordinator.playQueue() }, onPlay: { coordinator.playQueued($0) },
                                  onDone: { coordinator.closeQueue() })
                }
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
