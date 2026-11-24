// TransportBar.swift — the transport of In-App Playback (AUD-006-T27; AUD-006-R24 to R27;
// specs/007-aud-006-seekable-transport/contracts/ui-strings.md): the track title, a scrubber with
// the elapsed and the remaining time, and Previous track, Play or Pause playback, Stop playback
// and Next track. The app shows it inside the visualizer controls, for In-App Playback only; this
// view holds no playback state. It polls `position` four times per second while it is on screen.
//
// Scrubbing: while the scrubber is dragged the times follow the finger at once, playback follows
// with at most 10 seeks per second (`ScrubThrottle`), and the release seeks to the exact final
// value. A touch on the scrubber without a drag moves playback to that point.
// VoiceOver: the scrubber is "Playback position", its value is "‹elapsed› of ‹length›", and the
// increment and decrement gestures move it by 10 seconds.
//
// AUD-004: with a repeat mode and a cycle action (imported audio only), a Repeat button follows Next
// track: label "Repeat", value the mode, `repeat.1` for One Track and `repeat` dimmed for Off or in
// the accent color for All Tracks; a tap moves to the next mode and VoiceOver announces it.
//
// AUD-005: with a shuffle value and a toggle action (imported audio only), a Shuffle button comes
// before Repeat: label "Shuffle", value "On" or "Off", `shuffle` on a filled accent capsule when On
// and dimmed when Off (not color alone); a tap toggles and VoiceOver announces the new value.
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
    /// AUD-003: opens the queue; nil hides the button (reference track, test signals).
    public let onShowQueue: (() -> Void)?
    /// AUD-004: the queue's repeat mode; nil (or no `onCycleRepeat`) hides the Repeat button.
    public let repeatMode: RepeatMode?
    /// AUD-004: moves the queue to the next repeat mode.
    public let onCycleRepeat: (() -> Void)?
    /// AUD-005: whether the queue is shuffled; nil (or no `onToggleShuffle`) hides the Shuffle button.
    public let isShuffled: Bool?
    /// AUD-005: turns Shuffle on or off.
    public let onToggleShuffle: (() -> Void)?

    /// The scrubber's value while it is touched; nil otherwise.
    @State private var dragValue: Double?
    @State private var throttle = ScrubThrottle()
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(title: String, isPlaying: Bool, position: @escaping @MainActor () -> PlaybackPosition,
                onPlayPause: @escaping () -> Void, onStop: @escaping () -> Void, onPrevious: @escaping () -> Void,
                onNext: @escaping () -> Void, onSeek: @escaping (Double) -> Void, onShowQueue: (() -> Void)? = nil,
                repeatMode: RepeatMode? = nil, onCycleRepeat: (() -> Void)? = nil,
                isShuffled: Bool? = nil, onToggleShuffle: (() -> Void)? = nil) {
        self.title = title
        self.isPlaying = isPlaying
        self.position = position
        self.onPlayPause = onPlayPause
        self.onStop = onStop
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onSeek = onSeek
        self.onShowQueue = onShowQueue
        self.repeatMode = repeatMode
        self.onCycleRepeat = onCycleRepeat
        self.isShuffled = isShuffled
        self.onToggleShuffle = onToggleShuffle
    }

    /// QA-011 D3 (2026-11-24): only the position row (elapsed, scrubber, remaining) is inside the 4 Hz `TimelineView`.
    /// The title and the button rows were rebuilt and laid out again on every poll, the button rows twice since they
    /// sit in a `ViewThatFits`; on the main thread that also drives the Metal visuals, so each poll could delay a frame
    /// on a device with little GPU headroom (D3 iPad A16 with the camera). The tree and identifiers are unchanged.
    public var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)   // ACC-006-R1: a long title wraps at AX sizes
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("transportTitle")
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                positionRow(position())
            }
            buttonRows
        }
    }

    /// The times and the scrubber at `current` (or at the dragged value while the scrubber is touched).
    @ViewBuilder
    private func positionRow(_ current: PlaybackPosition) -> some View {
        let duration = current.durationSeconds
        let shown = min(dragValue ?? current.seconds, duration)
        if typeSize.isAccessibilitySize {
            // Large text: the times get their own row, so neither is cut off (AUD-006-R26).
            VStack(spacing: 6) {
                scrubber(shown: shown, duration: duration)
                HStack {
                    elapsed(shown)
                    Spacer(minLength: 8)
                    remaining(shown, duration: duration)
                }
            }
        } else {
            HStack(spacing: 8) {
                elapsed(shown)
                scrubber(shown: shown, duration: duration)
                remaining(shown, duration: duration)
            }
        }
    }

    private var buttonRows: some View {
        // QA-011 D1 rerun (2026-11-23, AUD-006-T41): at AX5 each icon is about 66 pt wide, so the seven controls of
        // imported audio (with Shuffle, Repeat and Queue) needed about 470 pt in one row. An HStack cannot shrink an
        // image below its size, so the row widened the controls, and with them the whole screen's layout, past a
        // 390 pt iPhone: Queue, half the scrubber and Emergency blackout lay outside the window. The row now
        // moves Shuffle, Repeat and Queue to a second row when one row does not fit (any width, any text size).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                playbackButtons
                queueButtons
            }
            VStack(spacing: 6) {
                HStack(spacing: 0) { playbackButtons }
                if hasQueueButtons {
                    HStack(spacing: 0) { queueButtons }
                }
            }
        }
        .font(.title2)
    }

    /// Previous, Play/Pause, Stop and Next.
    @ViewBuilder private var playbackButtons: some View {
        button(UIStrings.previousTrack, icon: "backward.end.fill", id: "transportPrevious", action: onPrevious)
        button(UIStrings.transportPlayPause(isPlaying: isPlaying), icon: isPlaying ? "pause.circle.fill" : "play.circle.fill",
               id: "transportPlayPause", action: onPlayPause)
        button(UIStrings.transportStop, icon: "stop.circle", id: "transportStop", action: onStop)
        button(UIStrings.nextTrack, icon: "forward.end.fill", id: "transportNext", action: onNext)
    }

    private var hasQueueButtons: Bool {
        (isShuffled != nil && onToggleShuffle != nil) || (repeatMode != nil && onCycleRepeat != nil) || onShowQueue != nil
    }

    /// Shuffle, Repeat and Queue, for imported audio only (AUD-003, AUD-004, AUD-005).
    @ViewBuilder private var queueButtons: some View {
        if let isShuffled, let onToggleShuffle {
            shuffleButton(isShuffled, toggle: onToggleShuffle)
        }
        if let repeatMode, let onCycleRepeat {
            repeatButton(repeatMode, cycle: onCycleRepeat)
        }
        if let onShowQueue {
            button(UIStrings.queue, icon: "list.bullet", id: "transportQueue", action: onShowQueue)
        }
    }

    private func elapsed(_ seconds: Double) -> some View {
        Text(UIStrings.elapsedTime(seconds))
            .font(.caption)
            .monospacedDigit()
            .accessibilityIdentifier("transportElapsed")
    }

    private func remaining(_ seconds: Double, duration: Double) -> some View {
        Text(UIStrings.remainingTime(elapsed: seconds, duration: duration))
            .font(.caption)
            .monospacedDigit()
            .accessibilityIdentifier("transportRemaining")
    }

    /// The scrubber: a track with a thumb. A touch anywhere on it moves playback there; a drag
    /// scrubs. It is drawn and handled here rather than with `Slider`, whose end-of-editing
    /// callback did not arrive reliably for a drag in TransportUITests on the iOS 27.2 simulator
    /// (2026-11-12): the times then stayed at the dragged value while playback went on.
    private func scrubber(shown: Double, duration: Double) -> some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - TransportBar.thumbSize, 1)
            let fraction = duration > 0 ? min(max(shown / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.25)).frame(height: 4)
                Capsule().fill(Color.accentColor).frame(width: TransportBar.thumbSize / 2 + travel * fraction, height: 4)
                Circle().fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    .frame(width: TransportBar.thumbSize, height: TransportBar.thumbSize)
                    .offset(x: travel * fraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard duration > 0 else { return }
                        let value = TransportBar.value(atX: gesture.location.x, travel: travel, duration: duration)
                        if dragValue == nil { throttle.reset() }
                        dragValue = value
                        if throttle.shouldSeek(at: ProcessInfo.processInfo.systemUptime) { onSeek(value) }
                    }
                    .onEnded { gesture in
                        dragValue = nil
                        guard duration > 0 else { return }
                        // The release always seeks, to the exact final value (AUD-006-R12).
                        onSeek(TransportBar.value(atX: gesture.location.x, travel: travel, duration: duration))
                    }
            )
        }
        .frame(height: 32)
        .opacity(duration > 0 ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityLabel(Text(UIStrings.transportScrubber))
        .accessibilityValue(Text(UIStrings.scrubberValue(elapsed: shown, duration: duration)))
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            let step = direction == .increment ? UIStrings.scrubStepSeconds : -UIStrings.scrubStepSeconds
            onSeek(min(max(0, shown + step), duration))
        }
        .accessibilityIdentifier("transportScrubber")
    }

    static let thumbSize: CGFloat = 18

    /// The time at horizontal position `x` of a scrubber whose thumb can travel `travel` points.
    static func value(atX x: CGFloat, travel: CGFloat, duration: Double) -> Double {
        ScrubberGeometry.value(atX: Double(x), thumbSize: Double(thumbSize), travel: Double(travel),
                               duration: duration)
    }

    /// AUD-004-R12: the Repeat control. The icon tells One Track apart; Off is dimmed.
    private func repeatButton(_ mode: RepeatMode, cycle: @escaping () -> Void) -> some View {
        Button {
            cycle()
            AccessibilityNotification.Announcement(UIStrings.repeatAnnouncement(mode.next)).post()
        } label: {
            Image(systemName: UIStrings.repeatIcon(mode))
                .foregroundStyle(mode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .accessibilityLabel(Text(UIStrings.repeatLabel))
        .accessibilityValue(Text(UIStrings.repeatValue(mode)))
        .accessibilityIdentifier("transportRepeat")
    }

    /// AUD-005-R11: the Shuffle control. On is a filled capsule behind the icon, so it does not rely
    /// on color alone; Off is dimmed.
    private func shuffleButton(_ on: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            toggle()
            AccessibilityNotification.Announcement(UIStrings.shuffleAnnouncement(!on)).post()
        } label: {
            Image(systemName: UIStrings.shuffleIcon)
                .font(.title3)
                .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(on ? Color.accentColor : Color.clear))
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .accessibilityLabel(Text(UIStrings.shuffleLabel))
        .accessibilityValue(Text(UIStrings.shuffleValue(on)))
        .accessibilityIdentifier("transportShuffle")
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

/// The scrubber's touch-to-time mapping, outside the SwiftUI guard so it builds and is tested on
/// every platform, Linux included (CI run 43346221995 failed to compile the test there).
enum ScrubberGeometry {
    /// The time for a touch at `x` on a scrubber whose thumb (`thumbSize` wide) travels `travel`
    /// points; touches left or right of the track clamp to the start or the end.
    static func value(atX x: Double, thumbSize: Double, travel: Double, duration: Double) -> Double {
        guard travel > 0, duration > 0 else { return 0 }
        return min(max((x - thumbSize / 2) / travel, 0), 1) * duration
    }
}
