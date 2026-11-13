# Contract: Generator Graph (target `GeneratorGraph`, Packages/Compositor)

## Document (JSON form)

```json
{
  "format": "projectm-ios.generator-graph",
  "version": 1,
  "name": "Ember Drift",
  "speed": 0.2,
  "nodes": [
    {"id": "t", "kind": "time"},
    {"id": "flow", "kind": "drift", "inputs": {"phase": "t"}, "values": {"velocityX": 0.3, "velocityY": 0.1}},
    {"id": "n", "kind": "noise", "inputs": {"point": "flow"}, "values": {"scale": 3, "octaves": 4}},
    {"id": "c", "kind": "gradient", "inputs": {"t": "n"}, "values": {"colorA": [0.05, 0.0, 0.02], "colorB": [0.9, 0.35, 0.05]}},
    {"id": "out", "kind": "output", "inputs": {"color": "c"}}
  ]
}
```

Callers decode with any `Decoder` (the module itself has no Foundation and reads no files). Node
kinds, inputs, settings, ranges and defaults: data-model.md "Node kinds"; listed in code by
`GraphNodeKind.allCases` and `GraphNodeKind.spec` (for a future editor).

## API

```swift
public struct GeneratorGraphDocument: Codable, Sendable, Equatable
public enum GraphNodeKind: String, CaseIterable, Sendable
public enum GeneratorGraphIssue: Error, Equatable, Sendable { var message: String }
public struct GeneratorGraphValidationError: Error { let issues: [GeneratorGraphIssue] }
public enum GeneratorGraphCompiler {
    static func validate(_ document: GeneratorGraphDocument) -> [GeneratorGraphIssue]
    static func compile(_ document: GeneratorGraphDocument) throws(GeneratorGraphValidationError) -> CompiledGeneratorGraph
}
public struct CompiledGeneratorGraph: Sendable, Equatable   // planBytes, speedCap, musicRate, …
public struct GraphMotion: Sendable, Equatable
public enum GeneratorGraphExamples { static let all: [GeneratorGraphDocument] }
// Metal only:
public final class GeneratorGraphPipeline   // one per device, shareable by every graph layer
public final class GeneratorGraphLayer: LayerSource
```

## Messages (exact)

| Issue | Message |
|---|---|
| unsupportedFormat | `Unsupported format "X"; expected "projectm-ios.generator-graph".` |
| unsupportedVersion | `Unsupported version N; this app reads version 1.` |
| nameTooLong | `Graph name has N characters; the limit is 64.` |
| speedOutOfRange | `Graph speed V is outside -1 to 1.` |
| tooManyNodes | `Graph has N nodes; the limit is 64.` |
| tooManyConnections | `Graph has N connections; the limit is 128.` |
| invalidNodeID | `Node ID "X" is invalid: use 1-32 letters, digits, "-" or "_", starting with a letter.` |
| duplicateNodeID | `Node ID "X" is used more than once.` |
| unknownKind | `Node "A": unknown kind "K".` |
| unknownName | `Node "A": kind "K" has no input or setting "P".` |
| settingConnected | `Node "A": "P" is a setting and cannot be connected.` |
| connectedAndSet | `Node "A": input "P" is both connected and given a value.` |
| missingSource | `Node "A": input "P" is connected to missing node "S".` |
| sourceIsOutput | `Node "A": input "P" is connected to output node "S", which gives no value.` |
| typeMismatch | `Node "A": input "P" expects T but node "S" gives U.` |
| phaseLiteral | `Node "A": input "P" takes time and cannot be given a value.` |
| missingInput | `Node "A": required input "P" is not connected.` |
| wrongValueShape | `Node "A": "P" needs T.` (`a number`, `a point (2 numbers)`, `a color (3 numbers)`) |
| notFinite | `Node "A": "P" is not a finite number.` |
| outOfRange | `Node "A": "P" is V, outside LO to HI.` |
| notWhole | `Node "A": "P" must be a whole number.` |
| invalidSetting | `Node "A": <rule>.` (`"min" must not exceed "max"`, `"edge0" and "edge1" must differ by at least 0.01`, `the drift velocity must be at most 1 long`) |
| noOutput | `Graph has no output node.` |
| multipleOutputs | `Graph has N output nodes ("a", "b"); exactly one is allowed.` |
| cycle | `Graph has a cycle: a → b → c → a.` |
| tooDeep | `Graph's longest chain has N nodes; the limit is 32.` |
| tooManyLiveValues | `Graph needs N values at once; the limit is 16.` |
| tooFast | `Graph changes too fast with time; it would have to run below 1/64 of normal speed.` / `… with music; …` |

Numbers print as integers when whole, otherwise in Swift's shortest form.

## Plan bytes (little-endian)

Header 32 bytes: magic `SHD2` (4 bytes), plan version UInt32 (1), instruction count UInt32,
register count UInt32, speedCap Float64 bits, musicRate Float64 bits. Then per instruction 80 bytes:
op, dst, sources, flags (UInt32 each), 12 literal Float32, 4 setting Float32, then per instruction
the time term: kind UInt32 and three Float64 constants (rate, offset/velocityY, unused). Same
document (in any node order) → identical bytes.

## Layer

`GeneratorGraphLayer(compiled:pipeline:)`; fallback transparent; picture rgba16Float linear,
opaque (premultiplied = straight); draws under the composite flash guard. `speed` clamps to
±speedCap. Uniform `GraphFrame` (1,040 bytes) by `setFragmentBytes`: size, music level, count, 64
time terms; the plan by a buffer created in `prepare`.
