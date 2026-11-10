// CaptureLabApp.swift — Stage 1 feasibility app (tasks T034, T039; FR-090: internal test tool).
//
// Purpose: prove (or disprove) on physical devices which sources deliver real audio.
// It claims nothing about any app: the screen shows only what the classifier verified.
import AudioCore
import CaptureKit
import Diagnostics
import SwiftUI

@main
struct CaptureLabApp: App {
    @State private var model = CaptureLabModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
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
    private let lifecycle: LifecycleObserver
    private let lifecycleForwarding: Task<Void, Never>

    init() {
        microphone = MicrophoneSource(backend: AVMicrophoneBackend())
        let manager = CaptureManager(sources: [
            ScreenCaptureSource.makeDefault(),
            microphone,
            InAppPlaybackSource(backend: AVInAppPlaybackBackend()),
        ], signposts: DiagnosticsLog.pipeline)
        self.manager = manager
        let lifecycle = LifecycleObserver()
        self.lifecycle = lifecycle
        lifecycleForwarding = Self.forwardLifecycle(from: lifecycle, to: manager)
    }

    deinit {
        lifecycleForwarding.cancel()
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
    ///
    /// The model owns this task, so forwarding lasts as long as the app and does not depend on
    /// any window scene. A view `.task` would not do: when iPadOS closes and later recreates the
    /// scene, SwiftUI cancels that task, cancelling the consumer finishes `lifecycle.events` for
    /// good, and the new scene's task would find the stream already finished. Events posted
    /// before the task first runs are buffered by the stream, not lost.
    private static func forwardLifecycle(from lifecycle: LifecycleObserver,
                                         to manager: CaptureManager) -> Task<Void, Never> {
        Task { @MainActor in
            for await event in lifecycle.events {
                await manager.handle(event)
            }
        }
    }
}
