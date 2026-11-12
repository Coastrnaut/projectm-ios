// TransportBar.swift — the transport of In-App Playback (AUD-006-T27; AUD-006-R24 to R27;
// specs/007-aud-006-seekable-transport/contracts/ui-strings.md): the track title, a scrubber with
// the elapsed and the remaining time, and Previous track, Play or Pause playback, Stop playback
// and Next track. The app shows it inside the visualizer controls, for In-App Playback only; this
// view holds no playback state. It polls `position` four times per second while it is on screen.
//
// Scrubbing: while the scrubber is dragged the times follow the finger at once, playback follows
// with at most 10 seeks per second (`ScrubThrottle`), and the release seeks to the exact final
// value. A value set without a drag (an assistive technology, a UI test) seeks directly.
// VoiceOver: the scrubber is "Playback position", its value is "‹elapsed› of ‹length›", and the
// increment and decrement gestures move it by 10 seconds.
#if canImport(SwiftUI)
import CaptureKit
import Foundation
import SwiftUI

public struct TransportBar: View {
    public let title: String
    public let isPlaying: Bool
    /// Where playback is now; asked on every refresh.
    public let position: @MainActor () -> PlaybackPosition
    public let onPlayPause: () -> Void
    public let onStop: () -> Void
    public let onPrevious: () -> Void
    public let onNext: () -> Void
    /// Seek to this many seconds (already limited to the track).
    public let onSeek: (Double) -> Void

    /// The scrubber's value while it is dragged; nil otherwise.
    @State private var dragValue: Double?
    @State private var isDragging = false
    @State private var throttle = ScrubThrottle()
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(title: String, isPlaying: Bool, position: @escaping @MainActor () -> PlaybackPosition,
                onPlayPause: @escaping () -> Void, onStop: @escaping () -> Void, onPrevious: @escaping () -> Void,
                onNext: @escaping () -> Void, onSeek: @escaping (Double) -> Void) {
        self.title = title
        self.isPlaying = isPlaying
        self.position = position
        self.onPlayPause = onPlayPause
        self.onStop = onStop
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onSeek = onSeek
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            content(position())
        }
    }

    @ViewBuilder
    private func content(_ current: PlaybackPosition) -> some View {
        let duration = current.durationSeconds
        let shown = min(dragValue ?? current.seconds, duration)
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("transportTitle")
            if typeSize.isAccessibilitySize {
                // Large text: the times get their own row, so neither is cut off (AUD-006-R26).
                scrubber(shown: shown, duration: duration)
                HStack {
                    elapsed(shown)
                    Spacer(minLength: 8)
                    remaining(shown, duration: duration)
                }
            } else {
                HStack(spacing: 8) {
                    elapsed(shown)
                    scrubber(shown: shown, duration: duration)
                    remaining(shown, duration: duration)
                }
            }
            HStack(spacing: 0) {
                button(UIStrings.previousTrack, icon: "backward.end.fill", id: "transportPrevious", action: onPrevious)
                button(UIStrings.transportPlayPause(isPlaying: isPlaying), icon: isPlaying ? "pause.circle.fill" : "play.circle.fill",
                       id: "transportPlayPause", action: onPlayPause)
                button(UIStrings.transportStop, icon: "stop.circle", id: "transportStop", action: onStop)
                button(UIStrings.nextTrack, icon: "forward.end.fill", id: "transportNext", action: onNext)
            }
            .font(.title2)
        }
    }

    private func elapsed(_ seconds: Double) -> some View {
        Text(UIStrings.elapsedTime(seconds))
            .font(.caption)
            .monospacedDigit()
            .accessibilityHidden(true)             // the scrubber's value says it
            .accessibilityIdentifier("transportElapsed")
    }

    private func remaining(_ seconds: Double, duration: Double) -> some View {
        Text(UIStrings.remainingTime(elapsed: seconds, duration: duration))
            .font(.caption)
            .monospacedDigit()
            .accessibilityHidden(true)
            .accessibilityIdentifier("transportRemaining")
    }

    private func scrubber(shown: Double, duration: Double) -> some View {
        Slider(value: Binding(get: { shown }, set: { scrubbed(to: $0) }), in: 0...max(duration, 0.001)) { editing in
            if editing {
                isDragging = true
                throttle.reset()
            } else {
                isDragging = false
                if let final = dragValue { onSeek(final) }      // the release always seeks, exactly
                dragValue = nil
            }
        }
        .disabled(duration <= 0)
        .accessibilityLabel(Text(UIStrings.transportScrubber))
        .accessibilityValue(Text(UIStrings.scrubberValue(elapsed: shown, duration: duration)))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? UIStrings.scrubStepSeconds : -UIStrings.scrubStepSeconds
            onSeek(min(max(0, shown + step), duration))
        }
        .accessibilityIdentifier("transportScrubber")
    }

    private func scrubbed(to value: Double) {
        guard isDragging else {
            onSeek(value)                                        // set without a drag
            return
        }
        dragValue = value
        if throttle.shouldSeek(at: ProcessInfo.processInfo.systemUptime) { onSeek(value) }
    }

    private func button(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(maxWidth: .infinity, minHeight: 36)
        }
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(id)
    }
}
#endif
