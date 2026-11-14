// ModulationRouteDetailView.swift — MOD-012-R7: one route's details (contract modulation-matrix M5).
//
// Source, destination, mix, ranges, a curve preview (the MOD-004 curve over 0…1), the envelope times and live values
// read at 10 Hz only while the screen is open (the layer's signal and mapped value, the destination's value), and a
// button that opens the UIX-003 inspector for the destination.
import ParameterGraph
import SwiftUI

struct ModulationRouteDetailView: View {
    let binding: AudioFeatureBinding
    let layer: Int
    let coordinator: AppCoordinator
    @State private var inspected: InspectedParameter?

    var body: some View {
        Form {
            routeSection
            curveSection
            envelopeSection
            liveSection
            inspectSection
        }
        .navigationTitle(ModulationRouteText.routeTitle(binding))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("modulationRouteDetail")
        .parameterInspectorSheet($inspected, settings: coordinator.settings, history: coordinator.sceneHistory,
                                 announcer: coordinator.announcer, reading: reading)
    }

    private var reading: (@MainActor (ParameterID) -> ParameterModulationReading?)? {
        let coordinator: AppCoordinator = coordinator
        return { [weak coordinator] (id: ParameterID) -> ParameterModulationReading? in coordinator?.parameterModulationReading(for: id) }
    }

    private var routeSection: some View {
        Section("Route") {
            LabeledContent("Source", value: binding.source.inspectorName)
            LabeledContent("Destination", value: ModulationRouteText.destinationName(binding.target))
            LabeledContent("Layer", value: String(layer + 1))
            LabeledContent("Mix", value: binding.mixMode.rawValue)
            LabeledContent("Output", value: ModulationRouteText.rangeText(binding))
            LabeledContent("Input", value: String(format: "%.3g…%.3g", binding.inputMinimum, binding.inputMaximum))
            LabeledContent("State", value: binding.isEnabled ? "On" : "Off")
        }
    }

    private var curveSection: some View {
        Section("Curve") {
            LabeledContent("Shape", value: ModulationRouteText.curveText(binding.curve))
            ModulationCurvePreview(curve: binding.curve)
                .frame(height: 80)
                .accessibilityLabel("Curve preview: " + ModulationRouteText.curveText(binding.curve))
        }
    }

    private var envelopeSection: some View {
        Section("Envelope") {
            LabeledContent("Attack", value: String(format: "%.2f s", binding.envelope.attackSeconds))
            LabeledContent("Release", value: String(format: "%.2f s", binding.envelope.releaseSeconds))
        }
    }

    private var liveSection: some View {
        Section("Live") {
            TimelineView(.periodic(from: .now, by: ParameterInspectorTiming.refreshSeconds)) { (_: TimelineViewDefaultContext) in
                ModulationLiveRows(reading: coordinator.modulationRouteReading(target: binding.target, layer: layer))
            }
        }
    }

    private var inspectSection: some View {
        Section {
            Button("Inspect " + ModulationRouteText.destinationName(binding.target)) {
                inspected = InspectedParameter.request(binding.target.rawValue)
            }
            .accessibilityIdentifier("modulationInspect")
        }
    }
}

private struct ModulationLiveRows: View {
    let reading: ModulationRouteReading?

    var body: some View {
        if let reading {
            LabeledContent("Signal", value: String(format: "%.2f", reading.signal))
            LabeledContent("Mapped", value: String(format: "%.3f", reading.mapped))
            LabeledContent("Destination", value: String(format: "%.3f", reading.destination))
        } else {
            Text("Live values appear while a native visual is shown.").foregroundStyle(.secondary)
        }
    }
}

/// The curve over 0…1 (input left to right, output bottom to top).
private struct ModulationCurvePreview: View {
    let curve: MappingCurve

    var body: some View {
        Canvas { (context: inout GraphicsContext, size: CGSize) in
            context.stroke(path(in: size), with: .color(.accentColor), lineWidth: 2)
        }
        .background(Color.secondary.opacity(0.1))
    }

    private func path(in size: CGSize) -> Path {
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let x: Double = Double(i) / Double(steps)
            let y: Double = curve.apply(x)
            let point = CGPoint(x: x * Double(size.width), y: (1 - y) * Double(size.height))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
