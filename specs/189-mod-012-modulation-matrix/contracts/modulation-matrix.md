# Contract: Modulation Matrix (MOD-012)

## M1 Fold with disabled layers

For a target with layers L₁…Lₙ (list order) and base b: r₀ = b; for each enabled Lᵢ in order,
r ← ModulationMixOrder.step(r, mᵢ, modeᵢ, min, max) (ADR-0057). Disabled layers are not applied. If no
layer is enabled the value is b exactly (no integer snap). Otherwise integers snap once at the end. Every
other target is evaluated independently, so its value is unaffected by any flag of this target.

## M2 Edits

- `setEnabled(e, for: target, layer: k)`: k-th layer (0-based) of target; throws `unknownTarget` when absent;
  the signal and timing state are kept.
- `moveLayer(of: target, from: i, to: j)`: removes the i-th layer of target and inserts it at layer position j
  (0 ≤ j < count); the target's slots keep the global positions they occupied; throws `unknownTarget` when i or
  j is out of range; nothing else moves.
- `replaceBindings(list)`: validates the whole list (each as `addLayer` would) into a fresh slot set; on any
  error nothing changes.
- `ModulationRouteList.settingEnabled` / `.moving` apply the same edits to a plain list (nil when refused).

## M3 Storage

`enabled` is written only when false; absent or true → enabled; any other JSON type → malformed binding.

## M4 Undo

Each `setEnabled` or `moveLayer` through the matrix is exactly one SCN-010 step, label
"Turn Off <source> → <destination>" / "Turn On <source> → <destination>" / "Reorder <destination>"; undo
restores the previous list.

## M5 UI identifiers

- Settings row: `modulationLink` ("Modulation", value "N routes").
- Matrix: section per destination; layer row `modulationRoute.<target>.<layer>` (opens the detail); switch
  `modulationRouteEnabled.<target>.<layer>`; VoiceOver actions "Move Up", "Move Down".
- DEBUG probe `modulationProbe`: "<target>=<value %.4f>" per destination, space separated, first-appearance order.
- Detail: `modulationRouteDetail`, button `modulationInspect`.
