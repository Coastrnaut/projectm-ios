// ShowTimelineRow.swift — SHOW-007-R8 the show timeline transport in the cue row (specs/243-show-007-timeline-transport;
// contract T7).
//
// * Shown under the cue row's buttons only when the show has a timeline (a timed cue). Play/Pause (SHOW-005's Hold),
//   the scrub slider, the position ("1:15 / 2:30", or the scrub preview "Cue 3 · Drop at 0:15") and Loop.
// * The slider is an ACC-005 accessible slider (5 s per swipe, each swipe one seek). A drag only moves the preview and
//   commits one seek on release (R4).
// * The row redraws the position twice a second only while it is on screen and not being dragged.
import ShowControl
import SwiftUI

struct ShowTimelineRow: View {
    let transport: ShowTransportCoordinator
    /// Restarts the controls' hide delay.
    let touched: () -> Void

    /// Redraw counter: bumped twice a second while on screen and not scrubbing (a `TimelineView` rebuilt the slider
    /// mid-drag and lost the release).
    @State private var tick = 0

    var body: some View {
        let _: Int = tick
        return content
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("showTimelineRow")
            .task { () async -> Void in await refreshLoop() }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            if !transport.scrub.isScrubbing { tick &+= 1 }
        }
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
        let transport: ShowTransportCoordinator = self.transport
        let target = ParameterTarget(
            get: { () -> Double in transport.currentTime().map(ShowTransportCoordinator.seconds) ?? 0 },
            set: { (seconds: Double) -> Void in transport.seek(toSeconds: seconds) })
        let shown: Double = transport.displayedTime().map(ShowTransportCoordinator.seconds) ?? 0
        return ShowScrubBar(value: shown, range: spec.range, transport: transport, touched: touched)
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

/// SHOW-007-R4: the scrub track. A drag moves only the preview; the end of the drag (released or cancelled, read from a
/// `GestureState` that resets either way) commits one seek. Track and thumb match a system slider's geometry (14 pt
/// inset, 28 pt thumb).
struct ShowScrubBar: View {
    let value: Double
    let range: ClosedRange<Double>
    let transport: ShowTransportCoordinator
    let touched: () -> Void
    @GestureState private var dragging = false

    private static let thumb: CGFloat = 28

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            track(width: proxy.size.width)
        }
        .frame(height: 31)
        .onChange(of: dragging) { (_: Bool, now: Bool) -> Void in
            if !now { transport.endScrub(); touched() }
        }
    }

    private func fraction() -> CGFloat {
        let span: Double = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    private func track(width: CGFloat) -> some View {
        let inset: CGFloat = Self.thumb / 2
        let usable: CGFloat = max(width - Self.thumb, 1)
        let x: CGFloat = inset + fraction() * usable
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.secondary.opacity(0.35)).frame(height: 4).padding(.horizontal, inset)
            Capsule().fill(Color.accentColor).frame(width: max(x - inset, 0), height: 4).offset(x: inset)
            Circle().fill(Color.white).shadow(radius: 1).frame(width: Self.thumb, height: Self.thumb).offset(x: x - inset)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(drag(inset: inset, usable: usable))
    }

    private func drag(inset: CGFloat, usable: CGFloat) -> some Gesture {
        let range: ClosedRange<Double> = self.range
        let transport: ShowTransportCoordinator = self.transport
        return DragGesture(minimumDistance: 0)
            .updating($dragging) { (_: DragGesture.Value, state: inout Bool, _: inout Transaction) -> Void in state = true }
            .onChanged { (drag: DragGesture.Value) -> Void in
                let f: Double = Double(min(max((drag.location.x - inset) / usable, 0), 1))
                transport.scrub(toSeconds: range.lowerBound + f * (range.upperBound - range.lowerBound))
            }
    }
}
