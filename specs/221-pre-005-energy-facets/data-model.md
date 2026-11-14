# Data Model: PRE-005 Preset Energy Facets

## PresetEnergy (enum, Codable by raw value)

| Case | Name | Spoken label | Score range (thousandths of a level) |
|---|---|---|---|
| calm | Calm | Calm motion | 0 ..< 4,000 |
| moderate | Moderate | Moderate motion | 4,000 ..< 16,000 |
| energetic | Energetic | Energetic motion | ≥ 16,000 |

## PresetMotionScore

- `version = 1` (bumped when the score computation changes; the PNG field and index carry it).
- `sampleFrames = [36, 40, 44]` (0-based within PRE-001's 45 frames).
- `score(samples: [[UInt8]], width:, height:) -> Int?` — nil for fewer than two samples or wrong sizes.
- `energy(for score: Int) -> PresetEnergy`.

## PresetMotionPNG

- Keyword `projectM-motion`; text `"<version>:<score>"`.
- `embed(score:in:) -> Data?` (nil when the bytes are not a PNG); `score(in:) -> Int?` (nil without the field, for another version, or for a malformed value).

## PresetMotionIndex (motion.json)

| Field | Type | Rule |
|---|---|---|
| schemaVersion | Int | 1; anything else (absent = 0) → rebuilt |
| scoreVersion | Int | `PresetMotionScore.version`; anything else → rebuilt |
| entries | [presetID: Entry] | Entry = `{thumbnailID: String, score: Int}`; dropped when score < 0 or thumbnailID empty |

## PresetMotionStore (actor)

`open`, `lastRepair`, `snapshot`, `record(presetID:thumbnailID:score:)`, `invalidate(presetID:keepingThumbnailID:)`,
`retainOnly(_:)`, `flush`, `saveCount`.

## PresetEnergyFilter

`init(scores: [presetID: Int])`; `energies`; `matching(any:) -> Set<String>`; `count(of:)`; `chips`; `presetCount`.

## App state (PresetCoordinator, in memory)

`selectedEnergies: [PresetEnergy]`, `motionVersion: Int`, cached filter per (version, library).
