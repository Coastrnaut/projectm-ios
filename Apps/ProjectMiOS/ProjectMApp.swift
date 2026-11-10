// ProjectMApp.swift — the visualizer app (Stage 2; tasks T080, T082). The screen follows
// AppCoordinator: photosensitivity notice (first launch) → source chooser → full-screen visualizer.
import CaptureUI
import SwiftUI

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
        case .chooser:
            NavigationStack {
                SourceChooserView(availability: coordinator.availability) { coordinator.select($0) }
                    .navigationTitle("Choose source")
            }
            .sheet(isPresented: $coordinator.showMicrophoneExplainer) {
                MicrophoneExplainerView(onContinue: { coordinator.microphoneExplainerContinue() },
                                        onCancel: { coordinator.showMicrophoneExplainer = false })
            }
        case .visualizer:
            VisualizerView(coordinator: coordinator)
        }
    }
}
