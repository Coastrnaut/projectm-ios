// IdleTimerPolicy.swift — when device auto-lock is suppressed (task T086; FR-084).
//
// Auto-lock is suppressed only while the visualization is running in the foreground: on the
// visualizer screen, not paused by the user (FR-046), and with the app active. Pausing, stopping
// (leaving the visualizer) or leaving the foreground restores it.
import Foundation

enum VisualizationState: Equatable, Sendable {
    /// Notice or source chooser: nothing is visualized.
    case notVisualizing
    case running
    /// Paused by the user (FR-046).
    case paused
    /// The app left the foreground (FR-050); rendering stops until it returns.
    case suspended
}

enum IdleTimerPolicy {
    /// True when `UIApplication.isIdleTimerDisabled` should be true.
    static func suppressAutoLock(visualization: VisualizationState, appIsActive: Bool) -> Bool {
        visualization == .running && appIsActive
    }
}
