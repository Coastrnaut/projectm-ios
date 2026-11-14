// ShowTimelineRow.swift — SHOW-007-R8 the show timeline transport in the cue row (specs/243-show-007-timeline-transport;
// contract T7).
//
// * Shown under the cue row's buttons only when the show has a timeline (a timed cue). Play/Pause (SHOW-005's Hold),
//   the scrub slider, the position ("1:15 / 2:30", or the scrub preview "Cue 3 · Drop at 0:15") and Loop.
// * The slider is an ACC-005 accessible slider (5 s per swipe, each swipe one seek). A drag only moves the preview and
//   commits one seek on release (R4).
// * A `TimelineView` redraws the position twice a second only while the row is on screen.
import ShowControl
import SwiftUI

struct ShowTimelineRow: View {
    let transport: ShowTransportCoordinator
    /// Restarts the controls' hide delay.
    let touched: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { (_: TimelineViewDefaultContext) in
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showTimelineRow")
    }

    private var content: some View {
        HStack(spacing: 12) {
            playButton
            VStack(spacing: 2) {
                slider
                positionText
            }
            loopButton
        }
    }

    private var playButton: some View {
        let playing: Bool = transport.isPlaying
        return Button { touched(); transport.togglePlay() } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill").font(.title3)
        }
        .accessibilityLabel(playing ? "Pause" : "Play")
        .accessibilityIdentifier("showTimelinePlay")
    }

    private var spec: AccessibleParameterSpec {
        let total: Double = max(ShowTransportCoordinator.seconds(transport.timeline.duration), 1)
        return AccessibleParameterSpec(id: "showTimelineScrub", label: "Show position", range: 0...total,
                                       step: ShowTransportCoordinator.stepSeconds, unit: .seconds)
    }

    private var slider: some View {
        let spec: AccessibleParameterSpec = self.spec
        let transport: ShowTransportCoordinator = self.transport
        let shown: Double = transport.displayedTime().map(ShowTransportCoordinator.seconds) ?? 0
        let value: Binding<Double> = Binding<Double>(
            get: { () -> Double in shown },
            set: { (seconds: Double) -> Void in transport.scrub(toSeconds: seconds) })
        let target = ParameterTarget(
            get: { () -> Double in transport.currentTime().map(ShowTransportCoordinator.seconds) ?? 0 },
            set: { (seconds: Double) -> Void in transport.seek(toSeconds: seconds) })
        return Slider(value: value, in: spec.range) { (editing: Bool) -> Void in
            touched()
            if editing { transport.beginScrub() } else { transport.endScrub() }
        }
        .accessibleParameter(spec, target: target, didStep: touched)
    }

    private var positionText: some View {
        Text(transport.positionText())
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("showTimelinePosition")
    }

    private var loopButton: some View {
        let on: Bool = transport.loops
        let available: Bool = transport.timeline.canLoop
        return Button { touched(); transport.setLoops(!on) } label: {
            Image(systemName: "repeat").font(.title3)
        }
        .tint(on ? .yellow : nil)
        .disabled(!available && !on)
        .accessibilityLabel("Loop show")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityHint(available ? "" : "Loop needs every cue timed")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("showTimelineLoop")
    }
}
