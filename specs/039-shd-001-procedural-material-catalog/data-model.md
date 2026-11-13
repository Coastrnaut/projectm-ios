# Data Model: SHD-001 Procedural Material Catalog

## MaterialKind

Enum, `CaseIterable`, raw value = the material's name; catalog order = case order.

| Case | ID | Display name | Description |
|---|---|---|---|
| `gradient` | `material.gradient` | Gradient Field | Two colors blended across the screen, turning slowly. |
| `plasma` | `material.plasma` | Plasma | Soft interfering color waves. |
| `noiseFlow` | `material.noiseFlow` | Noise Flow | Layered noise in one tint, drifting slowly. |
| `tunnel` | `material.tunnel` | Ring Tunnel | Soft concentric rings moving outward. |
| `starfield` | `material.starfield` | Starfield | Small stars drifting across in three depths. |

## MaterialDefinition

| Field | Type | Rule |
|---|---|---|
| `kind` | `MaterialKind` | |
| `id` | `String` | `material.<raw value>` |
| `displayName`, `summary` | `String` | non-empty |
| `group` | `ParameterGroup` | id = `id`, name = display name |
| `parameters` | `[ParameterDescriptor]` | ≤ 8; IDs `material.<name>.<param>`; parameter *i* is uniform slot *i* |
| `fragmentFunction` | `String` | the shader entry point (`mat_<name>`) |
| `speedParameter`, `reactivityParameter` | `ParameterID` | every material has `speed` and `audioReactivity` |

## Parameters (the documented defaults)

Units are MOD-001 `ParameterUnit`s. Policy "cont" = `ModulationPolicy.continuousDefault`;
"manual" = `ModulationPolicy.discreteManual`. Colors are linear RGB, alpha 1.

| ID | Name | Kind | Range | Default | Unit | Policy |
|---|---|---|---|---|---|---|
| `material.gradient.colorA` | First color | color | 0…1 | (0.02, 0.04, 0.15) | none | manual |
| `material.gradient.colorB` | Second color | color | 0…1 | (0.30, 0.10, 0.40) | none | manual |
| `material.gradient.speed` | Rotation (turns per second) | continuous | −0.25…0.25 | 0.02 | perSecond | cont |
| `material.gradient.brightness` | Brightness | continuous | 0…1 | 0.6 | normalized | cont |
| `material.gradient.audioReactivity` | Audio reactivity | continuous | 0…1 | 0.25 | normalized | cont |
| `material.plasma.scale` | Scale (waves across the shorter side) | continuous | 0.5…8 | 2 | none | cont |
| `material.plasma.speed` | Speed (cycles per second) | continuous | 0…1 | 0.12 | perSecond | cont |
| `material.plasma.brightness` | Brightness | continuous | 0…1 | 0.45 | normalized | cont |
| `material.plasma.saturation` | Saturation | continuous | 0…1 | 0.6 | normalized | cont |
| `material.plasma.audioReactivity` | Audio reactivity | continuous | 0…1 | 0.25 | normalized | cont |
| `material.noiseFlow.scale` | Scale (cells across the shorter side) | continuous | 1…16 | 4 | none | cont |
| `material.noiseFlow.speed` | Drift (cells per second) | continuous | 0…1 | 0.08 | perSecond | cont |
| `material.noiseFlow.octaves` | Detail (octaves) | integer | 1…5 | 3 | count | manual |
| `material.noiseFlow.tint` | Tint | color | 0…1 | (0.10, 0.35, 0.45) | none | manual |
| `material.noiseFlow.brightness` | Brightness | continuous | 0…1 | 0.6 | normalized | cont |
| `material.noiseFlow.audioReactivity` | Audio reactivity | continuous | 0…1 | 0.25 | normalized | cont |
| `material.tunnel.ringDensity` | Rings (from the center to the shorter edge) | continuous | 2…24 | 8 | count | cont |
| `material.tunnel.speed` | Speed (rings per second) | continuous | −1…1 | 0.1 | perSecond | cont |
| `material.tunnel.contrast` | Contrast | continuous | 0…1 | 0.35 | normalized | cont |
| `material.tunnel.color` | Color | color | 0…1 | (0.85, 0.45, 0.20) | none | manual |
| `material.tunnel.brightness` | Brightness | continuous | 0…1 | 0.4 | normalized | cont |
| `material.tunnel.audioReactivity` | Audio reactivity | continuous | 0…1 | 0.25 | normalized | cont |
| `material.starfield.density` | Density (of grid cells with a star) | continuous | 0.05…1 | 0.35 | normalized | cont |
| `material.starfield.speed` | Speed (half screens per second) | continuous | 0…1 | 0.1 | perSecond | cont |
| `material.starfield.starSize` | Star size (of a grid cell) | continuous | 0.1…0.9 | 0.35 | normalized | cont |
| `material.starfield.color` | Color | color | 0…1 | (0.90, 0.90, 1.00) | none | manual |
| `material.starfield.brightness` | Brightness | continuous | 0…1 | 0.7 | normalized | cont |
| `material.starfield.audioReactivity` | Audio reactivity | continuous | 0…1 | 0.25 | normalized | cont |

28 parameters. IDs are permanent (MOD-001): never renamed or reused; retired IDs go into
`ProceduralMaterialCatalog.retiredIDs` (empty).

## MaterialParameterValues

Value type for one material: `definition`, the stored `ParameterValue` per parameter (defaults at
init). `set(_:for:)` → clamped stored value or `MaterialParameterError` (`unknownParameter`,
`nonFiniteValue`, `kindMismatch`, `unknownEnumCase`); a refused value leaves the stored one.
`slot(i)` → `SIMD4<Float>` (continuous/integer/boolean in `.x`, color as RGBA, enum as case index).
`double(_:)` reads a numeric value.

## MaterialMotion

| Field | Rule |
|---|---|
| `phase` (Double) | starts 0; `+= dt · speed · (1 + reactivity · audioLevel)` |
| `audioLevel` (Double, 0…1) | starts 0; moves toward the band level by ≤ `maxRisePerSecond` (4) · dt up, ≤ `maxFallPerSecond` (1) · dt down |
| `dt` | frame duration clamped to 0…`LayerFrameClock.maxFrameDuration` (0.1 s); NaN reads 0 |
| band level | mean of finite bands clamped to 0…1; 0 when there are none |

`reset()` returns to phase 0, level 0. Speed multiplier ≤ 2.

## MaterialUniforms (shader layout, 144 bytes)

`float2 size; float phase; float audio; float4 slots[8];` — phase is `Float(phase)`; size in
pixels.

## ProceduralMaterialLayer

CMP-001 `LayerSource`: `layerName` = material ID, fallback `.transparent`, `parameters`
(`MaterialParameterValues`), `motion` (read-only), `set(_:for:)`, `update(from: ParameterStore)`,
`resetMotion()`. `prepare` compiles the library once (kept across size changes) and builds the
pipeline for `rgba16Float`; `render` advances the motion, then one clear-and-draw pass.
