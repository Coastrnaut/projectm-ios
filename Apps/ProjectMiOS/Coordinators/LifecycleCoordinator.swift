// LifecycleCoordinator.swift — app lifecycle for the visualizer (task T099; FR-050, FR-054,
// data-model lifecycle matrix).
//
// Background and lock suspend the visualization in every mode and forward to CaptureManager, which
// applies the per-adapter matrix: System/App Capture keeps running (RI-003); Microphone and In-App
// Playback are suspended and show Paused. Foreground and unlock forward the resume (≤ 2 s) and
// resume the visualization unless the user paused it (FR-046). Interruptions, route changes and
// the OS ending a session arrive as source events and are handled by CaptureManager; their banners
// come from contracts/ui-states.md through StatusBanner.
import CaptureKit

/// What the coordinator needs from the visualization (AppCoordinator; a fake in tests).
@MainActor
protocol VisualizationControlling: AnyObject {
    /// True while the user paused the visualization (FR-046).
    var userPaused: Bool { get }
    func suspendVisualization()
    func resumeVisualization()
}

@MainActor
final class LifecycleCoordinator {
    private let manager: CaptureManager
    private weak var visualization: (any VisualizationControlling)?
    /// True between visualizationStarted() and visualizationEnded().
    private(set) var visualizing = false
    /// True while backgrounded or locked.
    private(set) var suspended = false

    init(manager: CaptureManager, visualization: any VisualizationControlling) {
        self.manager = manager
        self.visualization = visualization
    }

    func visualizationStarted() { visualizing = true }
    func visualizationEnded() { visualizing = false }

    func handle(_ event: AppLifecycleEvent) async {
        switch event {
        case .background, .lock:
            if visualizing, !suspended { visualization?.suspendVisualization() }
            suspended = true
        case .foreground, .unlock:
            let wasSuspended = suspended
            suspended = false
            if visualizing, wasSuspended, visualization?.userPaused == false {
                visualization?.resumeVisualization()
            }
        }
        await manager.handle(event)
    }
}
