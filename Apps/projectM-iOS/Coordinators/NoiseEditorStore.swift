// NoiseEditorStore.swift — the Noise editor's values, storage, "Randomize seed" and live preview (SHD-006-R6, R7;
// specs/245-shd-006-noise-editor, contract N5, research SHD-006-D7, D8).
//
// * The values are Noise Flow's metadata parameters (`MaterialParameterValues`: clamped by the material's rules).
// * Storage: one UserDefaults key, `settings.noiseEditor.values`, a JSON object of parameter name → MOD-001 value
//   with sorted keys, holding only values that differ from the defaults (absent key = all defaults). Reading is
//   lenient: unknown names and refused values are skipped, damaged data reads as the defaults. Backed up and erased
//   with Settings (FILE-005, FILE-011).
// * "Randomize seed" takes the next seed of `NoiseSeedSequence` (a counter from 1 each launch, no system random
//   source), never the current seed.
// * The preview: Noise Flow's own GPU code draws one still frame (phase 0) through `MaterialPreviewRenderer` after
//   every change; nil without Metal.
import CoreGraphics
import Foundation
import Observation
import ParameterGraph
import ProceduralMaterials
import ShaderParameterMetadata

@MainActor
@Observable
final class NoiseEditorStore {
    static let key = "settings.noiseEditor.values"
    static let allKeys: [String] = [key]
    /// Pixels per side of the preview.
    static let previewSide = 256

    /// The renderer every editor shares (one command queue for the app).
    static let sharedRenderer: MaterialPreviewRenderer? = MaterialPreviewRenderer.makeDefault()

    let definition: MaterialDefinition = ProceduralMaterialCatalog.definition(.noiseFlow)
    private(set) var values: MaterialParameterValues
    private(set) var preview: CGImage?
    @ObservationIgnored private var seeds = NoiseSeedSequence()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let renderer: MaterialPreviewRenderer?
    @ObservationIgnored private let layer: ProceduralMaterialLayer

    init(defaults: UserDefaults, renderer: MaterialPreviewRenderer? = NoiseEditorStore.sharedRenderer) {
        self.defaults = defaults
        self.renderer = renderer
        let definition: MaterialDefinition = ProceduralMaterialCatalog.definition(.noiseFlow)
        values = Self.load(defaults.data(forKey: Self.key), definition: definition)
        layer = ProceduralMaterialLayer(definition)
        redraw()
    }

    // MARK: - Values

    var valueMap: [ParameterID: ParameterValue] {
        var map: [ParameterID: ParameterValue] = [:]
        for (d, v) in zip(definition.parameters, values.values) { map[d.id] = v }
        return map
    }

    /// One generic control per parameter, in metadata order (SHD-003-R7).
    var controls: [ShaderParameterControl] { definition.controls(values: valueMap) }

    var seed: Int { values.value(for: seedID)?.numericValue.map { (v: Double) -> Int in Int(v) } ?? 0 }
    var octaves: Int { values.value(for: definition.parameterID("octaves"))?.numericValue.map { (v: Double) -> Int in Int(v) } ?? 0 }
    var seedID: ParameterID { definition.parameterID("seed") }

    /// Stores `value` clamped, saves and redraws; a refused value changes nothing.
    func set(_ id: ParameterID, _ value: ParameterValue) {
        let before: MaterialParameterValues = values
        do {
            try values.set(value, for: id)
        } catch {
            return
        }
        guard values != before else { return }
        save()
        redraw()
    }

    func randomizeSeed() {
        let next: Int = seeds.next(after: seed)
        set(seedID, .integer(next))
    }

    func resetToDefaults() {
        values = MaterialParameterValues(definition)
        defaults.removeObject(forKey: Self.key)
        redraw()
    }

    /// The preview's VoiceOver value ("Seed 0, 3 octaves").
    var previewDescription: String {
        let seedText: String = "Seed \(seed)"
        let octaveText: String = octaves == 1 ? "1 octave" : "\(octaves) octaves"
        return seedText + ", " + octaveText
    }

    // MARK: - Storage

    /// Lenient read (see the header).
    static func load(_ data: Data?, definition: MaterialDefinition) -> MaterialParameterValues {
        var values = MaterialParameterValues(definition)
        guard let data, let stored = try? JSONDecoder().decode([String: LenientValue].self, from: data) else { return values }
        for name in stored.keys.sorted() {
            guard let value = stored[name]?.value else { continue }
            _ = try? values.set(value, for: definition.parameterID(name))
        }
        return values
    }

    /// One stored entry; an undecodable value reads as nil instead of failing the whole object.
    private struct LenientValue: Decodable {
        let value: ParameterValue?

        init(from decoder: any Decoder) throws {
            value = try? ParameterValue(from: decoder)
        }
    }

    /// The values that differ from the defaults, by parameter name; nil when all are defaults.
    static func encode(_ values: MaterialParameterValues) -> Data? {
        var changed: [String: ParameterValue] = [:]
        for (d, v) in zip(values.definition.parameters, values.values) where v != d.defaultValue {
            let name: String = d.id.segments.last.map { (s: Substring) -> String in String(s) } ?? d.id.rawValue
            changed[name] = v
        }
        guard !changed.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(changed)
    }

    private func save() {
        if let data = Self.encode(values) {
            defaults.set(data, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    // MARK: - Preview

    private func redraw() {
        guard let renderer else {
            preview = nil
            return
        }
        for (d, v) in zip(definition.parameters, values.values) { _ = try? layer.set(v, for: d.id) }
        guard let image = try? renderer.render(layer, width: Self.previewSide, height: Self.previewSide) else {
            preview = nil
            return
        }
        preview = Self.cgImage(width: image.width, height: image.height, rgba: image.rgba)
    }

    static func cgImage(width: Int, height: Int, rgba: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                       bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
