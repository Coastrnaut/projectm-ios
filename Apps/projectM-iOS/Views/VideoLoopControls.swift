// VideoLoopControls.swift — the stored video's loop region in Settings → Video (MED-003-R9, R10;
// spec Clarifications 2026-11-14).
//
// * In and Out sliders from 0 to the video's duration in 0.1 s steps, each with its time ("1.5 s";
//   VoiceOver "1.5 seconds"), and Reset Loop while a region is saved. Shown only once the layer has
//   reported the duration (the copy opened).
// * A slider change is saved at once (VideoCoordinator clamps it: at least 0.25 s, inside the file)
//   and reaches the player when the drag ends (`commitLoop`) or 0.4 s after the last change.
// * Title and time sit side by side, or stacked when they do not fit (ACC-006-R1); no animation.
// Bodies are kept small (CI's Xcode 26 type-checks each one separately).
import SwiftUI
import VideoLayer

struct VideoLoopControls: View {
    let videos: VideoCoordinator
    /// SCN-010-R4: a drag is one undo step.
    var endCoalescing: () -> Void = {}

    var body: some View {
        if let loop = videos.effectiveLoop, let duration = videos.durationNanoseconds {
            VideoLoopSlider(title: "Loop in", id: "videoLoopIn", seconds: Self.seconds(loop.inNanoseconds),
                            maximum: Self.seconds(duration), set: { (value: Double) -> Void in videos.setLoop(inSeconds: value) },
                            commit: commit)
            VideoLoopSlider(title: "Loop out", id: "videoLoopOut", seconds: Self.seconds(loop.outNanoseconds),
                            maximum: Self.seconds(duration), set: { (value: Double) -> Void in videos.setLoop(outSeconds: value) },
                            commit: commit)
            if videos.hasLoopRegion {
                Button("Reset Loop") { videos.resetLoop() }
                    .accessibilityIdentifier("videoLoopReset")
            }
        }
    }

    private func commit() {
        videos.commitLoop()
        endCoalescing()
    }

    static func seconds(_ nanoseconds: Int64) -> Double {
        let milliseconds: Double = Double(nanoseconds / 1_000_000)
        return milliseconds / 1000
    }

    /// "1.5" (one decimal; two when the value is not on a tenth).
    static func number(_ seconds: Double) -> String {
        let tenths: Double = (seconds * 10).rounded()
        let onTenth: Bool = abs(tenths / 10 - seconds) < 0.0005
        let digits: Int = onTenth ? 1 : 2
        return seconds.formatted(.number.precision(.fractionLength(digits)))
    }

    /// "1.5 s" (shown).
    static func shortText(_ seconds: Double) -> String {
        let value: String = number(seconds)
        return value + " s"
    }

    /// "1.5 seconds" (VoiceOver).
    static func spokenText(_ seconds: Double) -> String {
        let value: String = number(seconds)
        return value + " seconds"
    }
}

/// One loop point: title and time, then the slider.
private struct VideoLoopSlider: View {
    let title: String
    let id: String
    let seconds: Double
    let maximum: Double
    let set: (Double) -> Void
    let commit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            slider
        }
    }

    private var header: some View {
        let time: String = VideoLoopControls.shortText(seconds)
        return ViewThatFits(in: .horizontal) {
            HStack {
                Text(title)
                Spacer()
                Text(time).monospacedDigit().foregroundStyle(.secondary)
            }
            VStack(alignment: .leading) {
                Text(title)
                Text(time).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }

    private var slider: some View {
        let binding = Binding<Double>(get: { () -> Double in seconds }, set: { (value: Double) -> Void in set(value) })
        let upper: Double = max(maximum, 0.1)
        let spoken: String = VideoLoopControls.spokenText(seconds)
        return Slider(value: binding, in: 0...upper, step: 0.1) { (editing: Bool) in
            if !editing { commit() }
        }
        .accessibilityLabel(title)
        .accessibilityValue(spoken)
        .accessibilityIdentifier(id)
    }
}
