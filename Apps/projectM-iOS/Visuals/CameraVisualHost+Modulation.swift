// CameraVisualHost+Modulation.swift — CAM-010: the Camera visual evaluates the scene's bindings for what it draws
// (CAM-010-R16, S7; research CAM-010-D7; contract hand-sources H6). Closes CAM-009-D8's gap: face and hand values now
// move real parameters while the camera runs.
//
// * `CameraVisualModulation` owns the native visuals' `AudioFeatureModulator` over the visual catalog. The app loads
//   the scene's bindings when the Camera visual is made and again after every modulation-matrix edit (as the native
//   host). Each composited frame advances it with the frame's bands and, only while a binding names them, the face and
//   hand values, at the frame's target time.
// * The Camera visual draws one catalog-described layer of its own: the circular spectrum above the camera. Its inner
//   radius (`visual.circularSpectrum.innerRadius`) and gap (`.gap`) take the modulated values; the configuration clamps
//   them. Unbound, the base values return once. Bindings to other targets are carried but have no effect here; LFO,
//   band-envelope and motion sources read their no-input values; threshold triggers stay with the native visuals.
// * Per frame nothing is allocated: struct reads and the modulator's preallocated slots.
import Foundation
import ParameterGraph
import VisualGenerators
import VisualParameters

extension AudioFeatureSource {
    /// CAM-009: a face source.
    var isFace: Bool {
        if case .face = self { return true }
        return false
    }

    /// CAM-010: a hand source.
    var isHand: Bool {
        if case .hand = self { return true }
        return false
    }
}

@MainActor
final class CameraVisualModulation {
    /// The circular spectrum's two catalog parameters the Camera visual applies.
    static let appliedTargets: [ParameterID] = [VisualParameterIDs.circularSpectrumInnerRadius, VisualParameterIDs.circularSpectrumGap]

    private let modulator: AudioFeatureModulator? = (try? VisualParameterCatalog.makeRegistry()).map(AudioFeatureModulator.init(registry:))
    /// The face analyzer's values, read per frame while a binding names a face source.
    var faceValues: (@MainActor () -> FaceFeatureValues)?
    /// The hand analyzer's values, read per frame while a binding names a hand source.
    var handValues: (@MainActor () -> HandFeatureValues)?
    private(set) var usesFace = false
    private(set) var usesHand = false
    /// The ring's manual values (the Camera visual's defaults).
    let baseInnerRadius: Double
    let baseGap: Double
    /// The bar length scale, restored each frame (a larger inner radius shortens it while bound).
    let baseLengthScale: Double

    init(baseInnerRadius: Double, baseGap: Double, baseLengthScale: Double) {
        self.baseInnerRadius = baseInnerRadius
        self.baseGap = baseGap
        self.baseLengthScale = baseLengthScale
    }

    convenience init(_ configuration: CircularSpectrumConfiguration) {
        self.init(baseInnerRadius: configuration.innerRadius, baseGap: configuration.gap, baseLengthScale: configuration.lengthScale)
    }

    /// The scene's bindings in order (MOD-011 layers); one that does not validate is skipped, as the native host does.
    func load(_ bindings: [AudioFeatureBinding]) {
        guard let modulator else { return }
        modulator.unbindAll()
        for binding in bindings { try? modulator.addLayer(binding) }
        usesFace = modulator.bindings.contains { (b: AudioFeatureBinding) -> Bool in b.source.isFace }
        usesHand = modulator.bindings.contains { (b: AudioFeatureBinding) -> Bool in b.source.isHand }
    }

    /// The live bindings (tests).
    var bindings: [AudioFeatureBinding] { modulator?.bindings ?? [] }

    /// True while a binding targets something the Camera visual draws.
    var drivesRing: Bool {
        guard let modulator else { return false }
        return Self.appliedTargets.contains { (id: ParameterID) -> Bool in modulator.isBound(id) }
    }

    /// Advances with one frame and returns the ring's inner radius and gap; nil when neither is bound.
    func resolve(bands: UnsafeBufferPointer<Float>, timeNanoseconds: UInt64) -> (innerRadius: Double, gap: Double)? {
        guard let modulator, drivesRing else { return nil }
        let frame = AudioFeatureFrame(bands: bands, face: usesFace ? faceValues?() : nil,
                                      hand: usesHand ? handValues?() : nil)   // structs, no allocation
        modulator.advance(frame: frame, timeNanoseconds: timeNanoseconds)
        let radius: Double = modulator.value(for: VisualParameterIDs.circularSpectrumInnerRadius, manual: baseInnerRadius)
        let gap: Double = modulator.value(for: VisualParameterIDs.circularSpectrumGap, manual: baseGap)
        return (radius, gap)
    }
}

extension CameraVisualHost {
    /// CAM-010-R16: one frame of the Camera visual's modulation, applied to its circular spectrum (no allocation).
    func applyModulation(timeNanoseconds: UInt64) {
        guard let ring = spectrum.generator as? CircularSpectrumGenerator else { return }
        let bandView = UnsafeBufferPointer<Float>(start: bands, count: bandCount)
        var configuration: CircularSpectrumConfiguration = ring.configuration
        if let resolved = modulation.resolve(bands: bandView, timeNanoseconds: timeNanoseconds) {
            configuration.innerRadius = resolved.innerRadius
            configuration.gap = resolved.gap
        } else {
            configuration.innerRadius = modulation.baseInnerRadius   // unbound: the manual ring once
            configuration.gap = modulation.baseGap
        }
        configuration.lengthScale = modulation.baseLengthScale   // the setter clamps it to the radius
        guard configuration != ring.configuration else { return }
        ring.configuration = configuration
    }

    /// The ring's current inner radius and gap (tests).
    var ringGeometry: (innerRadius: Double, gap: Double)? {
        guard let ring = spectrum.generator as? CircularSpectrumGenerator else { return nil }
        return (ring.configuration.innerRadius, ring.configuration.gap)
    }
}
