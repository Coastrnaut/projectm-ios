// ParticleEmitterEditorView.swift — Settings › Particle emitter (SHD-007-R7, R8, R9; specs/271-shd-007-particle-
// emitter-editor, contract E3).
//
// A "Use on Particle Fountain" switch, a live preview (the fountain's simulation and layout on a fixed 30 fps frame
// clock, `ParticleEmitterPreview`; it plays only while shown and, under Reduce Motion, only by "Step"), Reset to
// defaults, the seed (stepper and New seed), then the spawn shape, rate, velocity, lifetime, gravity and collision
// controls (ACC-005 sliders). Every change is saved at once (`AppSettings.particleEmitter`). Parameters only: no code
// or shader is accepted (SHD-011). Bodies stay small (Xcode 26 type-check budget).
import ProceduralMaterials
import SwiftUI
import VisualGenerators

struct ParticleEmitterLinkSection: View {
    static let footer = "Spawn shape, rate, velocity, lifetime and collision bounds of the Particle Fountain, with a live preview."
    let settings: AppSettings

    var body: some View {
        Section {
            NavigationLink { ParticleEmitterEditorView(settings: settings) } label: { Text("Particle emitter") }
                .accessibilityIdentifier("particleEmitterLink")
        } footer: {
            Text(Self.footer)
        }
    }
}

/// Writes into the stored emitter (clamped; a min slider never passes its max and vice versa).
@MainActor
struct ParticleEmitterEditing {
    let settings: AppSettings

    var values: ParticleEmitterSettings { settings.particleEmitter.settings }

    func update(_ body: (inout ParticleEmitterSettings) -> Void) {
        var choice: ParticleEmitterChoice = settings.particleEmitter
        body(&choice.settings)
        choice.settings = choice.settings.clamped()
        guard choice != settings.particleEmitter else { return }
        settings.particleEmitter = choice
    }

    func binding(_ key: WritableKeyPath<ParticleEmitterSettings, Double>,
                 lowerPartner: WritableKeyPath<ParticleEmitterSettings, Double>? = nil,
                 upperPartner: WritableKeyPath<ParticleEmitterSettings, Double>? = nil) -> Binding<Double> {
        Binding<Double>(get: { () -> Double in values[keyPath: key] },
                        set: { (d: Double) -> Void in
                            update { (s: inout ParticleEmitterSettings) -> Void in
                                s[keyPath: key] = d
                                if let upper = upperPartner, s[keyPath: upper] < d { s[keyPath: upper] = d }
                                if let lower = lowerPartner, s[keyPath: lower] > d { s[keyPath: lower] = d }
                            }
                        })
    }

    func target(_ binding: Binding<Double>) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in binding.wrappedValue },
                        set: { (d: Double) -> Void in binding.wrappedValue = d })
    }
}

/// The editor's slider specs (ACC-005).
enum ParticleEmitterSliders {
    static func spec(_ id: String, _ label: String, _ range: ClosedRange<Double>, _ step: Double,
                     _ unit: SpokenUnit) -> AccessibleParameterSpec {
        AccessibleParameterSpec(id: "particleEmitter" + id, label: label, range: range, step: step, unit: unit)
    }

    typealias S = ParticleEmitterSettings
    static let shapeWidth = spec("ShapeWidth", "Shape width", S.shapeSizeRange, 0.05, .number(decimals: 2))
    static let shapeHeight = spec("ShapeHeight", "Shape height", S.shapeSizeRange, 0.05, .number(decimals: 2))
    static let rate = spec("Rate", "Rate", S.rateRange, 1, .number(decimals: 0))
    static let minimumSpeed = spec("MinimumSpeed", "Minimum speed", S.speedRange, 0.1, .number(decimals: 1))
    static let maximumSpeed = spec("MaximumSpeed", "Maximum speed", S.speedRange, 0.1, .number(decimals: 1))
    static let direction = spec("Direction", "Direction", S.directionRange, 1, .signedDegrees)
    static let spread = spec("Spread", "Spread", S.spreadRange, 1, .degrees)
    static let minimumLifetime = spec("MinimumLifetime", "Minimum lifetime", S.lifetimeRange, 0.1, .seconds)
    static let maximumLifetime = spec("MaximumLifetime", "Maximum lifetime", S.lifetimeRange, 0.1, .seconds)
    static let gravity = spec("Gravity", "Gravity", S.gravityRange, 0.1, .number(decimals: 1))
    static let boxHalfWidth = spec("BoxHalfWidth", "Box half-width", S.boxHalfWidthRange, 0.05, .number(decimals: 2))
    static let boxHeight = spec("BoxHeight", "Box height", S.boxHeightRange, 0.05, .number(decimals: 2))
    static let restitution = spec("Restitution", "Bounce", S.restitutionRange, 0.05, .percent(decimals: 0))
}

/// One labelled slider with its value and the ACC-005 adjustable action.
struct ParticleEmitterSlider: View {
    let spec: AccessibleParameterSpec
    let value: Binding<Double>
    let editing: ParticleEmitterEditing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(spec.label)
                Spacer()
                Text(readout).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityHidden(true)
            Slider(value: value, in: spec.range, step: spec.step)
                .accessibleParameter(spec, target: editing.target(value))
        }
    }

    private var readout: String {
        SpokenValueFormatter.text(value.wrappedValue, unit: spec.unit)
    }
}

struct ParticleEmitterEditorView: View {
    let settings: AppSettings

    private var editing: ParticleEmitterEditing { ParticleEmitterEditing(settings: settings) }

    var body: some View {
        List {
            ParticleEmitterPreviewSection(editing: editing)
            ParticleEmitterShapeSection(editing: editing)
            ParticleEmitterMotionSection(editing: editing)
            ParticleEmitterBoundsSection(editing: editing)
        }
        .navigationTitle("Particle Emitter")
    }
}

private struct ParticleEmitterPreviewSection: View {
    let editing: ParticleEmitterEditing
    @State private var seeds = NoiseSeedSequence()

    var body: some View {
        Section {
            Toggle("Use on Particle Fountain", isOn: enabled)
                .accessibilityIdentifier("particleEmitterEnabled")
            ParticleEmitterPreviewCanvas(settings: editing.values)
            seedRow
            Button("New seed") { () -> Void in newSeed() }
                .accessibilityIdentifier("particleEmitterNewSeed")
            Button("Reset to defaults") { () -> Void in editing.settings.particleEmitter = ParticleEmitterChoice() }
                .accessibilityIdentifier("particleEmitterReset")
        } footer: {
            Text(footer)
        }
    }

    private var enabled: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in editing.settings.particleEmitter.enabled },
                      set: { (on: Bool) -> Void in editing.settings.particleEmitter.enabled = on })
    }

    private var seed: Binding<Int> {
        Binding<Int>(get: { () -> Int in Int(min(editing.values.seed, 65_535)) },
                     set: { (n: Int) -> Void in editing.update { (s: inout ParticleEmitterSettings) -> Void in s.seed = UInt64(n) } })
    }

    private var seedRow: some View {
        Stepper(value: seed, in: 0...65_535) {
            Text("Seed \(seed.wrappedValue)")
        }
        .accessibilityIdentifier("particleEmitterSeed")
    }

    private func newSeed() {
        let next: Int = seeds.next(after: seed.wrappedValue)
        seed.wrappedValue = next
    }

    private var footer: String {
        let count: Int = Int(editing.values.steadyStateCount.rounded())
        let base: String = "The same seed always gives the same run. About \(count) particles at once"
        guard count > ParticleFountainConfiguration.capacity else { return base + "." }
        return base + "; the fountain holds \(ParticleFountainConfiguration.capacity), so the rest are skipped."
    }
}

private struct ParticleEmitterShapeSection: View {
    let editing: ParticleEmitterEditing

    var body: some View {
        Section("Spawn") {
            Picker("Shape", selection: shape) {
                ForEach(ParticleEmitterSettings.Shape.allCases, id: \.self) { (s: ParticleEmitterSettings.Shape) in
                    Text(s.rawValue.capitalized).tag(s)
                }
            }
            .accessibilityIdentifier("particleEmitterShape")
            if editing.values.shape != .point {
                ParticleEmitterSlider(spec: ParticleEmitterSliders.shapeWidth, value: editing.binding(\.shapeWidth), editing: editing)
            }
            if editing.values.shape == .rectangle || editing.values.shape == .path {
                ParticleEmitterSlider(spec: ParticleEmitterSliders.shapeHeight, value: editing.binding(\.shapeHeight), editing: editing)
            }
            if editing.values.shape == .path { ParticleEmitterPathLink(editing: editing) }   // SHD-008
            ParticleEmitterSlider(spec: ParticleEmitterSliders.rate, value: editing.binding(\.rate), editing: editing)
        }
    }

    private var shape: Binding<ParticleEmitterSettings.Shape> {
        Binding<ParticleEmitterSettings.Shape>(get: { () -> ParticleEmitterSettings.Shape in editing.values.shape },
                                               set: { (s: ParticleEmitterSettings.Shape) -> Void in
                                                   editing.update { (v: inout ParticleEmitterSettings) -> Void in v.shape = s }
                                               })
    }
}

private struct ParticleEmitterMotionSection: View {
    let editing: ParticleEmitterEditing

    var body: some View {
        Section("Velocity and lifetime") {
            ParticleEmitterSlider(spec: ParticleEmitterSliders.minimumSpeed,
                                  value: editing.binding(\.minimumSpeed, upperPartner: \.maximumSpeed), editing: editing)
            ParticleEmitterSlider(spec: ParticleEmitterSliders.maximumSpeed,
                                  value: editing.binding(\.maximumSpeed, lowerPartner: \.minimumSpeed), editing: editing)
            ParticleEmitterSlider(spec: ParticleEmitterSliders.direction, value: editing.binding(\.direction), editing: editing)
            ParticleEmitterSlider(spec: ParticleEmitterSliders.spread, value: editing.binding(\.spread), editing: editing)
            ParticleEmitterSlider(spec: ParticleEmitterSliders.minimumLifetime,
                                  value: editing.binding(\.minimumLifetime, upperPartner: \.maximumLifetime), editing: editing)
            ParticleEmitterSlider(spec: ParticleEmitterSliders.maximumLifetime,
                                  value: editing.binding(\.maximumLifetime, lowerPartner: \.minimumLifetime), editing: editing)
            ParticleEmitterSlider(spec: ParticleEmitterSliders.gravity, value: editing.binding(\.gravity), editing: editing)
        }
    }
}

private struct ParticleEmitterBoundsSection: View {
    let editing: ParticleEmitterEditing

    var body: some View {
        Section("Collision bounds") {
            Picker("Bounds", selection: bounds) {
                ForEach(ParticleEmitterSettings.Bounds.allCases, id: \.self) { (b: ParticleEmitterSettings.Bounds) in
                    Text(b.rawValue.capitalized).tag(b)
                }
            }
            .accessibilityIdentifier("particleEmitterBounds")
            if editing.values.bounds != .none { boundsDetails }
        }
    }

    @ViewBuilder private var boundsDetails: some View {
        Picker("On contact", selection: action) {
            Text("Bounce").tag(ParticleEmitterSettings.Action.bounce)
            Text("Remove").tag(ParticleEmitterSettings.Action.kill)
        }
        .accessibilityIdentifier("particleEmitterAction")
        if editing.values.bounds == .box {
            ParticleEmitterSlider(spec: ParticleEmitterSliders.boxHalfWidth, value: editing.binding(\.boxHalfWidth), editing: editing)
            ParticleEmitterSlider(spec: ParticleEmitterSliders.boxHeight, value: editing.binding(\.boxHeight), editing: editing)
        }
        if editing.values.action == .bounce {
            ParticleEmitterSlider(spec: ParticleEmitterSliders.restitution, value: editing.binding(\.restitution), editing: editing)
        }
    }

    private var bounds: Binding<ParticleEmitterSettings.Bounds> {
        Binding<ParticleEmitterSettings.Bounds>(get: { () -> ParticleEmitterSettings.Bounds in editing.values.bounds },
                                                set: { (b: ParticleEmitterSettings.Bounds) -> Void in
                                                    editing.update { (v: inout ParticleEmitterSettings) -> Void in v.bounds = b }
                                                })
    }

    private var action: Binding<ParticleEmitterSettings.Action> {
        Binding<ParticleEmitterSettings.Action>(get: { () -> ParticleEmitterSettings.Action in editing.values.action },
                                                set: { (a: ParticleEmitterSettings.Action) -> Void in
                                                    editing.update { (v: inout ParticleEmitterSettings) -> Void in v.action = a }
                                                })
    }
}

/// The preview: the fountain's layout of the simulation, drawn as squares on a dark background.
private struct ParticleEmitterPreviewCanvas: View {
    let settings: ParticleEmitterSettings
    @State private var preview: ParticleEmitterPreview?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            canvas
            #if DEBUG
            if UITestVisualProbes.isRequested, let preview {   // QA-011 B07 SHD-007-T13, SHD-008-T18
                Text(preview.boundsProbe)
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("particleBoundsProbe")
                    .accessibilityValue(preview.boundsProbe)
            }
            #endif
            if reduceMotion {
                Button("Step 1 second") { () -> Void in preview?.advance(frames: Int(ParticleEmitterPreview.framesPerSecond)) }
                    .accessibilityIdentifier("particleEmitterStep")
            }
        }
        .onAppear { () -> Void in
            if preview == nil { preview = ParticleEmitterPreview(settings: settings) }
        }
        .onChange(of: settings) { () -> Void in preview?.configure(settings) }
        .task(id: reduceMotion) { () async -> Void in
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))   // paces only: time comes from the frame index
                preview?.advance()
            }
        }
    }

    private var canvas: some View {
        let frame: Int = preview?.frame ?? 0
        return Canvas { (context: inout GraphicsContext, size: CGSize) -> Void in
            _ = frame
            draw(&context, size: size)
        }
        .background(Color.black)
        .aspectRatio(1.5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement()
        .accessibilityLabel("Emitter preview")
        .accessibilityValue(preview?.summary ?? "")
        .accessibilityIdentifier("particleEmitterPreview")
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        guard let preview else { return }
        let layout: ParticleFountainLayout = preview.layout
        layout.layout(simulation: preview.simulation, width: Int(size.width), height: Int(size.height))
        for k in 0..<layout.squareCount {
            let q: [Double] = layout.quad(k)
            let c: LinearColor = layout.color(k)
            let rect = CGRect(x: q[0], y: q[1], width: q[2] - q[0], height: q[5] - q[1])
            let color = Color(.sRGBLinear, red: Double(c.red), green: Double(c.green), blue: Double(c.blue), opacity: Double(c.alpha))
            context.fill(Path(rect), with: .color(color))
        }
    }
}

/// SHD-008-T14: "Edit path" for the `path` spawn shape; each committed path is saved at once.
private struct ParticleEmitterPathLink: View {
    let editing: ParticleEmitterEditing

    var body: some View {
        NavigationLink { editor } label: { LabeledContent("Edit path", value: "\(editing.values.path.points.count) points") }
            .accessibilityIdentifier("particleEmitterPathEdit")
    }

    private var editor: some View {
        let target: ParticleEmitterEditing = editing
        return VectorPathEditorView(title: "Spawn Path", path: editing.values.path) { (made: VectorPath) -> Void in
            target.update { (s: inout ParticleEmitterSettings) -> Void in s.path = made }
        }
    }
}
