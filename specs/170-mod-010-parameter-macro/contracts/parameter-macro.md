# Contract: Parameter macro (MOD-010)

## M1 Target value

For macro value `m` (limited to 0…1, non-finite → 0), target `t` and descriptor `d`:

```
p = t.curve.apply(t.inverted ? 1 − m : m)
x = LinearMapping.interpolate(from: lo, to: hi, at: p)      // lo/hi = t.outputMinimum/Maximum ?? d's bounds
continuous: clamp(x, d.minimum, d.maximum)
integer:    clamp(d.minimum + round((x − d.minimum) / step) · step, d.minimum, d.maximum)
enum:       d.cases[clamp(round(x), 0, cases − 1)].id      // lo/hi in case positions
```

Exact at m = 0 and m = 1 (MOD-003/MOD-004 ends). Boolean and color targets are refused.

## M2 Skips

`evaluate` never traps. A target is skipped, with its index and a problem, when: its parameter is not
registered (`unknownParameter`); its kind is boolean or color (`unsupportedKind`); its curve is invalid
(`invalidCurve`); its range is non-finite or minimum > maximum (`invalidRange`); it repeats an earlier
target's parameter (`duplicateParameter`); it is beyond 8 targets (`beyondLimit`). The other targets apply.

## M3 Scene list

`"macros": [{"name": "Glow sweep", "value": 0.5, "targets": [{"parameter": "effect.bloom.intensity",
"curve": "easeIn:2.0", "minimum": 0, "maximum": 1, "invert": false}]}]` — optional, written only when set,
every field verbatim; at most 64 entries decoded, the first 8 used. `name` (string) and `value` (finite
number) are required; `targets` is a list (≤ 64). Warnings: `invalidMacro` (entry or target malformed,
invalid curve or range, unsupported kind, duplicate, beyond a limit) and `unknownMacroTarget` (unregistered
parameter). Setting a macro rewrites only its `value`.

## M4 App

Setting a macro writes each assignment through the UIX-003 target of its parameter (the Settings path); a
registered parameter without an app control is skipped and reported. One macro change is one undo step
("Macro <name> <percent>", key `macro.<index>`). Opening a scene restores macros without applying them.

## M5 UI

Settings › Macros, shown when the scene has macros: slider `macro.<index>` (label = name, value spoken as a
percent, 1% steps, `.accessibleParameter`), and per usable target a read-only row
`macroTarget.<index>.<parameter ID>` whose label is "<display name>: <value text>".
