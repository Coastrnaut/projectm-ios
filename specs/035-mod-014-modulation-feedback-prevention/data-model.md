# Data Model: MOD-014 Modulation Feedback Prevention

All types are value types, `Sendable` and `Hashable`, in `Packages/ParameterGraph`.

| Entity | Fields | Rules |
|---|---|---|
| `ModulationNode` | `.audio(AudioFeatureSource)`, `.parameter(ParameterID)`, `.generator(String)`; `id` (stable text) | Audio features are sources only. A parameter has one input, `value`. A generator has the inputs it declares. Ordered by `id`, then kind (audio < parameter < generator). |
| `ModulationGenerator` | `id`, `displayName`, `inputs: [String]` | `id` uses the parameter ID syntax and may not equal a registered or retired parameter ID or use the `audio` domain; declared once; non-empty display name; input names are single segments (lowercase letter, then letters and digits), each once. |
| `ModulationEdge` | `source`, `target`, `input` (default `value`) | The target must accept `input`. Exact repeats are duplicates. |
| `ModulationGraph` | `generators`, `edges`; limits `maximumNodes` 1,024, `maximumEdges` 4,096 | `validate(in:)` returns every issue (MOD-014-R4, R5). |
| `ModulationCycle` | `edges` (loop order), `path`, `displayPath` | The first edge leaves the start node; the last edge enters it. |
| `ModulationGraphIssue` | `problem`, `edge?`, `generatorID?`, `cycle?`, `message` | One issue per problem; `message` is readable. |
| `ModulationGraphError` | `issues` | Thrown by `ValidatedModulationGraph.init`; `description` lists every message. |
| `ValidatedModulationGraph` | `graph`, `registry`, `nodes`, `evaluationOrder` | Exists only for an issue-free graph; `wouldCreateCycle(adding:)`. |

Issue problems: `tooManyEdges`, `tooManyNodes`, `malformedGeneratorID`, `emptyGeneratorName`,
`duplicateGenerator`, `conflictingGeneratorID`, `malformedInput`, `duplicateInput`,
`unknownAudioFeature`, `unknownParameter`, `retiredParameter`, `unknownGenerator`, `audioTarget`,
`unknownInput`, `duplicateEdge`, `selfLoop`, `cycle`.

Node count: valid declared generators plus the distinct nodes named by connections.

Path text: the start node's entry, then each step's entry, joined by ` → `. An entry is the node's
ID, followed by `.<input>` when the connection enters a generator input other than `value`. The
display path uses the parameter's display name, the generator's display name (with ` (<input>)`
for inputs other than `value`) and the audio feature's ID.
