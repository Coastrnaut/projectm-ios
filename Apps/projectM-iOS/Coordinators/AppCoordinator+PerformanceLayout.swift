// AppCoordinator+PerformanceLayout.swift — UIX-005 (specs/193-uix-005-performance-controls): the
// performance layout's session state and the pad's actions.
//
// The pad's actions (PerformancePad.swift) step the show and record taps without showing the controls
// (UIX-005-R5, R6). The layout lasts for the session and is never stored (FR-065).
import Foundation

extension AppCoordinator {
    /// DEBUG `-uitestPerformanceLayout` starts with the layout on (contract C4); Release ignores it.
    static var startsInPerformanceLayout: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitestPerformanceLayout")
        #else
        false
        #endif
    }

    /// The controls' "Performance layout" / "Standard layout" button (UIX-005-R1); restarts the auto-hide.
    func togglePerformanceLayout() {
        showControls()
        performanceLayout.toggle()
    }
}
