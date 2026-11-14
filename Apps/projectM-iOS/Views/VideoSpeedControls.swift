// VideoSpeedControls.swift — the stored video's playback speed in Settings → Video (MED-004-R8; spec
// Clarifications 2026-11-14; research MED-004-D7).
//
// * One menu `Picker` "Speed" with the seven safe speeds ("0.25×" … "2×"), shown whenever a video is
//   stored (speed does not need the duration). VoiceOver reads each value in words ("Half speed",
//   "1.5 times"). A pick is saved and applied at once (VideoCoordinator.setSpeed) and is one undo step.
// * Speed changes only the video layer; the music and the spectrum never change speed.
// * A menu picker wraps at accessibility text sizes (ACC-006) and has no animation of its own.
// Strings are built in typed steps; bodies are kept small (CI's Xcode 26 type-checks each one).
import SwiftUI
import VideoLayer

struct VideoSpeedControls: View {
    let videos: VideoCoordinator

    var body: some View {
        if videos.video != nil {
            Picker(selection: binding) {
                ForEach(VideoPlaybackSpeed.all, id: \.percent) { (speed: VideoPlaybackSpeed) in
                    VideoSpeedOption(speed: speed)
                }
            } label: {
                Text("Speed")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("videoSpeedPicker")
            .accessibilityValue(Self.spokenText(videos.speed))
        }
    }

    private var binding: Binding<Int> {
        Binding<Int>(get: { () -> Int in videos.speed.percent },
                     set: { (percent: Int) -> Void in
                         guard let speed = VideoPlaybackSpeed(percent: percent) else { return }
                         videos.setSpeed(speed)
                     })
    }

    /// "0.5×" (shown).
    static func shortText(_ speed: VideoPlaybackSpeed) -> String {
        let value: Double = Double(speed.percent) / 100
        let digits: Int = speed.percent % 100 == 0 ? 0 : (speed.percent % 10 == 0 ? 1 : 2)
        let number: String = value.formatted(.number.precision(.fractionLength(digits)))
        return number + "×"
    }

    /// "Half speed", "Normal speed", "1.5 times" (VoiceOver).
    static func spokenText(_ speed: VideoPlaybackSpeed) -> String {
        switch speed.percent {
        case 25: return "Quarter speed"
        case 50: return "Half speed"
        case 75: return "Three-quarter speed"
        case 100: return "Normal speed"
        case 200: return "Double speed"
        default:
            let value: Double = Double(speed.percent) / 100
            let number: String = value.formatted(.number.precision(.fractionLength(0...2)))
            return number + " times"
        }
    }
}

/// One option of the Speed picker: the short text, read in words.
private struct VideoSpeedOption: View {
    let speed: VideoPlaybackSpeed

    var body: some View {
        let shown: String = VideoSpeedControls.shortText(speed)
        let spoken: String = VideoSpeedControls.spokenText(speed)
        return Text(shown)
            .accessibilityLabel(spoken)
            .tag(speed.percent)
    }
}
