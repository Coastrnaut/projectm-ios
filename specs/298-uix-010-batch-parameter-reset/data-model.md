# Data Model: UIX-010 Batch Parameter Reset

- **ParameterResetSelection** (value, in memory per visit): `ids: Set<ParameterID>`; `toggle(id)`, `setAll(ids, selected:)`, `allSelected(ids) -> Bool` (non-empty and all contained), `clear()`; `count`; `buttonTitle`, `buttonAccessibilityLabel`. Only IDs with a write target are offered.
- **ParameterBatchResetResult**: `outcome` (`.reset`, `.alreadyAtDefaults`, `.refused`), `written: [ParameterID]` (catalog order), `undoLabel: String?`, `message: String`.
- State: list (browse) → selecting (Select) → after a reset or refusal: browse with the selection cleared; after "Already at defaults": still selecting.
