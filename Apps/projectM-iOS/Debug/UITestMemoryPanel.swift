// UITestMemoryPanel.swift — the memory pressure probe for MemoryPressureUITests (PERF-006-R15,
// research PERF-006-D7). DEBUG builds only, and only with the launch argument `-uitestMemoryPressure`;
// Release builds contain none of this.
//
// "memory:warning" posts `UIApplication.didReceiveMemoryWarningNotification`, the notification UIKit
// posts for a real warning, so the coordinator's observer, steps and logging run exactly as for the
// system's warning; only the memory pressure itself is simulated. "memory:critical" calls the
// coordinator with the critical level (the system warning carries no level). The readouts are hidden
// values for XCUITest.
#if DEBUG
import SwiftUI
import UIKit

struct UITestMemoryPanel: View {
    static let argument = "-uitestMemoryPressure"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Button("memory:warning") {
                    NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
                }
                .accessibilityIdentifier("memory:warning")
                Button("memory:critical") { coordinator.memoryPressure.handle(.critical) }
                    .accessibilityIdentifier("memory:critical")
            }
            .font(.system(size: 9))
            .buttonStyle(.bordered)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let recovery = coordinator.memoryPressure.recovery
                VStack {
                    value("memoryRecoveries", "\(recovery.recoveries)")
                    value("memoryFreedBytes", "\(coordinator.memoryPressure.lastReport?.freedBytes ?? -1)")
                    value("memoryRetiredBytes", "\(SharedTexturePool.retiredBytes)")
                    value("memoryWarmUpContext", coordinator.warmUpHoldsContext ? "yes" : "no")
                    value("visualFrames", "\(coordinator.activeVisualFrames)")
                }
                .font(.caption2)
                .opacity(0.01)
            }
        }
        .padding(4)
        .background(.black.opacity(0.6))
    }

    private func value(_ id: String, _ text: String) -> some View {
        Text(text).accessibilityIdentifier(id).accessibilityValue(text)
    }
}
#endif
