# Contract: Threshold Trigger (MOD-006)

## T1 Settings

`ThresholdTriggerSettings(high:low:minimumIntervalSeconds: = 0.1, holdSeconds: = 0)`;
`validationProblem: String?` is nil exactly when MOD-006-R7 holds. `ThresholdTrigger(settings:)` throws
`ThresholdTriggerError.invalidSettings(reason)` otherwise.

## T2 Step

`mutating func step(value: Double, timeNanoseconds: UInt64) -> Bool` follows data-model.md transitions;
returns true on the frame it fires. Pure, allocation-free, deterministic.

## T3 Bank

`ThresholdTriggerBank`: `maximumTriggers = 8`; `set(_ bindings:) throws` (validates all; replaces all;
fresh state); `bindings`; `hasTriggers`; `advance(frame: AudioFeatureFrame, timeNanoseconds:,
fire: (ThresholdTriggerAction) -> Void)` steps each binding with `source.value(in: frame)` and calls
`fire` for each that fires, in order. No allocation per call.

## T4 Scene field

Top-level `triggers` (optional array of objects). Absent ⇔ `SceneDocument.triggers == nil`; written
only when non-nil. Each entry round-trips verbatim.

## T5 Scene read

`SceneTriggerEntry.read(_ entries: [SceneTriggerEntry]) -> (bindings: [ThresholdTriggerBinding],
issues: [SceneIssue])`, in order, never throws:
- `source` / `action` missing or not a string, `high` / `low` missing or not a finite number,
  `minimumInterval` / `hold` present but not a finite number → `invalidTrigger` at that field's path.
- Unknown source ID or action → `unknownTrigger` at `.source` / `.action`.
- Settings invalid (T1) → `invalidTrigger` at `$.triggers[i]`.
- More than 8 valid entries → `invalidTrigger` at `$.triggers[i]` for the extra ones.
All are warnings; the entry stays in the document. `validate(registry:)` includes these issues.

## T6 App

`NativeSpectrumHost.setTriggers(_:)`, `onTrigger: ((ThresholdTriggerAction) -> Void)?`; each frame's
`applyModulation` advances the bank with the frame's features and display time.
`MIDINoteActionPerformer.fire(_ action: MIDINoteAction)` performs the trigger-mode action.
