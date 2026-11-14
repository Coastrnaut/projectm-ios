# Feature Specification: OSC-003 OSC Parameter Routes

**Feature Branch**: `feature/osc-003` (spec directory `191-osc-003-parameter-routes`)

**Created**: 2026-11-14

**Status**: Implemented

**Input**: User description: "Implement roadmap row OSC-003 (OSC parameter routes) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Map allowlisted OSC addresses to
stable parameter IDs." Acceptance, verbatim: "Known route changes intended target and unknown route is
ignored." P1, effort M, depends on OSC-001 and MOD-001 (integrated)."

Identifiers carry the roadmap ID: requirements `OSC-003-R1…`, success criteria `OSC-003-S1…`, research
decisions `OSC-003-D1…`, tasks `OSC-003-T01…`. FR-068 as amended on 2026-11-12 (ADR-0008, networking for
OSC) and every OSC-001, OSC-002, OSC-007 and OSC-009 requirement stay in force. Network access is not
widened: the transport, its local-only scope and the listener lifecycle are unchanged.

## Baseline: what exists today (audit of 2026-11-14, commit `0cad6578`)

| Part of the row | Today | Gap |
|---|---|---|
| OSC receiver | OSC-001/002: UDP listener (`OSCTransport/`, the only allowed network path), bounded decoder, `OSCDispatcher` writing a `ParameterStore` under `ModulationPolicy.allowsExternalControl`; settings `settings.osc.enabled`, `settings.osc.port` | none |
| Address → parameter | One fixed route, `/projectm/test` → `osc.receiver.testValue`, which feeds nothing that renders (OSC-001-R7). The catalog comment says "OSC-003 replaces the fixed route with an allowlisted route table" | **gap**: no route to any registry parameter (no `/projectm/glow/intensity` or similar) |
| Rate limiting (OSC-009) | Per source and global before decoding; per **target** (`ParameterID`) before applying, with latest-value coalescing | none: targets are already parameter IDs, so new routes are limited for free |
| Live values (MIDI-003) | `MIDIMappingCoordinator.liveValues` (memory only) → `NativeSpectrumHost.externalValues` → base glow → MOD-002 bindings → ACC-012 clamp (`GlowModulationOrder`) | **gap**: only MIDI feeds `externalValues`; a second source would overwrite it |
| Unknown addresses | Counted in `ignored` | partial: not told apart from wrong arguments |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which addresses are routes? → A: An allowlist built from the registry: the OSC-001 test route, one standard route `/projectm/param/<parameter ID>` per routable parameter, four built-in friendly aliases `/projectm/param/glow.intensity|radius|threshold|knee`, and the user's validated aliases. Addresses are matched literally; OSC pattern matching (`*`, `?`, `[]`, `{}`) is never evaluated, so no address can reach a parameter that is not on the list (OSC-003-R1, R2).
- Q: Which parameters are routable? → A: The same rule as MIDI-003 learn: external control allowed (MOD-001 policy), continuous, and applied by the app per frame. Today that is the four glow parameters (`effect.bloom.intensity`, `radius`, `threshold`, `knee`). A wider set waits for the app to apply more parameters per frame (OSC-003-R3).
- Q: What does a route's number mean? → A: A normalized position: one `f`, `i`, `h` or `d` argument, clamped to 0…1 and mapped linearly (MOD-003) over the registry range, exactly like a MIDI control. A raw value in the parameter's own unit is not offered: one convention is easier to explain and cannot exceed the range. The OSC-001 test route keeps its raw 0…1 value (OSC-003-R4).
- Q: What happens to other argument types, booleans and extra arguments? → A: Ignored (`wrongArguments`, counted in `ignored`); booleans and impulses are not numbers (OSC-003-R4).
- Q: Which value path? → A: The MIDI-003 live-value path: OSC live values are merged with MIDI's (the newest change wins per parameter; when one source stops, the other's value is used) into the native host's external values, then MOD-002 and the ACC-012 clamp. Live values are memory only, never stored or put in a scene (OSC-003-R5).
- Q: When do OSC live values end? → A: When the user turns OSC off, and for a parameter when no enabled route reaches it any more. A background pause keeps them, like MIDI (OSC-003-R5, R6).
- Q: Does the rate limiter still apply? → A: Yes, unchanged: the target is the parameter ID, and the mapped value is what is held and flushed (OSC-003-R8).
- Q: How are unknown addresses reported? → A: Counted, never stored: `unknownAddresses` (also part of `ignored`), shown in OSC Routes as "Ignored addresses N". No address text is kept (OSC-003-R2).
- Q: Route enable/disable? → A: Every route has a toggle in Settings › OSC › OSC Routes; all are on by default (OSC itself is off by default). The disabled addresses are stored under `settings.osc.disabledRoutes` (OSC-003-R6, R9).
- Q: User aliases? → A: Yes, small and validated: at most 16; `/` plus 1-63 more of `A-Z a-z 0-9 / . _ -`, no `//`, no trailing `/`, not under `/projectm/` (reserved), unique, to a routable parameter. Stored as `<address>=<parameter ID>` lines under `settings.osc.aliases`; unreadable lines and aliases to parameters no longer routable are dropped on load (OSC-003-R7, R9).
- Q: Does FILE-005 backup include the new keys? → A: Yes, both are included (like `settings.midi.mappings`): they hold only addresses and parameter IDs, and they are erased with Settings (FILE-011) (OSC-003-R9).
- Q: Is an ADR needed? → A: No. No default is overridden and network access is unchanged; the routes are inside ADR-0008's ruling.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A controller drives the glow through a known address (Priority: P1)

A performer turns on OSC and sends `/projectm/param/glow.intensity 0.25` from a controller on the local
network; the glow intensity becomes 0.25. A message to any address that is not listed changes nothing.

**Acceptance Scenarios**:

1. **Given** OSC routes as shipped, **When** `/projectm/param/glow.intensity` arrives with `0.25`, **Then** the glow intensity's value is 0.25 and no other parameter changes.
2. **Given** the same, **When** `/projectm/unknown 1.0` arrives, **Then** every parameter value is byte-identical and the ignored-address counter goes up by one.
3. **Given** the same, **When** `/projectm/param/glow.intensity "text"` arrives, **Then** it is ignored.
4. **Given** the alias turned off, **When** it arrives with a number, **Then** it is ignored.

### User Story 2 - Choose which routes are open (Priority: P2)

In Settings › OSC › OSC Routes the user sees each address with its target and turns routes off or on, and
may add a short alias of their own.

### Edge Cases

- NaN or infinity: refused, nothing held (OSC-009).
- A bundle mixing known and unknown addresses: each message is routed or ignored on its own.
- Every route to a parameter turned off: its OSC live value is dropped and the manual value returns.
- Strict sensory safety: the mapped value is capped by ACC-012 like a MIDI value.

## Requirements *(mandatory)*

- **OSC-003-R1**: The route table is the test route, `/projectm/param/<parameter ID>` for every routable parameter, the built-in glow aliases, then valid user aliases; addresses are unique.
- **OSC-003-R2**: Only an exact address in the active table reaches a parameter; any other message is ignored with no state change and counted (`unknownAddresses`, `ignored`).
- **OSC-003-R3**: Routable parameters are the MOD-001 descriptors that allow external control, are continuous and are applied by the app per frame.
- **OSC-003-R4**: A route's message carries exactly one number (`f`, `i`, `h`, `d`), clamped to 0…1 and mapped linearly over the registry range; any other argument list is ignored.
- **OSC-003-R5**: Applied values become OSC live values (memory only), merged with MIDI-003's (newest change wins) into the same host path, then MOD-002 and the ACC-012 clamp; turning OSC off forgets them.
- **OSC-003-R6**: Each route can be turned off and on; a change applies from the next message, and a parameter no enabled route reaches loses its live value.
- **OSC-003-R7**: User aliases are validated (format, reserved prefix, uniqueness, routable target, at most 16).
- **OSC-003-R8**: The OSC-009 limits apply unchanged; the held value is the mapped value.
- **OSC-003-R9**: `settings.osc.disabledRoutes` and `settings.osc.aliases` hold addresses and parameter IDs only; they are in the FILE-005 backup, the FILE-011 erase, the UI-test reset and the device-test allowed keys.
- **OSC-003-R10**: Settings › OSC has an "OSC Routes" screen listing every route with its target, origin and toggle, the ignored-address count, and the alias form.

## Success Criteria *(mandatory)*

- **OSC-003-S1**: The acceptance fixture (decoder path, fake clock) proves scenarios 1-4.
- **OSC-003-S2**: Rate limiting and the Strict clamp are shown to apply to routed values.
- **OSC-003-S3**: Alias validation refuses every invalid case listed in R7.
- **OSC-003-S4**: A UI test under 30 s opens OSC Routes from `-uitestSettingsSection osc` and toggles a route.
- **OSC-003-S5**: Network checks unchanged: `check_compliance` and `check_network_symbols` pass with no new allowance.

## Assumptions

- Device testing with a real controller on Wi-Fi is OSC-001's `{device}` task; this row adds nothing that needs a device beyond it.
