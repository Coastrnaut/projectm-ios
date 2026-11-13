# Data Model: MED-014 Safe Media Decoder

No stored data is added. The new value types (target `MediaSniffing`, plain Swift):

## ImageContainer

`png | jpeg | heif | other` — what the first bytes say. `other` (GIF, TIFF/DNG, WebP, BMP, unknown) is
left to ImageIO with MED-001's checks.

## ImageHeaderFacts

| Field | Meaning |
|---|---|
| `container` | `ImageContainer` |
| `width`, `height` | from IHDR / SOF / largest `ispe`; nil for `other` (and HEIF without `ispe`) |

`pixelCount` = width × height with overflow saturating to `Int.max`.

## MovieContainerFacts

| Field | Meaning |
|---|---|
| `videoTrackCount` | tracks whose `hdlr` is `vide` |
| `trackCount` | all tracks |
| `codec` | four-character code of the first video track's first sample description (nil when none) |
| `codedWidth`, `codedHeight` | that sample description's width and height (0 when none) |
| `boxesVisited` | box headers read (≤ 4,096) |

## MediaSniffError (Error, Equatable)

| Case | Meaning | Image mapping | Video mapping |
|---|---|---|---|
| `empty` | no bytes | `.notAnImage` | `.notAVideo` |
| `unrecognized` | not a movie container's first bytes (movies only; images return `.other` facts instead) | — | `.notAVideo` |
| `truncated` | a length points past the end / end marker missing | `.damaged` | `.damaged` |
| `corrupt` | a field is illegal, CRC mismatch, walk bound exceeded | `.damaged` | `.damaged` |
| `unreadable` | the byte source failed to read | `.unreadable` | `.unreadable` |

## MovieSniffLimits

`maxBoxes` 4,096; `maxDepth` 8; `maxTracks` 64; `maxEntryBytes` 4,096.

## Layer states (unchanged)

`ImageLayerState.failed(ImageImportError)`, `VideoLayerState.failed(VideoImportError)`: the typed outcome
of a load. A failed video layer stays failed until its content changes.
