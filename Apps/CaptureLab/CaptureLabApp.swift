// CaptureLabApp.swift — Stage 1 feasibility app (tasks T034, T039; FR-090: internal test tool).
//
// Purpose: prove (or disprove) on physical devices which sources deliver real audio.
// It claims nothing about any app: the screen shows only what the classifier verified.
import AudioCore
import CaptureKit
import SwiftUI

@main
struct CaptureLabApp: App {
    @State private var model = CaptureLabModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task { await model.observeLifecycle() }
        }
    }
}

/// Owns the CaptureManager and the real sources.
@MainActor
@Observable
final class CaptureLabModel {
    let manager: CaptureManager
    let microphone: MicrophoneSource
    var showMicrophoneExplainer = false
    private let lifecycle = LifecycleObserver()

    init() {
        microphone = MicrophoneSource(backend: AVMicrophoneBackend())
        manager = CaptureManager(sources: [
            ScreenCaptureSource.makeDefault(),
            microphone,
            InAppPlaybackSource(backend: AVInAppPlaybackBackend()),
        ])
    }

    /// Source selection from the chooser (a user action, FR-002).
    func select(_ mode: AudioSourceMode) {
        if mode == .microphone && microphone.needsExplainer {
            showMicrophoneExplainer = true   // FR-005: explain before the permission prompt
            return
        }
        Task { await manager.select(mode) }
    }

    func microphoneExplainerContinue() {
        showMicrophoneExplainer = false
        microphone.acknowledgeExplainer()
        Task { await manager.select(.microphone) }
    }

    /// Forwards app background/foreground and lock/unlock to the manager (T039, FR-050–FR-054).
    func observeLifecycle() async {
        for await event in lifecycle.events {
            await manager.handle(event)
        }
    }
}
