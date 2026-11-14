// SnapshotBatchJob.swift — REC-002 what one image batch renders (specs/234-rec-002-image-batch-export; R1 to R4, R12;
// data-model.md; contract B2; research REC-002-D1, D3, D5).
//
// * A job is captured once, when Export is tapped: the native visual's style, Reduce flashing, the safety clamp, the
//   size and one item per selected usable snapshot (list order). Later live changes never reach it (R12).
// * An item's values are the live values of the seven SCN-008 parameters with the snapshot's usable values laid over
//   them (`SceneSnapshotRecallPlan`, SCN-009's side rule D4). Nothing here writes the live settings (D1).
// * Only the native visuals render offscreen (D3); any other visual refuses the job.
import FlashSafety
import Foundation
import ParameterGraph
import SceneFormat
import VisualEffects
import VisualGenerators
import VisualParameters

/// The batch's image size (REC-014's three shapes at 1080 p; chosen per export, not stored).
enum SnapshotBatchSize: String, CaseIterable, Identifiable, Sendable {
    case landscape
    case portrait
    case square

    var id: String { rawValue }

    var width: Int {
        switch self {
        case .landscape: 1920
        case .portrait, .square: 1080
        }
    }

    var height: Int {
        switch self {
        case .portrait: 1920
        case .landscape, .square: 1080
        }
    }

    var title: String {
        switch self {
        case .landscape: "Landscape"
        case .portrait: "Portrait"
        case .square: "Square"
        }
    }

    /// "1920 × 1080".
    var pixels: String { String(width) + " × " + String(height) }
}

/// The snapshot parameters an image is drawn with.
struct SnapshotRenderValues: Equatable, Sendable {
    var barCount: SpectrumBarCount
    var orientation: LinearSpectrumOrientation
    var spacing: Double
    var glow: BloomParameters

    /// The live values (what the Settings controls show).
    @MainActor
    init(settings: AppSettings) {
        barCount = SpectrumBarCount(rawValue: settings.circularSpectrumBars) ?? .b64
        orientation = settings.linearSpectrumOrientation
        spacing = settings.linearSpectrumSpacing
        glow = settings.glowParameters
    }

    init(barCount: SpectrumBarCount, orientation: LinearSpectrumOrientation, spacing: Double, glow: BloomParameters) {
        self.barCount = barCount
        self.orientation = orientation
        self.spacing = spacing
        self.glow = glow
    }

    /// `base` with each value of `values` it understands laid over it (a missing or wrong-kind value keeps the base).
    func overlaid(with values: [ParameterID: ParameterValue]) -> SnapshotRenderValues {
        typealias IDs = VisualParameterIDs
        var out: SnapshotRenderValues = self
        if let b = values[IDs.bloomEnabled]?.boolValue { out.glow.enabled = b }
        if let d = values[IDs.bloomIntensity]?.doubleValue { out.glow.intensity = Float(d) }
        if let d = values[IDs.bloomRadius]?.doubleValue { out.glow.radius = Float(d) }
        if let d = values[IDs.bloomThreshold]?.doubleValue { out.glow.threshold = Float(d) }
        if let bars = values[IDs.circularSpectrumBarCount]?.enumCaseID.flatMap({ (s: String) -> Int? in Int(s) }),
           let count = SpectrumBarCount(rawValue: bars) {
            out.barCount = count
        }
        if let o = values[IDs.linearSpectrumOrientation]?.enumCaseID.flatMap(LinearSpectrumOrientation.init(rawValue:)) {
            out.orientation = o
        }
        if let d = values[IDs.linearSpectrumSpacing]?.doubleValue { out.spacing = d }
        return out
    }
}

/// One image of a batch.
struct SnapshotBatchItem: Equatable, Sendable {
    /// 1-based position in the batch.
    let position: Int
    /// The snapshot's index in the scene's list.
    let snapshotIndex: Int
    let name: String
    let fileName: String
    let values: SnapshotRenderValues
}

/// Everything a batch renders, frozen at Export (R12).
struct SnapshotBatchJob: Equatable, Sendable {
    let visual: VisualChoice
    /// The visual's style with the live options (the linear spectrum's orientation and spacing come from each item).
    let style: NativeSpectrumStyle
    let reduceFlashing: Bool
    let clamp: SafetyClamp
    let size: SnapshotBatchSize
    let items: [SnapshotBatchItem]

    /// The style an item is drawn with.
    func style(for item: SnapshotBatchItem) -> NativeSpectrumStyle {
        if case .linear = style { return .linear(item.values.orientation, spacing: item.values.spacing) }
        return style
    }
}

/// Why Export is refused (contract B2).
enum SnapshotBatchRefusal: Error, Equatable, Sendable {
    case nothingSelected
    case unsupportedVisual
    case comparing
    case busy

    static let unsupportedMessage = "Image export works with the native visuals. Choose one in Settings › Visual."

    var message: String {
        switch self {
        case .nothingSelected: "Select at least one snapshot."
        case .unsupportedVisual: Self.unsupportedMessage
        case .comparing: "Finish Compare first."   // SceneSnapshotCoordinator.compareRefusal (SCN-009-R4)
        case .busy: "An export is already running."
        }
    }
}

enum SnapshotBatchPlanner {
    /// The native style of `visual` with the live options; nil for projectM, Camera, Photo, Video and Text (D3).
    @MainActor
    static func style(for visual: VisualChoice, settings: AppSettings) -> NativeSpectrumStyle? {
        guard visual.isNative else { return nil }
        switch visual {
        case .linearSpectrum: return .linear(settings.linearSpectrumOrientation, spacing: settings.linearSpectrumSpacing)
        case .oscilloscope: return .oscilloscope(line: settings.oscilloscopeLine, windowMilliseconds: settings.oscilloscopeWindowMilliseconds)
        case .lissajous: return .lissajous(mode: settings.lissajousMode, persistence: settings.lissajousPersistence)
        case .radialWaveform: return .radialWaveform(ring: settings.radialWaveformRing, amplitude: settings.radialWaveformAmplitude)
        case .beatRings: return .beatRings(life: settings.beatRingsLife)
        case .mandala: return .mandala(symmetry: settings.mandalaSymmetry, mirror: settings.mandalaMirror, petal: settings.mandalaPetal)
        case .particleFountain: return .particleFountain(gravity: settings.particleGravity)
        case .particleOrbit: return .particleOrbit(radius: settings.particleOrbitRadius)
        default: return .circular
        }
    }

    /// The selected usable snapshots of `entries` in list order, each with its values and file name.
    static func items(entries: [SceneSnapshotEntry], selection: Set<Int>, base: SnapshotRenderValues,
                      registry: ParameterRegistry, settable: Set<ParameterID>) -> [SnapshotBatchItem] {
        let read: [SceneSnapshot?] = SceneSnapshotEntry.read(entries).snapshots
        var chosen: [(index: Int, snapshot: SceneSnapshot)] = []
        for index in read.indices where selection.contains(index) {
            if let snapshot = read[index] { chosen.append((index, snapshot)) }
        }
        let names: [String] = SnapshotBatchNaming.fileNames(chosen.map { (c: (index: Int, snapshot: SceneSnapshot)) -> String in c.snapshot.name })
        var items: [SnapshotBatchItem] = []
        for (offset, choice) in chosen.enumerated() {
            let plan = SceneSnapshotRecallPlan(choice.snapshot, registry: registry,
                                               settable: { (id: ParameterID) -> Bool in settable.contains(id) })
            var values: [ParameterID: ParameterValue] = [:]
            for write in plan.writes { values[write.id] = write.value }
            items.append(SnapshotBatchItem(position: offset + 1, snapshotIndex: choice.index, name: choice.snapshot.name,
                                           fileName: names[offset], values: base.overlaid(with: values)))
        }
        return items
    }
}
