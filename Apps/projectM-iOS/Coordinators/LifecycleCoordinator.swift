// LifecycleCoordinator.swift — app lifecycle for the visualizer (task T099; FR-050, FR-054,
// data-model lifecycle matrix; PERF-011).
//
// Background and lock suspend the visualization in every mode and forward to CaptureManager, which
// applies the per-adapter matrix: System/App Capture keeps running (RI-003); Microphone and In-App
// Playback are suspended and show Paused. Foreground and unlock forward the resume (≤ 2 s) and
// resume the visualization unless the user paused it (FR-046). Interruptions, route changes and
// the OS ending a session arrive as source events and are handled by CaptureManager; their banners
// come from contracts/ui-states.md through StatusBanner.
//
// PERF-011: the same events decide whether the app can present frames (PresentationAvailability).
// Background and lock are independent conditions: an unlock while the app is still in the
// background resumes nothing, and entering the foreground clears both. When presentation is lost,
// every presentation-bound resource in the registry (the renderer's frame loop and surface, the
// preset warm-up, later camera and video layers) is suspended; when it returns they are resumed.
// The inactive scene phase is not an event here: the app is still visible. CaptureManager receives
// every event exactly as before.
import CaptureKit
import PresentationLifecycle

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
    /// Presentation-bound resources, suspended while the app cannot present frames (PERF-011).
    let presentation: PresentationResourceRegistry
    private var availability = PresentationAvailability()
    /// True between visualizationStarted() and visualizationEnded().
    private(set) var visualizing = false
    /// True while the app cannot present frames: backgrounded or locked.
    var suspended: Bool { !availability.canPresent }

    init(manager: CaptureManager, visualization: any VisualizationControlling,
         presentation: PresentationResourceRegistry = PresentationResourceRegistry()) {
        self.manager = manager
        self.visualization = visualization
        self.presentation = presentation
    }

    func visualizationStarted() { visualizing = true }
    func visualizationEnded() { visualizing = false }

    func handle(_ event: AppLifecycleEvent) async {
        let couldPresent = availability.canPresent
        let canPresent = availability.apply(Self.signal(for: event))
        if couldPresent, !canPresent {
            if visualizing { visualization?.suspendVisualization() }
            presentation.setCanPresent(false)
        } else if !couldPresent, canPresent {
            presentation.setCanPresent(true)
            if visualizing, visualization?.userPaused == false {
                visualization?.resumeVisualization()
            }
        }
        await manager.handle(event)
    }

    private static func signal(for event: AppLifecycleEvent) -> PresentationSignal {
        switch event {
        case .background: .enteredBackground
        case .foreground: .willEnterForeground
        case .lock: .locked
        case .unlock: .unlocked
        }
    }
}
