// FixturePreviewStore.swift — the Noise editor's fixture preview (SHD-012-R6, R7, R9; specs/249-shd-012-authoring-preview-
// fixture, contract P4; research SHD-012-D6).
//
// * Session state only (no UserDefaults key): one preview binding (a modulatable Noise Flow parameter ← kick, band mean
//   or the lowest band; full range, linear, no smoothing; default Warp amount ← kick) and the fixture seed (1…99).
// * `play(values:)` records the whole run off the main actor with its own `AuthoringPreviewRecorder` (REC-013's fixture
//   audio and clock, the material's own GPU code, SHA-256 per frame) at 128 × 128, then loops it; without Metal only the
//   trajectory is recorded and the summary has no digest. A result that arrives after the inputs changed is dropped.
// * Any change of the Noise settings, the binding or the seed clears the run (the frames no longer match).
import AuthoringPreview
import CoreGraphics
import FrameCapture
import Foundation
import Observation
import ParameterGraph
import ProceduralMaterials

/// The features the fixture analysis feeds (the others read 0 in the preview).
enum FixturePreviewSource: String, CaseIterable, Identifiable, Sendable {
    case kick, bandMean, lowestBand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kick: "Kick"
        case .bandMean: "All bands"
        case .lowestBand: "Lowest band"
        }
    }

    var feature: AudioFeatureSource {
        switch self {
        case .kick: .kick
        case .bandMean: .bandMean
        case .lowestBand: .band(0)
        }
    }
}

@MainActor
@Observable
final class FixturePreviewStore {
    enum Phase: Equatable { case idle, rendering, ready, failed(String) }

    /// Pixels per side of the preview frames.
    nonisolated static let side = 128

    let definition: MaterialDefinition
    /// nil = no binding.
    var target: ParameterID? { didSet { if target != oldValue { invalidate() } } }
    var source: FixturePreviewSource = .kick { didSet { if source != oldValue { invalidate() } } }
    var seed: Int = Int(AuthoringPreviewFixture.defaultSeed) {
        didSet {
            let clamped: Int = min(max(seed, AuthoringPreviewFixture.editorSeeds.lowerBound), AuthoringPreviewFixture.editorSeeds.upperBound)
            if clamped != seed { seed = clamped }
            if seed != oldValue { invalidate() }
        }
    }
    private(set) var phase: Phase = .idle
    private(set) var trajectory: AuthoringPreviewTrajectory?
    private(set) var runDigest: String?
    private(set) var frames: [CGImage] = []
    /// Completed runs (the Play button's accessibility value).
    private(set) var runCount = 0
    var isPlaying = false
    /// The frame shown while not playing (the frame slider).
    var frameIndex = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let useGPU: Bool

    init(definition: MaterialDefinition = ProceduralMaterialCatalog.definition(.noiseFlow), useGPU: Bool = true) {
        self.definition = definition
        self.useGPU = useGPU
        target = definition.parameterID("warpAmount")
    }

    /// The parameters a binding may target (modulatable numbers), in metadata order.
    var targets: [ParameterDescriptor] {
        definition.parameters.filter { (d: ParameterDescriptor) -> Bool in d.modulation.isModulatable && d.kind.isNumeric }
    }

    /// The preview binding: the target's full range, linear, no smoothing.
    var bindings: [AudioFeatureBinding] {
        guard let target, let d = definition.parameters.first(where: { (p: ParameterDescriptor) -> Bool in p.id == target }),
              case let .continuous(minimum, maximum, _, _, _) = d.kind else { return [] }
        return [AudioFeatureBinding(source: source.feature, target: target, outputStart: minimum, outputEnd: maximum)]
    }

    func request(values: MaterialParameterValues) -> AuthoringPreviewRequest {
        AuthoringPreviewRequest(values: values, bindings: bindings, fixture: AuthoringPreviewFixture(seed: UInt64(seed)))
    }

    /// Records the run for `values`, then starts the loop (unless `autoPlay` is false, e.g. Reduce Motion).
    func play(values: MaterialParameterValues, autoPlay: Bool = true) async {
        generation += 1
        let mine: Int = generation
        let request: AuthoringPreviewRequest = request(values: values)
        let gpu: Bool = useGPU
        isPlaying = false
        phase = .rendering
        let result: Result<FixtureRun, AuthoringPreviewError> = await Task.detached(priority: .userInitiated) {
            () -> Result<FixtureRun, AuthoringPreviewError> in
            Self.run(request, gpu: gpu)
        }.value
        guard mine == generation else { return }   // the inputs changed meanwhile
        switch result {
        case let .success(run):
            trajectory = run.trajectory
            runDigest = run.digest
            frames = run.images.compactMap { (image: RGBA8Image) -> CGImage? in
                NoiseEditorStore.cgImage(width: image.width, height: image.height, rgba: image.rgba)
            }
            frameIndex = 0
            runCount += 1
            phase = .ready
            isPlaying = autoPlay && !frames.isEmpty
        case let .failure(error):
            phase = .failed(error.description)
        }
    }

    func stop() { isPlaying = false }

    /// The frames no longer match the inputs: drop the run.
    func invalidate() {
        generation += 1
        isPlaying = false
        phase = .idle
        trajectory = nil
        runDigest = nil
        frames = []
        frameIndex = 0
    }

    /// "120 frames · Warp amount 0.00…4.00 · run 1a2b3c4d".
    var summary: String {
        switch phase {
        case .idle: return "Not rendered"
        case .rendering: return "Rendering…"
        case let .failed(text): return "Failed: " + text
        case .ready: break
        }
        guard let trajectory else { return "Not rendered" }
        var parts: [String] = ["\(trajectory.frameCount) frames"]
        if let id = trajectory.parameters.first, let values = trajectory.values(for: id),
           let low = values.min(), let high = values.max() {
            let lowText: String = String(format: "%.2f", low)
            let highText: String = String(format: "%.2f", high)
            parts.append(shortName(id) + " " + lowText + "…" + highText)
        }
        if let runDigest { parts.append("run " + String(runDigest.prefix(8))) }
        return parts.joined(separator: " · ")
    }

    /// The parameter's label without its parenthesised detail ("Warp amount").
    func shortName(_ id: ParameterID) -> String {
        let name: String = definition.parameters.first { (d: ParameterDescriptor) -> Bool in d.id == id }?.displayName ?? id.rawValue
        guard let cut = name.range(of: " (") else { return name }
        return String(name[..<cut.lowerBound])
    }

    // MARK: - Off the main actor

    struct FixtureRun: Sendable {
        let trajectory: AuthoringPreviewTrajectory
        let digest: String?
        let images: [RGBA8Image]
    }

    nonisolated private static func run(_ request: AuthoringPreviewRequest, gpu: Bool) -> Result<FixtureRun, AuthoringPreviewError> {
        do {
            if gpu, let recorder = AuthoringPreviewRecorder.makeDefault() {
                let r: AuthoringPreviewRecording = try recorder.record(request, width: side, height: side, keepImages: true)
                return .success(FixtureRun(trajectory: r.trajectory, digest: r.runDigest, images: r.images))
            }
            let t: AuthoringPreviewTrajectory = try AuthoringPreviewSequencer.record(request)
            return .success(FixtureRun(trajectory: t, digest: nil, images: []))
        } catch {
            return .failure(error)
        }
    }
}
