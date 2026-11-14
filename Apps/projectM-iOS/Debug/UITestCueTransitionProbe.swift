// UITestCueTransitionProbe.swift — DEBUG only (XFADE-R9, specs/167-cue-transitions-on-screen): with
// `-uitestDiagnostics`, an invisible text `cueTransitionProbe` whose value is the stage's probe
// ("outcome=blended frames=… progress=… holds=…"), read every 0.1 s (CueTransitionUITests).
#if DEBUG
import SwiftUI

struct UITestCueTransitionProbe: View {
    let stage: CueTransitionStage

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { (_: TimelineViewDefaultContext) in
            let value: String = stage.probe
            Text(value)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("cueTransitionProbe")
                .accessibilityValue(value)
        }
    }
}
#endif
