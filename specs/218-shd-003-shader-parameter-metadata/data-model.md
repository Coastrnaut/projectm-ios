# Data Model: SHD-003 Shader Parameter Metadata

## ShaderMetadataDocument (JSON, schema 1)
| Key | Type | Required | Rule |
|---|---|---|---|
| `schema` | number | yes | exactly 1 |
| `variant` | string | yes | well-formed ID segment (lowercase start, letters/digits) |
| `name` | string | yes | 1-64 characters |
| `summary` | string | yes | 1-200 characters |
| `parameters` | array | yes | 1-8 parameter objects |

### Parameter object
| Key | Kinds | Required | Rule |
|---|---|---|---|
| `id` | all | yes | well-formed segment, unique in the document |
| `label` | all | yes | 1-64 characters |
| `kind` | all | yes | `float`, `int`, `bool`, `enum`, `color` |
| `slot` | all | yes | integer equal to the parameter's position (0-based) |
| `unit` | float, int | no | MOD-001 unit raw value; default `none` |
| `min`, `max` | float, int | yes | finite; min < max; integers whole |
| `step` | float, int | float: yes; int: no (1) | > 0 and ≤ max − min; int whole |
| `default` | all | yes | float/int: in range (int on a step); bool: boolean; enum: a case ID; color: 4 numbers in 0…1 |
| `cases` | enum | yes | 2-16 objects `{id, label}`; IDs well-formed and unique; labels 1-64 |

Keys not listed for a kind are rejected (`keyNotAllowed`). Unknown keys anywhere are rejected (`unknownKey`).

## ShaderParameterSpec (validated)
`id`, `label`, `slot`, `unit`, `kind: .float(min,max,step,default) | .int(min,max,step,default) | .bool(default) | .enumeration(cases, default) | .color(default)`.

## ValidatedShaderMetadata
`variant`, `name`, `summary`, `parameters: [ShaderParameterSpec]`; methods: `descriptors(idPrefix:group:)`,
`check(against: ShaderSlotUsage)`.

## ShaderSlotUsage
`function`, `reads: [Int: SlotRead]` with `SlotRead = .component | .vector | .both`.

## ShaderParameterControl
`parameterID`, `label`, `kind: .slider | .stepper | .picker | .toggle | .color`, `range` (numbers),
`step` (numbers), `unit`, `options: [(id,label)]` (picker), `defaultValue`, `value: ParameterValue`.

## Required material parameters
Every material document includes `speed` (float) and `audioReactivity` (float) (SHD-001 motion).
