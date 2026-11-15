# Feature Specification: OUT-014 Output Profile Export

**Feature Branch**: `feature/out-014` (spec directory `288-out-014-output-profile-export`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement OUT-014 (Output profile export) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Save and restore display transforms as local files." Acceptance, verbatim:
"Import/export reproduces calibration on same display class." P2, M, depends on OUT-007 (integrated)."

Identifiers carry the roadmap ID: requirements `OUT-014-R1…`, success criteria `OUT-014-S1…`, tasks
`OUT-014-T01…`. Other features are cited by their own IDs: OUT-003 (output resolution), OUT-004 (aspect
correction, pixel aspect), OUT-006 (output mode), OUT-007 (corner pin), OUT-009 (colour calibration), OUT-011
(output diagnostics), MIDI-012 (profile files: export through the file mover, import through the file picker).

## Baseline: what exists today (audit of 2026-11-15, commit `c13a236e`)

| Area | Today | Gap for this row |
|---|---|---|
| Display transforms | `ExternalOutputSetting` holds every output choice as device-local `settings.externalDisplay.*` keys: fit, shape, pixel aspect (OUT-004), resolution and its percentage (OUT-003), output mode (OUT-006), corner pin (OUT-007, validated by `CornerPin`: range, convexity, foldover, area) and colour calibration (OUT-009, `DisplayCalibration`: gamma 0.5…2.5, trims 0.5…1.5). Each change is pushed to `ExternalDisplayCoordinator` and applied live. | They cannot leave the device: the library backup excludes them on purpose (they describe the display hardware). |
| Display description | OUT-011's `outputDiagnostics` reads native pixels, refresh rate and gamut from the live screen; the slot knows the screen's pixel aspect. | Nothing records which display a calibration was made for. |
| Profile files | MIDI-012 exports a versioned, sorted-key JSON document (`.pmmidi`) through the system file mover and imports at most 128 KB through the file picker, validating format, version and every value before anything changes. | No such file for output settings. |

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What does a profile hold? → A: Exactly the display-transform settings of Settings › External Display: fit,
  shape, pixel aspect, resolution choice and custom percentage, output mode, corner pin and colour calibration,
  plus an optional description of the display it was made for. Output mode belongs: it is part of what the
  display shows and lives in the same group. Rehearsal state, blackout and anything outside that section do not.
- Q: What describes the display ("display class")? → A: Native pixel size, the screen's own pixel aspect ratio,
  maximum refresh rate and colour gamut, read from OUT-011's live readings at export. Without a connected display
  the profile has no display description. No names, identifiers, serial numbers or network data ever.
- Q: What is "the same display class"? → A: Same native pixel width and height and the same screen pixel aspect
  (within 0.005); when both sides report a gamut, the same gamut. Refresh rate is recorded for information but not
  compared (the same projector may run at 50 or 60 Hz without changing geometry or colour).
- Q: What happens on a different class? → A: A warning names the differences and offers "Apply Anyway" or
  "Cancel"; nothing changes until the user chooses Apply Anyway. When the class cannot be compared (no display
  connected, or the profile has no description) the profile applies without a warning, and the message says the
  display could not be checked.
- Q: How strict is import? → A: Strict, all or nothing: at most 16 KB, the format tag, a known version, every
  field present, no unknown field, and every value valid by the same rules the settings use (the corner pin must
  pass OUT-007's checks; calibration values must lie inside OUT-009's ranges; the percentage inside OUT-003's
  range; names must be known). Out-of-range values are rejected, not clamped, because a clamped calibration would
  not reproduce the original. A rejected file changes nothing and shows one clear message.
- Q: Is anything new stored? → A: No. Applying a profile writes the existing `settings.externalDisplay.*` keys
  through the setting, exactly as the controls do. No new UserDefaults key, no profile list, no "last imported".

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Save a calibrated projector setup to a file (Priority: P1)

A VJ has corner-pinned and colour-calibrated a venue projector and wants to keep that setup for the next show.

**Why this priority**: The roadmap row's first half: transforms leave the device as a local file.

**Independent Test**: Set a corner pin and a calibration, tap "Export output profile…", save the file; the file
holds every display-transform value and the display description, nothing else.

**Acceptance Scenarios**:

1. **Given** custom output settings and a connected display, **When** the user exports, **Then** the system file
   export opens with one profile file holding all display-transform values and the display's description.
2. **Given** no display connected, **When** the user exports, **Then** the file holds the values and no display
   description.
3. **Given** any export, **Then** the file contains no device name, identifier, display identifier or network
   address.

### User Story 2 - Restore it on the same projector (Priority: P1)

Back at the venue, possibly after resetting the settings, the VJ imports the profile.

**Why this priority**: The roadmap acceptance: import reproduces the calibration on the same display class.

**Independent Test**: Export, reset every output setting, import with the same display connected: every value and
the live external output equal the originals, with no warning.

**Acceptance Scenarios**:

1. **Given** an exported profile and the same display class connected, **When** the user imports it, **Then**
   every setting equals the exported value exactly and the connected display shows the restored corner pin and
   calibration at once, without a warning.
2. **Given** a profile made for a different display class, **When** the user imports it, **Then** a warning names
   the differences; Apply Anyway applies everything, Cancel changes nothing.

### User Story 3 - Bad files never damage the setup (Priority: P2)

**Independent Test**: Import a damaged, oversized, newer-version or invalid file; nothing changes and a message
says why.

**Acceptance Scenarios**:

1. **Given** a file whose corner pin folds the picture (a bow tie), calibration is out of range, that is truncated,
   too large, of an unknown version or not a profile, **When** it is imported, **Then** no setting changes and the
   message names the problem.

### Edge Cases

- The user cancels the file export or the picker: nothing changes, no temporary file is left behind.
- A profile from a newer app version: refused with "made by a newer version".
- A display connects or disconnects while the warning is shown: the choice applies to the profile already read.
- A recording holds the output placement: the values apply as the controls do (OUT-003/004 placement after the
  hold; corner pin, mode and calibration at once).

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-014-R1**: Settings › External Display MUST offer "Export output profile…" and "Import output profile…".
- **OUT-014-R2**: Export MUST write one versioned profile document holding fit, shape, pixel aspect, resolution
  mode, custom percentage, output mode, corner pin (four points) and calibration (gamma, red, green, blue), and,
  when a display is connected, its class (native width and height, screen pixel aspect, refresh rate, gamut).
- **OUT-014-R3**: The document MUST contain no device or display name, identifier or network address.
- **OUT-014-R4**: Export MUST go through the system file export as a local file; the app uploads nothing and
  removes its temporary copy on every outcome.
- **OUT-014-R5**: Import MUST read a user-picked file of at most 16 KB and validate format, version, field set and
  every value with the rules the settings use, before anything changes.
- **OUT-014-R6**: An invalid file MUST change nothing and show one message naming the problem.
- **OUT-014-R7**: A valid profile MUST apply all values at once through the output setting, so the connected display
  updates immediately, and persist them in the existing setting keys only.
- **OUT-014-R8**: When the profile's display class differs from the connected display's, the app MUST warn, naming
  the differences, and apply only on "Apply Anyway".
- **OUT-014-R9**: The same class (spec Clarifications) or a class that cannot be compared MUST apply without a
  warning; the latter says that the display could not be checked.
- **OUT-014-R10**: Round trip: exporting and importing MUST reproduce every value exactly.

### Key Entities

- **Output profile**: the display-transform values and an optional display class; versioned document format.
- **Display class**: native pixel size, screen pixel aspect, refresh rate, gamut.
- **Class match**: same, different (with the list of differences), or unknown.

## Success Criteria *(mandatory)*

- **OUT-014-S1**: An export followed by an import on the same display class reproduces 100 % of the values (corner
  points and calibration bit for bit) and the live display output, with no warning.
- **OUT-014-S2**: 100 % of the invalid files in the test set (bow tie, out-of-range calibration, truncated,
  oversized, wrong version, unknown field) are refused and change nothing.
- **OUT-014-S3**: A different display class always warns before anything changes.
- **OUT-014-S4**: No exported file contains a device name, identifier or address.

## Assumptions

- The profile is a local file the user manages (Files, AirDrop); the app keeps no list of profiles.
- The calibration and corner pin are reproduced exactly as numbers; whether the picture looks identical on a real
  projector is the `{device}` check.
- Not in the library backup (the settings themselves are excluded there); unchanged.
