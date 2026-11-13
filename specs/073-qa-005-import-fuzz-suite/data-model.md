# Data Model: QA-005 Import Fuzz Suite

All types live in `FuzzKit` (test-only). None is persisted.

| Entity | Fields | Rules |
|---|---|---|
| `FuzzRandom` | `state: UInt64` | SplitMix64; `next()`, `below(n)` (n ≥ 1), `chance(oneIn:)`, `bytes(count:)`. Never uses the system generator. |
| `FuzzMutation` | case `bitFlip`, `byteOverwrite`, `byteInsert`, `byteDelete`, `truncate`, `repeatSlice`, `splice`, `lengthField`, `jsonStructure`, `oscStructure` | `apply(to:other:rng:cap:)` returns ≤ `cap` bytes; total for every input (empty included). |
| `FuzzBudget` | `inputs`, `maxInputBytes`, `maxRunBytes` | `inputs ≥ 1`; `maxRunBytes` defaults to `inputs × maxInputBytes`. |
| `FuzzConfiguration` | `iterationsOverride: Int?`, `seedOverride: UInt64?` | Parsed from an environment dictionary: `FUZZ_ITERATIONS` positive decimal ≤ 100,000 (larger capped, others ignored); `FUZZ_SEED` decimal or `0x` hex. |
| `FuzzInput` | `bytes`, `iteration`, `seed`, `strategies: [FuzzMutation]`, `baseIndex: Int?` | `description` names all fields except bytes, plus the size. |
| `FuzzOutcome` | `kind: accepted / refused`, `work: Int?`, `violation: String?` | `work` is the parser's own counter when it has one. |
| `FuzzReport` | `inputs`, `bytes`, `accepted`, `refused`, `digest: UInt64`, `violations: [String]`, `strategyCounts` | `violations` empty ⇔ suite passed; each entry carries the input's description. |
| `FuzzCampaign` | `name`, `seed`, `budget`, `strategies`, `corpus`, `workBound: ((Int) -> Int)?` | `run(_ body: (FuzzInput) -> FuzzOutcome) -> FuzzReport`; stops at `budget.inputs` or `budget.maxRunBytes`. |
| `FuzzCorpus` | `name`, `items: [[UInt8]]` | Loaded from a directory in file-name order; hidden files skipped. |

State: none beyond a run. A `FuzzCampaign.run` is a pure function of (seed, configuration, corpus,
strategies, budget) and the body's behaviour.
