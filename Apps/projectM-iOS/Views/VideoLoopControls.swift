// VideoLoopControls.swift — the stored video's loop region in Settings → Video (MED-003-R9, R10;
// spec Clarifications 2026-11-14).
//
// * In and Out sliders from 0 to the video's duration in 0.1 s steps, each with its time ("1.5 s";
//   VoiceOver "1.5 seconds"), and Reset Loop while a region is saved. Shown only once the layer has
//   reported the duration (the copy opened).
// * A slider change is saved at once (VideoCoordinator clamps it: at least 0.25 s, inside the file)
//   and reaches the player when the drag ends (`commitLoop`) or 0.4 s after the last change.
// * Title and time sit side by side, or stacked when they do not fit (ACC-006-R1); no animation.
// * ACC-005: VoiceOver reads "1.5 seconds" and swipes move the saved point by 0.1 s; each swipe
//   reaches the player and is one undo step (`commit`).
// Bodies are kept small (CI's Xcode 26 type-checks each one separately).
import SwiftUI
import VideoLayer

struct VideoLoopControls: View {
    let videos: VideoCoordinator
    /// SCN-010-R4: a drag is one undo step.
    var endCoalescing: () -> Void = {}

    var body: some View {
        if let loop = videos.effectiveLoop, let duration = videos.durationNanoseconds {
            let upper: Double = max(Self.seconds(duration), 0.1)
            VideoLoopSlider(spec: AccessibleParameterCatalog.videoLoopIn.withRange(0...upper), title: "Loop in",
                            seconds: Self.seconds(loop.inNanoseconds), target: Self.inTarget(videos), commit: commit)
            VideoLoopSlider(spec: AccessibleParameterCatalog.videoLoopOut.withRange(0...upper), title: "Loop out",
                            seconds: Self.seconds(loop.outNanoseconds), target: Self.outTarget(videos), commit: commit)
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

    /// ACC-005: the saved loop's In point (VideoCoordinator saves and clamps it, MED-003-R9).
    static func inTarget(_ videos: VideoCoordinator) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in seconds(videos.effectiveLoop?.inNanoseconds ?? 0) },
                        set: { (value: Double) -> Void in videos.setLoop(inSeconds: value) })
    }

    /// ACC-005: the saved loop's Out point.
    static func outTarget(_ videos: VideoCoordinator) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in seconds(videos.effectiveLoop?.outNanoseconds ?? 0) },
                        set: { (value: Double) -> Void in videos.setLoop(outSeconds: value) })
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

    /// "1.5 seconds" (VoiceOver; ACC-005's seconds formatter).
    static func spokenText(_ seconds: Double) -> String {
        SpokenValueFormatter.seconds(seconds)
    }
}

/// One loop point: title and time, then the slider.
private struct VideoLoopSlider: View {
    let spec: AccessibleParameterSpec
    let title: String
    let seconds: Double
    let target: ParameterTarget
    let commit: @MainActor () -> Void

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
        let binding = Binding<Double>(get: { () -> Double in seconds }, set: { (value: Double) -> Void in target.set(value) })
        return Slider(value: binding, in: spec.range, step: spec.step) { (editing: Bool) in
            if !editing { commit() }
        }
        .accessibleParameter(spec, target: target, didStep: commit)
    }
}
