// UITestMacroFixture.swift — DEBUG only (MOD-010-T07; research MOD-010-D5). No macro editor exists, so
// `-uitestSeedMacro` gives the current scene the acceptance macro before the first screen: "Glow sweep" driving the
// glow intensity (easeIn 2, 10%…90%), the glow radius (logarithmic 9, reversed, 1%…5%) and the circular spectrum's
// bars, at 0. Not compiled into Release builds.
#if DEBUG
import Foundation
import ParameterGraph
import SceneFormat
import VisualParameters

@MainActor
enum UITestMacroFixture {
    static let argument = "-uitestSeedMacro"

    static let acceptance = ParameterMacro(name: "Glow sweep", value: 0, targets: [
        MacroTarget(parameter: VisualParameterIDs.bloomIntensity, curve: .easeIn(exponent: 2), outputMinimum: 0.1, outputMaximum: 0.9),
        MacroTarget(parameter: VisualParameterIDs.bloomRadius, curve: .logarithmic(strength: 9), outputMinimum: 0.01,
                    outputMaximum: 0.05, inverted: true),
        MacroTarget(parameter: VisualParameterIDs.circularSpectrumBarCount),
    ])

    static func seedIfRequested(_ macros: MacroCoordinator) {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return }
        macros.restore([SceneMacroEntry(acceptance)])
        macros.setValue(0, at: 0)
    }
}
#endif
