// KenBurnsSection.swift — the photo's Ken Burns pan and zoom in Settings → Photo (MED-007-R7, R11; research MED-007-D9).
//
// * A "Ken Burns" section under the photo and the slideshow: the switch with its summary ("Zoom in, 10 s"), then the
//   Movement picker (Zoom in, Zoom out, Pan left to right, Pan right to left, Custom), for Custom the Start and End
//   framing (Zoom 100…400 %, Horizontal and Vertical position 0…100 %), Duration (2…60 s) and Easing.
// * Every slider uses ACC-005's accessible-parameter behaviour (named, valued, adjustable; a drag is one undo step).
// * With Reduce Motion on, a note says the photo stays at its start framing. No animation of its own.
// Strings are built in typed steps; bodies are kept small (CI's Xcode 26 type-checks each one).
import Compositor
import SwiftUI

struct KenBurnsSection: View {
    let kenBurns: KenBurnsCoordinator
    let reduceMotion: Bool
    /// SCN-010-R4: a slider drag is one undo step.
    var endCoalescing: @MainActor () -> Void = { () -> Void in }

    static let reduceMotionNote = "Reduce Motion is on: the photo stays at its start framing."
    static let footer = "Ken Burns slowly pans and zooms the photo from a start framing to an end framing, then holds. In a slideshow every picture moves for as long as it is shown."

    var body: some View {
        Section {
            KenBurnsSwitch(kenBurns: kenBurns)
            if kenBurns.isEnabled {
                KenBurnsControls(kenBurns: kenBurns, endCoalescing: endCoalescing)
            }
            if kenBurns.isEnabled && reduceMotion {
                Text(Self.reduceMotionNote)
                    .font(.footnote)
                    .accessibilityIdentifier("kenBurnsReduceMotionNote")
            }
        } header: {
            Text("Ken Burns")
        } footer: {
            Text(Self.footer)
        }
    }
}

/// The on/off switch with its summary.
private struct KenBurnsSwitch: View {
    let kenBurns: KenBurnsCoordinator

    var body: some View {
        let binding = Binding<Bool>(get: { () -> Bool in kenBurns.isEnabled },
                                    set: { (on: Bool) -> Void in kenBurns.setEnabled(on) })
        return Toggle(isOn: binding) {
            VStack(alignment: .leading) {
                Text("Ken Burns")
                Text(kenBurns.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("kenBurnsSummary")
            }
        }
        .accessibilityIdentifier("kenBurnsToggle")
    }
}

/// Movement, the custom framing, duration and easing.
private struct KenBurnsControls: View {
    let kenBurns: KenBurnsCoordinator
    let endCoalescing: @MainActor () -> Void

    var body: some View {
        movementPicker
        if kenBurns.preset == .custom {
            KenBurnsFramingControls(kenBurns: kenBurns, end: .start, endCoalescing: endCoalescing)
            KenBurnsFramingControls(kenBurns: kenBurns, end: .end, endCoalescing: endCoalescing)
        }
        KenBurnsSlider(spec: KenBurnsSliderSpecs.duration, value: Double(kenBurns.durationSeconds), text: durationText,
                       set: { (v: Double) -> Void in kenBurns.setDurationSeconds(Int(v.rounded())) }, endCoalescing: endCoalescing)
        easingPicker
    }

    private var durationText: String { String(kenBurns.durationSeconds) + " s" }

    private var movementPicker: some View {
        let binding = Binding<KenBurnsPreset>(get: { () -> KenBurnsPreset in kenBurns.preset },
                                              set: { (p: KenBurnsPreset) -> Void in kenBurns.setPreset(p) })
        return Picker("Movement", selection: binding) {
            ForEach(KenBurnsPreset.allCases, id: \.self) { (p: KenBurnsPreset) in
                Text(KenBurnsCoordinator.title(p)).tag(p)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("kenBurnsMovementPicker")
    }

    private var easingPicker: some View {
        let binding = Binding<KenBurnsEasing>(get: { () -> KenBurnsEasing in kenBurns.draft.easing },
                                              set: { (e: KenBurnsEasing) -> Void in kenBurns.setEasing(e) })
        return Picker("Easing", selection: binding) {
            ForEach(KenBurnsEasing.allCases, id: \.self) { (e: KenBurnsEasing) in
                Text(KenBurnsCoordinator.title(e)).tag(e)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("kenBurnsEasingPicker")
    }
}

/// The accessible slider specs (ACC-005).
@MainActor
enum KenBurnsSliderSpecs {
    static let duration = AccessibleParameterSpec(id: "kenBurnsDurationSlider", label: "Duration",
                                                  range: Double(KenBurnsMotion.durationRangeMilliseconds.lowerBound / 1_000)...Double(KenBurnsMotion.durationRangeMilliseconds.upperBound / 1_000),
                                                  step: 1, unit: .seconds)

    static func zoom(_ end: KenBurnsEnd) -> AccessibleParameterSpec {
        AccessibleParameterSpec(id: "kenBurns" + suffix(end) + "Zoom", label: label(end) + " zoom",
                                range: KenBurnsCoordinator.zoomRange, step: 0.05, unit: .multiplier)
    }

    static func horizontal(_ end: KenBurnsEnd) -> AccessibleParameterSpec {
        AccessibleParameterSpec(id: "kenBurns" + suffix(end) + "Horizontal", label: label(end) + " horizontal position",
                                range: 0...1, step: 0.05, unit: .percent(decimals: 0))
    }

    static func vertical(_ end: KenBurnsEnd) -> AccessibleParameterSpec {
        AccessibleParameterSpec(id: "kenBurns" + suffix(end) + "Vertical", label: label(end) + " vertical position",
                                range: 0...1, step: 0.05, unit: .percent(decimals: 0))
    }

    private static func suffix(_ end: KenBurnsEnd) -> String { end == .start ? "Start" : "End" }
    private static func label(_ end: KenBurnsEnd) -> String { end == .start ? "Start" : "End" }
}

/// One end's zoom and position (Custom).
private struct KenBurnsFramingControls: View {
    let kenBurns: KenBurnsCoordinator
    let end: KenBurnsEnd
    let endCoalescing: @MainActor () -> Void

    private var rect: KenBurnsRect { kenBurns.rect(end) }

    var body: some View {
        KenBurnsSlider(spec: KenBurnsSliderSpecs.zoom(end), value: rect.zoom, text: zoomText,
                       set: { (v: Double) -> Void in kenBurns.setZoom(v, of: end) }, endCoalescing: endCoalescing)
        KenBurnsSlider(spec: KenBurnsSliderSpecs.horizontal(end), value: rect.position.x, text: percent(rect.position.x),
                       set: { (v: Double) -> Void in kenBurns.setPosition(x: v, of: end) }, endCoalescing: endCoalescing)
        KenBurnsSlider(spec: KenBurnsSliderSpecs.vertical(end), value: rect.position.y, text: percent(rect.position.y),
                       set: { (v: Double) -> Void in kenBurns.setPosition(y: v, of: end) }, endCoalescing: endCoalescing)
    }

    private var zoomText: String {
        let p: Int = Int((rect.zoom * 100).rounded())
        return String(p) + " %"
    }

    private func percent(_ v: Double) -> String {
        let p: Int = Int((v * 100).rounded())
        return String(p) + " %"
    }
}

/// A labelled slider with ACC-005's accessible-parameter behaviour.
private struct KenBurnsSlider: View {
    let spec: AccessibleParameterSpec
    let value: Double
    let text: String
    let set: @MainActor (Double) -> Void
    let endCoalescing: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            slider
        }
    }

    private var header: some View {
        HStack {
            Text(spec.label)
            Spacer()
            Text(text).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private var slider: some View {
        let current: Double = value
        let apply: @MainActor (Double) -> Void = set
        let target = ParameterTarget(get: { () -> Double in current }, set: { (v: Double) -> Void in apply(v) })
        let binding = Binding<Double>(get: { () -> Double in current }, set: { (v: Double) -> Void in apply(v) })
        return Slider(value: binding, in: spec.range, step: spec.step) { (editing: Bool) in
            if !editing { endCoalescing() }
        }
        .accessibleParameter(spec, target: target, didStep: endCoalescing)
    }
}
