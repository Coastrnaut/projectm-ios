// MIDIMappingOptionsView.swift — one MIDI mapping's curve and inversion (MIDI-004-R7, R8; specs/140-midi-004-cc-scaling,
// contract C4.3). Opened from the "Curve" row under a mapped parameter in MIDI Mappings: a curve picker (Linear, Ease
// in, Ease out, Logarithmic; "Custom" only for another stored curve), an Invert switch, a static preview drawn from
// the same position function the values use, and the unreadable-curve notice. Changes save at once and are
// announced by the coordinator through the shared announcer (never posted here). No animation. Small views so each
// body stays under CI's type-check budget.
import ParameterGraph
import PerformanceControl
import SwiftUI

struct MIDIMappingOptionsView: View {
    var mappings: MIDIMappingCoordinator
    let parameter: ParameterID
    let name: String

    var body: some View {
        Form {
            if let options = mappings.options(for: parameter) {
                MIDICurvePickerSection(mappings: mappings, parameter: parameter, options: options)
                MIDIInvertSection(mappings: mappings, parameter: parameter, options: options)
                MIDICurvePreviewSection(options: options)
            } else {
                Text("Not mapped").accessibilityIdentifier("midiOptionsNotMapped")
            }
        }
        .navigationTitle(name)
    }
}

private struct MIDICurvePickerSection: View {
    var mappings: MIDIMappingCoordinator
    let parameter: ParameterID
    let options: MIDIMappingOptions

    private var selection: Binding<MIDICurvePreset?> {
        Binding<MIDICurvePreset?>(
            get: { () -> MIDICurvePreset? in options.preset },
            set: { (preset: MIDICurvePreset?) -> Void in
                guard let preset else { return }
                mappings.selectPreset(preset, for: parameter)
            })
    }

    var body: some View {
        Section {
            Picker("Curve", selection: selection) {
                ForEach(MIDICurvePreset.allCases, id: \.self) { (preset: MIDICurvePreset) in
                    Text(preset.title).tag(Optional(preset))
                }
                if options.preset == nil {
                    Text("Custom").tag(Optional<MIDICurvePreset>.none)
                }
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("midiCurvePicker")
            if options.hasUnreadableCurve {
                Label(MIDIMappingCoordinator.unreadableCurveText, systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("midiCurveNotice")
            }
        } footer: {
            Text("The curve shapes how the value follows the control between its ends. Both ends always reach the setting's minimum and maximum.")
        }
    }
}

private struct MIDIInvertSection: View {
    var mappings: MIDIMappingCoordinator
    let parameter: ParameterID
    let options: MIDIMappingOptions

    private var inverted: Binding<Bool> {
        Binding<Bool>(
            get: { () -> Bool in options.inverted },
            set: { (value: Bool) -> Void in mappings.setInverted(value, for: parameter) })
    }

    var body: some View {
        Section {
            Toggle("Invert", isOn: inverted)
                .accessibilityIdentifier("midiInvert")
        } footer: {
            Text("Inverted, the control's lowest position gives the maximum and its highest the minimum. Changes apply the next time the control moves.")
        }
    }
}

private struct MIDICurvePreviewSection: View {
    let options: MIDIMappingOptions

    var body: some View {
        Section("Preview") {
            MIDICurvePreview(options: options)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.description(options))
                .accessibilityIdentifier("midiCurvePreview")
        }
    }

    /// "Curve preview: Ease in, inverted. Turning the control up lowers the value from maximum to minimum."
    static func description(_ options: MIDIMappingOptions) -> String {
        let direction: String = options.inverted
            ? "Turning the control up lowers the value from maximum to minimum."
            : "Turning the control up raises the value from minimum to maximum."
        return "Curve preview: " + options.summary + ". " + direction
    }
}

/// Value (up) against control position (right), from 33 samples of `MIDIMappingOptions.position`. Static.
private struct MIDICurvePreview: View {
    let options: MIDIMappingOptions
    static let samples: Int = 33
    static let size = CGSize(width: 180, height: 110)

    var body: some View {
        ZStack {
            Rectangle().stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            curvePath.stroke(Color.accentColor, lineWidth: 2)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .padding(.vertical, 8)
    }

    private var curvePath: Path {
        var path = Path()
        let last: Int = Self.samples - 1
        for index in 0...last {
            let x: Double = Double(index) / Double(last)
            let y: Double = options.position(normalized: x)
            let px: CGFloat = CGFloat(x) * Self.size.width
            let py: CGFloat = CGFloat(1 - y) * Self.size.height
            let point = CGPoint(x: px, y: py)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
