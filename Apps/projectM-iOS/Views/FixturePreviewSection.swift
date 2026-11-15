// FixturePreviewSection.swift — Settings › Noise editor › Fixture preview (SHD-012-R6, R7, R9; contract P4).
//
// The binding (target and source), the fixture seed, Play fixture / Stop, the looping picture, a frame slider and the
// summary ("120 frames · Warp amount 0.00…4.00 · run 1a2b3c4d"). The loop only picks which pre-rendered frame to show
// from a `TimelineView` (no `.animation`); with Reduce Motion on it does not auto-play and the slider scrubs. Bodies
// stay small (Xcode 26 type-check budget).
import ParameterGraph
import ProceduralMaterials
import SwiftUI

struct FixturePreviewSection: View {
    static let footer = "Plays the texture against built-in fixture music with a fixed clock, so the same settings, binding and seed always give the same frames and the same run code."

    let store: FixturePreviewStore
    let noise: NoiseEditorStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        Section {
            FixturePreviewBindingRows(store: store)
            FixturePreviewPicture(store: store)
            playButton
            FixturePreviewFrameSlider(store: store)
            summary
        } header: {
            Text("Fixture preview")
        } footer: {
            Text(Self.footer)
        }
    }

    private var playButton: some View {
        let title: String = store.isPlaying ? "Stop" : (store.phase == .rendering ? "Rendering…" : "Play fixture")
        return Button(title) { () -> Void in
            if store.isPlaying {
                store.stop()
            } else {
                let values: MaterialParameterValues = noise.values
                let autoPlay: Bool = !reduceMotion
                Task { () -> Void in await store.play(values: values, autoPlay: autoPlay) }
            }
        }
        .disabled(store.phase == .rendering)
        .accessibilityIdentifier("fixturePreviewPlay")
        .accessibilityValue("Run \(store.runCount)")
    }

    private var summary: some View {
        Text(store.summary)
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("fixturePreviewSummary")
    }
}

private struct FixturePreviewBindingRows: View {
    @Bindable var store: FixturePreviewStore

    var body: some View {
        Picker("Bound parameter", selection: $store.target) {
            Text("None").tag(ParameterID?.none)
            ForEach(store.targets, id: \.id) { (d: ParameterDescriptor) in
                Text(store.shortName(d.id)).tag(ParameterID?.some(d.id))
            }
        }
        .accessibilityIdentifier("fixturePreviewTarget")
        Picker("Follows", selection: $store.source) {
            ForEach(FixturePreviewSource.allCases) { (s: FixturePreviewSource) in
                Text(s.title).tag(s)
            }
        }
        .accessibilityIdentifier("fixturePreviewSource")
        Stepper("Fixture seed \(store.seed)", value: $store.seed, in: 1...99)
            .accessibilityIdentifier("fixturePreviewSeed")
    }
}

private struct FixturePreviewPicture: View {
    let store: FixturePreviewStore

    var body: some View {
        if store.frames.isEmpty {
            Text(placeholder)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("fixturePreviewPicture")
        } else if store.isPlaying {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { (context: TimelineViewDefaultContext) in
                frame(Self.loopIndex(context.date, count: store.frames.count))
            }
        } else {
            frame(min(store.frameIndex, store.frames.count - 1))
        }
    }

    private var placeholder: String {
        store.phase == .ready ? "The preview needs Metal, which isn't available here." : "Tap Play fixture to render the preview."
    }

    /// Frame of a 30 fps loop at `date` (wall time only picks which recorded frame is shown).
    static func loopIndex(_ date: Date, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let ticks: Double = (date.timeIntervalSinceReferenceDate * 30).rounded(.down)
        return Int(ticks.truncatingRemainder(dividingBy: Double(count)))
    }

    private func frame(_ index: Int) -> some View {
        Image(decorative: store.frames[index], scale: 1)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 192)
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel("Fixture preview")
            .accessibilityValue(store.isPlaying ? "Playing" : "Frame \(index + 1) of \(store.frames.count)")
            .accessibilityIdentifier("fixturePreviewPicture")
    }
}

private struct FixturePreviewFrameSlider: View {
    @Bindable var store: FixturePreviewStore

    var body: some View {
        if store.frames.count > 1 {
            let last: Double = Double(store.frames.count - 1)
            let spec = AccessibleParameterSpec(id: "fixturePreviewFrame", label: "Frame", range: 0...last, step: 1,
                                               unit: .number(decimals: 0))
            let target = ParameterTarget(get: { () -> Double in Double(store.frameIndex) },
                                         set: { (v: Double) -> Void in
                                             store.stop()
                                             store.frameIndex = Int(v.rounded())
                                         })
            let value = Binding<Double>(get: { () -> Double in Double(store.frameIndex) },
                                        set: { (v: Double) -> Void in target.set(v) })
            Slider(value: value, in: spec.range, step: 1)
                .accessibleParameter(spec, target: target)
        }
    }
}
