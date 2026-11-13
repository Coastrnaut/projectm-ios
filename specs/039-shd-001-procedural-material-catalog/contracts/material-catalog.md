# Contract: Procedural material catalog (SHD-001)

Module `ProceduralMaterials` (Packages/Compositor). CPU parts build everywhere; the layer and the
shaders build behind `#if canImport(Metal) && !COMPOSITOR_NO_METAL`.

## Catalog (CPU)

```swift
public enum MaterialKind: String, CaseIterable, Sendable { case gradient, plasma, noiseFlow, tunnel, starfield }

public enum ProceduralMaterialCatalog {
    static var materials: [MaterialDefinition]            // catalog order (SHD-001-R1)
    static func material(withID id: String) -> MaterialDefinition?   // nil for unknown IDs (R3)
    static func definition(_ kind: MaterialKind) -> MaterialDefinition
    static var descriptors: [ParameterDescriptor]         // every material's parameters, in order (R2)
    static let retiredIDs: Set<ParameterID>
    static func makeRegistry() throws(ParameterRegistryError) -> ParameterRegistry
    static func defaultValues(for kind: MaterialKind) -> [ParameterID: ParameterValue]
}
```

Rules: IDs, ranges and defaults are the data-model table; the registry passes MOD-001 validation;
every material has a `speed` and an `audioReactivity` parameter; at most 8 parameters.

## Values (CPU)

```swift
public struct MaterialParameterValues: Sendable, Equatable {
    init(_ definition: MaterialDefinition)                 // defaults
    func value(for id: ParameterID) -> ParameterValue?
    mutating func set(_ value: ParameterValue, for id: ParameterID) throws(MaterialParameterError) -> ParameterValue
    func slot(_ index: Int) -> SIMD4<Float>
}
```

Clamping as the MOD-001 store (contract C3.2); refusals leave the stored value (R6).

## Motion (CPU)

```swift
public struct MaterialMotion: Sendable, Equatable {
    static let maxRisePerSecond: Double    // 4
    static let maxFallPerSecond: Double    // 1
    private(set) var phase: Double
    private(set) var audioLevel: Double
    mutating func advance(frameDuration: Double, bandLevel: Double, speed: Double, reactivity: Double)
    static func bandLevel(_ bands: UnsafeBufferPointer<Float>) -> Double
    mutating func reset()
}
```

## Layer (Metal)

```swift
public final class ProceduralMaterialLayer: LayerSource {
    init(_ definition: MaterialDefinition)
    convenience init?(materialID: String)                 // nil for unknown IDs
    let definition: MaterialDefinition
    var layerName: String { definition.id }
    let fallback = LayerFallback.transparent
    private(set) var parameters: MaterialParameterValues
    private(set) var motion: MaterialMotion
    func set(_ value: ParameterValue, for id: ParameterID) throws(MaterialParameterError) -> ParameterValue
    func update(from store: ParameterStore)               // copies this material's values that the store holds
    func resetMotion()
}
extension ProceduralMaterialCatalog { static func makeLayer(_ kind: MaterialKind) -> ProceduralMaterialLayer }
```

- `prepare`: compiles `ProceduralMaterialShaders.source` once per layer (the module's only library
  creation; SHD-001-R7), builds the pipeline for `LayerPictureDescriptor.metalPixelFormat`; a
  failure throws `.resourceUnavailable` and the compositor shows the transparent fallback.
- `render`: advances `motion` from `frame.frameDuration` and `audio.bands`, then clears and draws
  the whole picture: finite, color 0…1, alpha 1 (opaque, so premultiplied equals straight) (R4,
  R13). No commit, wait, lock, log or I/O.
- Output depends only on parameters, frame durations, sizes and bands (R5).

## Safety (R7, R8)

The module's sources contain exactly one `makeLibrary(` call, whose source argument is
`ProceduralMaterialShaders.source`, and no `contentsOf`, `URL`, `Bundle`, `FileManager`,
`URLSession`, `makeDefaultLibrary`, `dlopen` or `dlsym`. `MaterialSourceSafetyTests` scans them.
