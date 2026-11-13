// UITestRenderFaultPanel.swift — the render fault probe for RenderFaultUITests (PERF-014-R15). DEBUG
// builds only, and only with the launch argument `-uitestRenderFaults <list>` (the faults every new
// visual is armed with; RenderFaultInjection.parse). Release builds contain none of this.
//
// "faults:clear" disarms every live visual and the renderer, so the next retry (or reset) succeeds.
// The readouts are hidden values for XCUITest: the shown visual's health, its fault count, its frame
// ticks and frames shown.
#if DEBUG
import SwiftUI

struct UITestRenderFaultPanel: View {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(AppCoordinator.renderFaultsArgument) }

    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button("faults:clear") { coordinator.clearRenderFaults() }
                .accessibilityIdentifier("faults:clear")
                .font(.system(size: 9))
                .buttonStyle(.bordered)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let health = coordinator.activeRenderHealth
                VStack {
                    value("renderHealth", health.debugValue)
                    value("renderFaults", "\(health.faultCount)")
                    value("renderTicks", "\(coordinator.activeRenderTicks)")
                    value("visualFrames", "\(coordinator.activeVisualFrames)")
                    value("renderPlaceholderShown", coordinator.showsRenderPlaceholder ? "yes" : "no")
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
