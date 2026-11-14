# Research: SHD-003 Shader Parameter Metadata

## SHD-003-D1 Format: JSON text constants, strict reader
- **Decision**: one JSON document per material as a Swift string constant in ProceduralMaterials, decoded by
  `JSONDecoder` into a small JSON value enum (`null`/bool/number/string/array/object), then read by hand so
  every key is checked (unknown keys rejected with their path).
- **Rationale**: data, not code; `JSONDecoder` keeps booleans and numbers apart on Darwin and Linux (it never
  turns `1` into `true`), unlike `JSONSerialization`'s `NSNumber`; Codable structs ignore unknown keys.
- **Alternatives**: Swift literals (no unknown-key check, code), bundle resources (the package has no
  resources by design; a run-time file read is a failure path for constant content).

## SHD-003-D2 Slot binding and the shader cross-check
- **Decision**: each parameter states `slot`; slot must equal its position (MaterialParameterValues and the
  uniform struct already put parameter *i* in slot *i*). A plain-Swift scanner finds the fragment function
  `mat_<name>` in the shader source (brace matching) and records each `u.slots[N]` read with its swizzle:
  one component (`.x`) or a vector (`.rgb`, `.xyz`, `.rgba`, `.xyzw`, or no swizzle). Validation: every read
  slot is declared; vector reads only on colors; single reads only on non-colors. Unread slots are allowed
  (speed and audio reactivity drive the CPU motion).
- **Rationale**: catches the realistic mistakes (wrong slot, color/number swap, forgotten parameter) without a
  Metal parser; runs on Linux in tests and once per process on device.
- **Alternatives**: Metal reflection (`MTLFunction` argument reflection sees only the `float4 slots[8]` array,
  not how each element is read); free slot assignment (needs a remapping table for no benefit).

## SHD-003-D3 Kinds and policies
- `float` → `.continuous(min,max,default,step)`, `.continuousDefault`; `int` → `.integer(…, step)`,
  `bool` → `.boolean`, `enum` → `.enumeration`, `color` → `.color`, all `.discreteManual` (SHD-001's rule for
  discrete values: no per-frame jumps). Units: MOD-001 `ParameterUnit` raw values (`none`, `normalized`,
  `fractionOfOutput`, `seconds`, `perSecond`, `degrees`, `count`); default `none`.

## SHD-003-D4 Gradient Shape
- **Decision**: `material.gradient.shape` enum (`linear`, `radial`), slot 5. Shader: `shape == 1` uses
  `t = smoothstep(0.05, 0.75, length(p) * (1 + 0.15 * cos(a)))` (boundary breathes with the rotation phase,
  ≤ one cycle per phase unit); otherwise the SHD-001 code path unchanged, so the linear golden holds.

## SHD-003-D5 Control builder
- Controls: `slider` (float), `stepper` (int), `picker` (enum), `toggle` (bool), `color` (color). The value is
  the stored value when it is valid for the spec (kind, enum case, finite, in range after clamping is not
  applied: an out-of-range number is clamped for display) else the default. The app formats display and
  spoken text with UIX-003's `ParameterValueText` from the mapped descriptor.

## SHD-003-D6 Failure handling of bundled metadata
- The catalog validates at first use; an invalid bundled document stops with `preconditionFailure` naming the
  error. Unit tests (CI) validate every document, so a broken document never ships. The layer's `prepare`
  additionally runs the slot check against the compiled source and throws `.resourceUnavailable` on mismatch.
