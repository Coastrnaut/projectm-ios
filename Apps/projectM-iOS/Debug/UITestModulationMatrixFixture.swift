// UITestModulationMatrixFixture.swift — DEBUG only (MOD-012-T08; research MOD-012-D7). No route editor exists, so
// `-uitestSeedModulationMatrix` gives the current scene the acceptance routes before the first screen. Their output
// ranges are constant (start = end), so the matrix's probe is independent of audio and time:
//   A  kick  → glow intensity, replace 0.6
//   B  LFO 1 → glow intensity, multiply ×0.5 (second layer)
//   C  band 3 → glow radius, replace 0.04
// Intensity 0.3000 with both layers, 0.6000 with B off; radius 0.0400 throughout. Not compiled into Release builds.
#if DEBUG
import Foundation
import ParameterGraph
import VisualParameters

@MainActor
enum UITestModulationMatrixFixture {
    static let argument = "-uitestSeedModulationMatrix"

    static let routes: [AudioFeatureBinding] = [
        AudioFeatureBinding(source: .kick, target: VisualParameterIDs.bloomIntensity, outputStart: 0.6, outputEnd: 0.6, mixMode: .replace),
        AudioFeatureBinding(source: .lfo(0), target: VisualParameterIDs.bloomIntensity, outputStart: 0.5, outputEnd: 0.5, mixMode: .multiply),
        AudioFeatureBinding(source: .band(3), target: VisualParameterIDs.bloomRadius, outputStart: 0.04, outputEnd: 0.04, mixMode: .replace),
    ]

    static func seedIfRequested(_ coordinator: AppCoordinator) {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return }
        _ = coordinator.applyModulationEdit(.replace(routes))
    }
}
#endif
