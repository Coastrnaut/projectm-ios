// ShowKeyframeTracksView.swift — SHOW-008 Settings → Show → Keyframe Tracks (specs/246-show-008-keyframe-tracks; R8;
// contract K6, K7).
//
// * The playhead (SHOW-007's position, 0:00 at Standby), Add Track (the targets without a track), and per track a section
//   with its keyframes in time order ("0:30, 0.90, Linear"; VoiceOver reads the same), Add Keyframe at Playhead and
//   Delete Track. A keyframe opens `ShowKeyframeEditView`: an ACC-005 slider over the parameter's range (numbers) or the
//   system colour picker (colours), the interpolation to the next keyframe, and Delete Keyframe.
// * SCN-015-R6: while the scene is locked the edit controls are disabled and the lock note is shown; the list stays.
// A standard List, so Dynamic Type, VoiceOver and Full Keyboard Access apply (FR-070).
import ShowControl
import SwiftUI

struct ShowKeyframeTracksView: View {
    let keyframes: ShowKeyframeCoordinator

    private var locked: Bool { keyframes.isEditLocked }

    var body: some View {
        List {
            if locked { Section { SceneLockNote() } }
            headerSection
            ForEach(keyframes.tracks.tracks) { (track: ShowKeyframeTrack) in
                trackSection(track)
            }
        }
        .navigationTitle("Keyframe Tracks")
        .accessibilityIdentifier("showKeyframeTracks")
    }

    private var headerSection: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 0.5)) { (_: TimelineViewDefaultContext) in
                Text("Playhead " + ShowKeyframeCoordinator.timeText(keyframes.playheadMilliseconds))
                    .accessibilityIdentifier("showKeyframePlayhead")
            }
            addTrackMenu
        } footer: {
            Text("A track changes one value along the show timeline. Keyframes are added at the playhead; move it with the show's timeline.")
        }
    }

    private var addTrackMenu: some View {
        Menu {
            ForEach(keyframes.unusedTargets) { (target: ShowKeyframeTarget) in
                Button(target.name) { keyframes.addTrack(target) }
            }
        } label: {
            Text("Add Track…")
        }
        .disabled(locked || keyframes.unusedTargets.isEmpty || keyframes.tracks.tracks.count >= ShowKeyframeTracks.maximumTracks)
        .accessibilityIdentifier("showKeyframeAddTrack")
    }

    private func trackName(_ track: ShowKeyframeTrack) -> String {
        keyframes.target(for: track.parameter)?.name ?? (track.parameter.rawValue + " (not available)")
    }

    private func trackSection(_ track: ShowKeyframeTrack) -> some View {
        Section(trackName(track)) {
            ForEach(track.keyframes, id: \.time) { (keyframe: ShowKeyframe) in
                keyframeRow(track, keyframe)
            }
            Button("Add Keyframe at Playhead") { keyframes.addKeyframeAtPlayhead(track: track.id) }
                .disabled(locked || keyframes.target(for: track.parameter) == nil)
                .accessibilityIdentifier("showKeyframeAddKey")
            Button("Delete Track", role: .destructive) { keyframes.removeTrack(track.id) }
                .disabled(locked)
                .accessibilityIdentifier("showKeyframeDeleteTrack")
        }
    }

    private func keyframeRow(_ track: ShowKeyframeTrack, _ keyframe: ShowKeyframe) -> some View {
        let text: String = ShowKeyframeCoordinator.rowText(keyframe)
        return NavigationLink {
            ShowKeyframeEditView(keyframes: keyframes, trackID: track.id, time: keyframe.time)
        } label: {
            Text(text)
        }
        .disabled(locked || keyframes.target(for: track.parameter) == nil)
        .accessibilityLabel(text)
        .accessibilityIdentifier("showKeyframeRow")
    }
}

/// One keyframe: value, interpolation, delete.
struct ShowKeyframeEditView: View {
    let keyframes: ShowKeyframeCoordinator
    let trackID: UUID
    let time: Int
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Double?

    private var track: ShowKeyframeTrack? { keyframes.tracks.track(trackID) }
    private var keyframe: ShowKeyframe? { track?.keyframes.first { (k: ShowKeyframe) -> Bool in k.time == time } }
    private var target: ShowKeyframeTarget? { track.flatMap { (t: ShowKeyframeTrack) -> ShowKeyframeTarget? in keyframes.target(for: t.parameter) } }

    var body: some View {
        Form {
            if let keyframe, let target {
                Section(target.name + " at " + ShowKeyframeCoordinator.timeText(time)) {
                    valueEditor(keyframe, target)
                }
                Section("To the next keyframe") { interpolationPicker(keyframe) }
                Section {
                    Button("Delete Keyframe", role: .destructive) {
                        if keyframes.removeKeyframe(track: trackID, time: time) { dismiss() }
                    }
                    .accessibilityIdentifier("showKeyframeDelete")
                }
            } else {
                Text("The keyframe no longer exists.")
            }
        }
        .disabled(keyframes.isEditLocked)
        .navigationTitle("Keyframe")
    }

    @ViewBuilder
    private func valueEditor(_ keyframe: ShowKeyframe, _ target: ShowKeyframeTarget) -> some View {
        switch (target.kind, keyframe.value) {
        case let (.number(range, step), .number(stored)):
            numberEditor(stored: stored, range: range, step: step, label: target.name)
        case let (.color, .color(color)):
            ColorPicker("Colour", selection: colorBinding(color), supportsOpacity: true)
                .accessibilityIdentifier("showKeyframeColor")
            Text(ShowKeyframeCoordinator.colorText(color))
        default:
            Text("This keyframe's value does not fit its parameter.")
        }
    }

    private func numberEditor(stored: Double, range: ClosedRange<Double>, step: Double, label: String) -> some View {
        let shown: Double = draft ?? stored
        let spec = AccessibleParameterSpec(id: "showKeyframeValue", label: label, range: range, step: step, unit: .number(decimals: 2))
        let target = ParameterTarget(get: { () -> Double in stored },
                                     set: { (value: Double) -> Void in commitNumber(value) })
        let binding = Binding<Double>(get: { () -> Double in draft ?? stored }, set: { (value: Double) -> Void in draft = value })
        return VStack(alignment: .leading) {
            Text(shown.formatted(.number.precision(.fractionLength(2)))).accessibilityHidden(true)
            Slider(value: binding, in: range) { (editing: Bool) -> Void in
                if !editing, let value = draft { commitNumber(value) }
            }
            .accessibleParameter(spec, target: target)
        }
    }

    private func commitNumber(_ value: Double) {
        keyframes.setValue(.number(value), track: trackID, time: time)
        draft = nil
    }

    private func colorBinding(_ color: ShowKeyframeColor) -> Binding<CGColor> {
        Binding<CGColor>(
            get: { () -> CGColor in
                CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
            },
            set: { (picked: CGColor) -> Void in
                guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
                      let converted = picked.converted(to: srgb, intent: .defaultIntent, options: nil),
                      let parts = converted.components, parts.count >= 4 else { return }
                func unit(_ v: CGFloat) -> Double { min(max(Double(v), 0), 1) }
                guard let next = ShowKeyframeColor(red: unit(parts[0]), green: unit(parts[1]), blue: unit(parts[2]), alpha: unit(parts[3])) else { return }
                keyframes.setValue(.color(next), track: trackID, time: time)
            })
    }

    private func interpolationPicker(_ keyframe: ShowKeyframe) -> some View {
        let binding = Binding<ShowKeyframeInterpolation>(
            get: { () -> ShowKeyframeInterpolation in keyframe.interpolation },
            set: { (value: ShowKeyframeInterpolation) -> Void in keyframes.setInterpolation(value, track: trackID, time: time) })
        return Picker("Interpolation", selection: binding) {
            ForEach(ShowKeyframeInterpolation.allCases, id: \.self) { (value: ShowKeyframeInterpolation) in
                Text(value.displayName).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("showKeyframeInterpolation")
    }
}
