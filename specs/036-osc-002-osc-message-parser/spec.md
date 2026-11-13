# Feature Specification: OSC-002 OSC Message Parser

**Feature Branch**: `feature/osc-002` (spec directory `036-osc-002-osc-message-parser`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement roadmap row OSC-002 (OSC message parser) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Decode OSC address, type tags,
int, float, string and bundles safely." Acceptance, verbatim: "Malformed packet is rejected without
crash or unbounded allocation." Priority P0, depends on MOD-001. Extend OSC-001's bounded decoder
(strings, blobs, no-payload tags, 64-bit numbers, bundles with a time tag, bounded nesting and
element count); do not write a second decoder."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `OSC-002-R1…`, success criteria `OSC-002-S1…`, tasks `OSC-002-T01…`. OSC-001's
requirements (`specs/032-osc-001-osc-receiver/spec.md`), FR-068 as amended on 2026-11-12 and
ADR-0008's networking ruling stay in force.

## Baseline: what exists today (audit of 2026-11-13, commit `608f1a8`)

The row's gap status is "Gap candidate". The audit confirms a partial gap.

| Area | Today (OSC-001) | Gap for this row |
|---|---|---|
| Messages | One OSC message per datagram: `/`-prefixed printable-ASCII address of at most 255 bytes, a `,` type tag string, at most 16 arguments, datagram at most 1,472 bytes. | — (kept) |
| Argument types | 32-bit float `f` and 32-bit integer `i` only; anything else is rejected as `unsupportedTypeTag`. | No string, blob, boolean, nil, impulse, 64-bit integer or double. |
| Bundles | A datagram starting with `#bundle` is rejected as `bundleUnsupported`. | No bundle decoding, no time tag, no nesting rules. |
| Safety | Every read bounds-checked; no allocation sized from a packet-declared length; typed errors with stable `reason` keys; a fixed-seed 20,000-packet fuzz with re-encode round trip. | Blob sizes and bundle element sizes are packet-declared lengths: they need the same discipline. |
| Receiver | Applies only `/projectm/test` with one numeric argument; counters per reject reason. | Must handle a bundle datagram. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative option.

- Q: What are the bundle limits? → A: Nesting depth at most 4 (the top-level bundle is level 1, so a bundle inside three nested bundles is the deepest allowed) and at most 64 elements in one datagram, counting messages and nested bundles at every level. An element size must be positive, a multiple of 4 and no larger than the bytes left in its enclosing bundle; a bundle needs its 16-byte header (`#bundle` marker and time tag). An empty bundle is valid. The message limits stay OSC-001's (16 arguments per message, address ≤ 255 bytes, datagram ≤ 1,472 bytes). Rejections: `bundleTooDeep`, `tooManyElements`, `invalidElementSize`, `truncatedBundle` (OSC-002-R5, R6).
- Q: Which argument types does the parser accept, and which count as numbers for the receiver? → A: `i`, `f` (OSC-001), `s` string, `b` blob, `h` 64-bit integer, `d` double, and the no-payload tags `T` true, `F` false, `N` nil, `I` impulse. `h` and `d` are numbers (a controller sending a double fader reaches the test value; the store clamps it); `s`, `b`, `T`, `F`, `N`, `I` are not numbers, so `/projectm/test T` is ignored as wrong arguments. Mapping booleans or impulses to values is a routing decision for OSC-003. Arrays `[ ]`, `t`, `c`, `r`, `m`, `S` and any other tag stay `unsupportedTypeTag` (OSC-002-R4).
- Q: How does the receiver treat a bundle's time tag in this row? → A: It decodes the whole datagram first, then applies every message in packet order (depth-first) immediately, whatever the time tag says; nothing is queued or delayed. OSC-006 owns scheduling by time tag and the late-message policy and will replace this immediate path. Counters: `received` and `rejected` stay per datagram, a new `bundles` counter counts accepted bundle datagrams, and `applied`/`ignored` count per message, so a bundle with three messages adds three. A bundle with any malformed element is rejected as a whole and applies nothing (OSC-002-R10).
- Q: What text may a string argument hold? → A: Any bytes except NUL that form valid UTF-8 (OSC 1.0 says ASCII; UTF-8 is what current controllers send and is a superset). Invalid UTF-8 is rejected as `invalidString`, so a decoded string always re-encodes to the same bytes. Strings and blobs have no separate length cap: the datagram limit bounds them. The address rule stays printable ASCII (OSC-002-R2).
- Q: How do the reject reasons change, and what happens to `bundleUnsupported`? → A: OSC-001's twelve keys keep their names and meanings. New keys: `invalidString`, `invalidBlobSize` (negative, or the blob plus padding does not fit in the bytes left), `truncatedBundle`, `invalidElementSize`, `bundleTooDeep`, `tooManyElements`. A blob shorter than its 4-byte size word is `truncatedArgument`, like a short number. The packet decoder never returns `bundleUnsupported`; the message-only decode entry point that OSC-001 callers use still returns it for a bundle, so those callers keep their behavior. A bundle element that does not start with `/` or `#bundle` is decoded as a message and is rejected as `invalidAddress` (OSC-002-R8, R11).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Controllers that send strings, booleans or bundles still work (Priority: P1)

A performer's OSC controller (TouchOSC-style apps, Max/MSP, Pure Data, SuperCollider) sends a
fader as `/projectm/test 0.42` wrapped in a bundle, or adds a label string or a boolean to other
messages. The app decodes every well-formed packet: the fader inside the bundle reaches the test
value, and messages with types the app understands but does not route are decoded and ignored,
not counted as malformed.

**Why this priority**: It is the row's observable behavior. Many controllers wrap every message
in a bundle, so without bundles the receiver would ignore them entirely.

**Independent Test**: Decode hand-written byte fixtures for each new type and for nested bundles
and compare with the expected decoded value; send a bundle over loopback and see the test value
change.

**Acceptance Scenarios**:

1. **Given** a message with a string, a blob, a 64-bit integer, a double, true, false, nil and
   impulse arguments, **When** it is decoded, **Then** every argument has the exact value and type
   written in the fixture, and encoding it again gives the same bytes.
2. **Given** a bundle holding `/projectm/test 0.42`, **When** the receiver gets it, **Then** the
   test value becomes 0.42.
3. **Given** a bundle holding a nested bundle and three messages, **When** it is decoded, **Then**
   the elements come out in packet order with the time tags written in the fixture.

---

### User Story 2 - Malformed or hostile packets cannot crash the app or exhaust memory (Priority: P1)

Anyone on the local network can send the app arbitrary datagrams while OSC is on. A truncated
packet, a blob that claims to be 2 GB, a bundle nested 50 levels deep or a bundle with hundreds of
tiny elements is rejected with a specific reason; the app keeps rendering and memory use stays
bounded by the datagram size.

**Why this priority**: It is the row's acceptance criterion and the reason for P0.

**Independent Test**: A table of malformed packets, each mapped to its exact reason, plus a
fixed-seed fuzz that mutates valid packets and generates random bytes.

**Acceptance Scenarios**:

1. **Given** a valid packet truncated at any 4-byte boundary, **When** it is decoded, **Then** it is
   rejected with a typed reason and nothing is applied.
2. **Given** a blob whose declared size is negative or larger than the bytes left, **When** it is
   decoded, **Then** it is rejected before any memory for the blob is reserved.
3. **Given** bundles nested deeper than the limit or holding more elements than the limit,
   **When** they are decoded, **Then** they are rejected with their own reasons.
4. **Given** a bundle where one element is malformed, **When** the receiver gets it, **Then** the
   whole datagram is rejected and no element of it is applied.

---

### User Story 3 - Existing OSC-001 behavior does not change (Priority: P2)

Everything OSC-001 accepted is still accepted with the same value, everything it rejected for a
reason other than an unsupported type or a bundle is still rejected with the same reason key, and
the address and routing rules are unchanged.

**Why this priority**: The receiver shipped in OSC-001; its counters and tests depend on the keys.

**Independent Test**: OSC-001's decoder, dispatcher, receiver and loopback tests pass unchanged
except the two cases this row intentionally changes (a string argument and a bundle).

**Acceptance Scenarios**:

1. **Given** OSC-001's test packets, **When** they are decoded, **Then** the results equal OSC-001's.
2. **Given** a caller of the message-only decode entry point, **When** it receives a bundle,
   **Then** it still gets `bundleUnsupported`.

### Edge Cases

- A string argument that is not valid UTF-8, or whose padding holds non-zero bytes.
- A blob of size 0 (valid: four bytes of size and no data).
- A blob whose size is valid but whose padding runs past the end.
- An empty bundle (header and time tag, no elements): valid, applies nothing.
- A bundle element whose size is 0, not a multiple of 4, or larger than what is left.
- A bundle element that is neither a message (`/`) nor a bundle (`#bundle`).
- A bundle shorter than its header and time tag.
- Type tags for arrays (`[`, `]`), time tags (`t`), characters (`c`), colors (`r`), MIDI (`m`) and
  symbols (`S`): rejected as unsupported.
- The 17th argument, counted across every type including no-payload tags.

## Requirements *(mandatory)*

### Functional Requirements

- **OSC-002-R1**: The decoder MUST keep every OSC-001 limit and rule: datagram at most 1,472 bytes
  (checked first), non-empty, length a multiple of 4, address rules, type tag string required, at
  most 16 arguments per message, zero padding, no trailing bytes.
- **OSC-002-R2**: The decoder MUST accept string arguments: null-terminated, zero-padded to 4
  bytes, valid UTF-8; otherwise rejected with a typed reason.
- **OSC-002-R3**: The decoder MUST accept blob arguments whose declared size is checked to be
  non-negative and to fit, with its padding, in the bytes left BEFORE any storage is reserved for
  the blob; otherwise rejected with a typed reason.
- **OSC-002-R4**: The decoder MUST accept the no-payload tags true, false, nil and impulse and the
  64-bit integer and double tags; every other tag is rejected as unsupported.
- **OSC-002-R5**: The decoder MUST accept bundles: the `#bundle` marker, a 64-bit time tag and zero
  or more size-prefixed elements, each a message or a bundle, with every element size checked
  against the bytes left before the element is read.
- **OSC-002-R6**: Bundle nesting MUST be at most 4 levels (the top-level bundle is level 1), and one
  datagram MUST hold at most 64 elements at all levels; each limit has its own reject reason
  (`bundleTooDeep`, `tooManyElements`).
- **OSC-002-R7**: Decoding MUST never trap, never recurse deeper than the nesting limit, and never
  allocate storage sized from a packet-declared length that was not first checked against the
  bytes left; the decoded payload (addresses, strings, blobs, numbers) MUST never exceed the
  datagram's size.
- **OSC-002-R8**: Every rejection MUST carry a typed reason with a stable key; OSC-001's keys MUST
  keep their meaning.
- **OSC-002-R9**: The encoder MUST encode every packet the decoder accepts back to the identical
  bytes (canonical round trip).
- **OSC-002-R10**: The receiver MUST decode a bundle completely before applying anything, then apply
  its messages in packet order under OSC-001's rules, immediately and regardless of the time tag
  (scheduling is OSC-006); a malformed element rejects the whole datagram. `64-bit integer` and
  `double` arguments count as numbers; string, blob, true, false, nil and impulse do not.
- **OSC-002-R11**: The message-only decode entry point MUST keep OSC-001's behavior for bundles
  (`bundleUnsupported`).
- **OSC-002-R12**: The parser MUST stay pure and platform-independent (testable on Linux) and MUST
  NOT use the network framework, which stays confined to the OSC transport folder.

### Key Entities

- **OSC packet**: either a message or a bundle.
- **OSC message**: address and arguments (OSC-001), now with string, blob, boolean, nil, impulse,
  64-bit integer and double arguments.
- **OSC bundle**: a time tag and an ordered list of elements (messages or bundles).
- **Time tag**: 32-bit seconds since 1900 and 32-bit fraction; the value 1 means "immediately".
- **Decode error**: a typed reason with a stable key, counted by the receiver.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **OSC-002-S1**: 100% of the malformed-packet table (truncation at every 4-byte boundary of a
  representative packet, misaligned and unterminated strings, invalid UTF-8, negative and oversized
  blob sizes, bad bundle element sizes, nesting past the limit, too many elements, unknown tags,
  non-ASCII address) is rejected with its exact expected reason.
- **OSC-002-S2**: A fixed-seed fuzz of at least 20,000 packets (mutated valid packets and random
  bytes) finishes in under 1 second on the host with no crash; every accepted packet re-encodes to
  the identical bytes and its decoded payload is never larger than the datagram.
- **OSC-002-S3**: Valid fixtures for every supported type and for nested bundles decode to exactly
  the expected values.
- **OSC-002-S4**: A bundle holding the test message sent over loopback changes the test value, and
  OSC-001's loopback integration test still passes.
- **OSC-002-S5**: All OSC-001 decoder, dispatcher and receiver tests pass, changed only where this
  row intentionally accepts what OSC-001 rejected.

## Assumptions

- OSC 1.0 wire format, with the widely used OSC 1.1 additions (`T`, `F`, `N`, `I`) and the common
  `h`/`d` tags. Arrays, time-tag arguments, characters, colors, MIDI and symbols are left for a
  later row if a controller needs them.
- Scheduling bundles by their time tag and a late-message policy belong to OSC-006; this row
  applies bundle elements immediately in order.
- Routes to real parameters are OSC-003; the dispatcher still applies only `/projectm/test`.
- No app UI changes: the decoder, encoder and dispatcher live in the PerformanceControl package.
