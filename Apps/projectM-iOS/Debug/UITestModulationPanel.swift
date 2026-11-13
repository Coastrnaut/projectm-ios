// UITestModulationPanel.swift — the glow modulation readout and Unbind button for
// AudioFeatureBindingUITests (MOD-002-T12, T13; MOD-002-R12). DEBUG builds only, and only with the
// launch argument `-uitestBindGlowToLevel`; Release builds contain none of this.
//
// The readout ("bound, manual 0.50, effective 0.73") is refreshed four times a second from the
// native host; the frame loop itself never formats text. Simulator results are never device
// evidence.
#if DEBUG
import SwiftUI

struct UITestModulationPanel: View {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(AppCoordinator.bindGlowToLevelArgument) }

    let coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 4) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let readout = coordinator.glowModulationReadout
                Text(readout)
                    .accessibilityIdentifier("glowModulation")
                    .accessibilityValue(readout)
            }
            Button("Unbind") { coordinator.unbindGlowTest() }
                .accessibilityIdentifier("glowModulationUnbind")
        }
        .font(.system(size: 9))
        .buttonStyle(.bordered)
        .padding(4)
        .background(.black.opacity(0.6))
    }
}
#endif
