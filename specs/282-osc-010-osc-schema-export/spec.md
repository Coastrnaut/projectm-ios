# Feature Specification: OSC-010 OSC Schema Export

**Feature Branch**: `feature/osc-010` (spec directory `282-osc-010-osc-schema-export`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement roadmap row OSC-010 (OSC schema export) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Export a local text file documenting active
routes and value ranges." Acceptance, verbatim: "Export matches registry IDs and includes no private network
credentials." P2, size S, depends on OSC-003 (integrated)."

Identifiers carry the roadmap ID: requirements `OSC-010-R1…`, success criteria `OSC-010-S1…`, research decisions
`OSC-010-D1…`, tasks `OSC-010-T01…`. Every OSC-001 to OSC-009 requirement and FR-068 as amended (ADR-0008) stay in
force. This row adds no network use: the file is written locally and handed to the system share sheet.

## Baseline: what exists today (audit of 2026-11-14, commit `69d4aa78`)

| Part of the row | Today | Gap |
|---|---|---|
| Route registry | OSC-003 `OSCParameterRoutes.table`: the `/projectm/test` route, `/projectm/param/<parameter ID>` per routable parameter (the four glow parameters), the built-in `/projectm/param/glow.*` aliases, then user aliases (`settings.osc.aliases`, OSC-004 learn adds to them). `OSCRoutesCoordinator` holds the table, the disabled set (`settings.osc.disabledRoutes`) and the routable descriptors | none: the export reads this table |
| Value ranges | MOD-001 `ParameterDescriptor` (continuous minimum, maximum, default, unit); SHD-003 metadata produces the same descriptors. OSC-003-R4: a route takes one number 0…1 (`f`, `i`, `h`, `d`) mapped linearly over the range; the test route takes a raw 0…1 value | **gap**: documented only in the OSC-003 contract, nowhere a controller author can read it from the app |
| Local file export | REC-012 `ShareFileStore` (`<tmp>/Sharing/<UUID>/<name>`, deleted on every share outcome) and `ActivitySharePresenter`; PERF-012 builds a text report the same way with a DEBUG `-uitestShareSimulation` stand-in | none: reused |
| Network identifiers | OSC-001 port (`settings.osc.port`), OSC-008 approved peers (`settings.osc.approvedPeers`), OSC-005 (merging in parallel) send destination `settings.osc.send.*` | must never reach the export |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative, local-first option.

- Q: Which format? → A: One Markdown file (`.md`, plain UTF-8 text with LF line endings): a short header and one pipe-table row per route. No JSON file alongside: one file keeps the share sheet to a single item, and the fixed-column table is easy to parse; a JSON form can be a later row (OSC-010-D1).
- Q: Which routes are listed? → A: Every route in the OSC-003 table (the routes the receiver knows), in table order: the test route, the standard routes in registry order, the built-in aliases, then the user aliases in stored order. Each row says whether the route is on; turned-off routes are listed so the file matches the registry, marked "off" (OSC-010-R2, R3).
- Q: Which columns? → A: Address, parameter ID, display name, arguments, input range, value range, unit, origin (test, standard, built-in alias, your alias), enabled (OSC-010-R3).
- Q: How is the date written? → A: From an injected clock, in UTC as `YYYY-MM-DDThh:mm:ssZ`, so the output is deterministic for a given instant and does not depend on the device's time zone; the file name carries the same UTC stamp (OSC-010-R4).
- Q: What must never be in the file? → A: Any network identifier: no IP addresses, ports (including the receiver's own port), peer names or approved peers, allow-list state, send destinations, device names, user names or received values. The builder takes only the route table, the disabled set, the descriptors, the app version and the date, so it cannot read them (OSC-010-R5).
- Q: Where is the button? → A: Settings › OSC › OSC Routes, a last section "Export routes…" with a footer saying what the file holds. It works whether OSC is on or off (OSC-010-R6).
- Q: How is the file handed off? → A: The REC-012 path: a temporary copy under `<tmp>/Sharing`, the system share sheet with that one file, deleted on every outcome; nothing is uploaded and nothing is stored (OSC-010-R7).
- Q: New settings keys? → A: None (OSC-010-R8).
- Q: ADR? → A: No: no default is overridden and network access is unchanged.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document the routes for a controller layout (Priority: P2)

A performer building a TouchOSC layout opens Settings › OSC › OSC Routes, taps "Export routes…", and saves or
sends the file from the share sheet. The file lists every address the app accepts, the parameter each drives, the
number it expects and the range it maps to.

**Independent Test**: build the export from a seeded route table; compare its rows with the table.

**Acceptance Scenarios**:

1. **Given** the shipped routes plus one user alias, **When** the export is built, **Then** every route's address appears exactly once and the set of (address, parameter ID) pairs equals the route table's.
2. **Given** the same, **Then** each row's value range and unit equal the parameter's registry metadata, and the test route says it takes a raw value.
3. **Given** a route turned off, **Then** its row says "off".
4. **Given** the same inputs and the same injected date and version, **When** the export is built twice, **Then** the text is byte-identical.

### User Story 2 - Nothing private leaves in the file (Priority: P2)

**Acceptance Scenarios**:

1. **Given** approved peers, a send destination, a receiver port and a device name stored in settings, **When** the export is built through the app, **Then** none of those strings and no IPv4 or IPv6 address pattern appears in the file.

### User Story 3 - Share it (Priority: P2)

1. **Given** OSC Routes, **When** the user taps "Export routes…", **Then** the share sheet opens with one `.md` file; when it closes (shared or cancelled) the temporary file is deleted.

### Edge Cases

- No user aliases: the table still has the test, standard and built-in routes.
- A write failure: the REC-012 failure notice, no sheet.
- A second tap while the sheet is open: ignored.
- An address or name containing `|`: escaped so the table stays valid (aliases cannot contain it; display names are app text).

## Requirements *(mandatory)*

- **OSC-010-R1**: Settings › OSC › OSC Routes offers "Export routes…", which writes one local Markdown file and offers it in the system share sheet.
- **OSC-010-R2**: The file lists every route of the OSC-003 table exactly once, in table order.
- **OSC-010-R3**: Each row gives address, parameter ID, display name, arguments, input range, value range, unit, origin and enabled state; ranges come from the parameter's registry descriptor.
- **OSC-010-R4**: The header gives the app version and the export time in UTC from an injected clock; the same inputs give the same bytes.
- **OSC-010-R5**: The file holds no network identifier (IP address, port, peer, allow-list entry, send destination, device or user name) and no received value.
- **OSC-010-R6**: The export is available whether OSC is on or off and needs no permission.
- **OSC-010-R7**: The file is a REC-012 temporary share copy, deleted on every share outcome; nothing is uploaded or stored.
- **OSC-010-R8**: No new settings keys.

## Success Criteria *(mandatory)*

- **OSC-010-S1**: A pure test shows the exported route set equals the route table (each address once, parameter IDs match) and ranges match the descriptors.
- **OSC-010-S2**: A pure test shows two builds with the same injected date and version are byte-identical.
- **OSC-010-S3**: A leak test with seeded peers, send destination, port and device values finds none of them and no IP pattern in the file.
- **OSC-010-S4**: An app test shows the export produces one share file and request; finishing the share deletes it.
- **OSC-010-S5**: A UI test under 30 s taps "Export routes…" and sees the share stand-in, reading the generated text through a DEBUG hook.

## Assumptions

- The share sheet on a device is checked by the `{device}` task; simulator results are never device evidence.
- Display names come from the same helper the OSC Routes screen uses (MIDI-003 `name`).
