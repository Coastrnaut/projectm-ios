# Research: OSC-003 OSC Parameter Routes

## OSC-003-D1 Address scheme
Decision: one standard rule, `/projectm/param/<parameter ID>`, plus built-in friendly aliases
`/projectm/param/glow.<name>`. Rationale: the parameter ID is MOD-001's stable identifier, so the rule
needs no table maintenance and survives renames of display names; the aliases are what a person types.
Alternatives: per-group paths (`/projectm/glow/intensity`) duplicate the ID scheme; evaluating OSC
patterns would let one message touch many parameters and is refused by the row ("never evaluate arbitrary
addresses").

## OSC-003-D2 Routable set
Decision: `OSCParameterRoutes.routable` = allows external control ∧ continuous ∧ applied per frame — the
MIDI-003 learnable rule, today the four glow parameters. A parameter the app does not apply would accept a
value with no visible effect.

## OSC-003-D3 Value path and merging
Decision: dispatcher → `liveValues` (memory) → gated main-actor refresh (OSC-009-R11, ≤ about 30 Hz) →
`ExternalLiveValues` merge with MIDI → `NativeSpectrumHost.externalValues` → MOD-002 → ACC-012 clamp.
Newest change wins per parameter so a performer touching either controller sees it act. Alternatives:
"MIDI always wins" hides OSC silently; a separate OSC path would bypass the clamp order (ADR-0057).

## OSC-003-D4 Normalized values only
Decision: 0…1 positions over the registry range (MOD-003 linear), clamped first. A raw-unit option was
rejected: units differ per parameter (radius is a fraction of the output) and raw values invite
out-of-range input.

## OSC-003-D5 User aliases
Decision: ≤ 16, `[A-Za-z0-9/._-]`, 2-64 bytes, starts with `/`, no `//`, no trailing `/`, never under
`/projectm/`. The character set excludes every OSC pattern character and spaces, so an alias is always a
literal address. Stored as text lines; invalid lines are dropped on load.

## OSC-003-D6 Persistence and backup
Decision: two keys, both in the FILE-005 backup and FILE-011 erase; they carry no network data.
