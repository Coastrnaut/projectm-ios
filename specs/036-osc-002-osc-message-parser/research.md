# Research: OSC-002 OSC Message Parser

All decisions are Claude's under the owner's best-judgement delegation (owner rule 4).

## OSC-002-D1 Extend, do not replace

- **Decision**: add cases to `OSCArgument` and a new `decodePacket(_:)` beside `decode(_:)` in
  `OSCDecoder`; both share one message decoder.
- **Rationale**: OSC-001 designed the enums for this (its Clarifications); one decoder means one
  set of bounds checks to fuzz.
- **Alternatives**: a second parser type (two code paths to keep safe); changing `decode(_:)` to
  return packets (breaks OSC-001 callers and its `bundleUnsupported` contract).

## OSC-002-D2 Lengths from the packet

- **Decision**: the blob size is read as a signed 32-bit value; it must be ≥ 0 and
  `size + padding ≤ bytes left` before the blob is copied (`invalidBlobSize`). A bundle element
  size must be > 0, a multiple of 4 and ≤ bytes left in the enclosing bundle (`invalidElementSize`)
  before the element is decoded, and the element is decoded from exactly that slice.
- **Rationale**: the row's acceptance criterion; the only copies are of bytes already in the
  datagram, so the decoded payload can never exceed the datagram size.
- **Alternatives**: trusting the size and letting a slice trap (crash); `reserveCapacity(size)`
  (unbounded allocation from attacker input).

## OSC-002-D3 Nesting and element limits

- **Decision**: depth ≤ 4, 64 elements per datagram (all levels). Recursion happens only when an
  element starts with `#bundle`, carries the depth, and is refused before descending past 4.
- **Rationale**: a 1,472-byte datagram could otherwise nest about 70 bundles or hold about 120
  minimal messages; real controllers send one level and a handful of messages. 64 × 16 arguments is
  still small.
- **Alternatives**: an explicit stack (no benefit at depth 4); no element limit (a datagram of
  120 messages would apply 120 store writes per packet, a load OSC-009 must otherwise absorb).

## OSC-002-D4 Types

- **Decision**: accept `s`, `b`, `h`, `d`, `T`, `F`, `N`, `I`; reject arrays and `t`, `c`, `r`,
  `m`, `S` as `unsupportedTypeTag`. `h`/`d` are numeric for the dispatcher.
- **Rationale**: these are OSC 1.0 required types plus the 1.1 standard tags; arrays would add a
  second nesting dimension, and the rest are rare in controllers. Each can be added later without
  changing callers.

## OSC-002-D5 Strings

- **Decision**: valid UTF-8 without NUL; invalid UTF-8 is `invalidString`. Check: decode with
  `String(decoding:as:)` and compare the re-encoded bytes with the source (portable, bounded).
- **Rationale**: replacement characters would break the canonical round trip and hide garbage.

## OSC-002-D6 Bundles in the receiver

- **Decision**: decode completely, then apply every message in depth-first packet order at once;
  ignore the time tag. `OSCDispatchOutcome.bundle([OSCDispatchOutcome])` reports per-message
  outcomes; a new `bundles` counter; `applied`/`ignored` count per message.
- **Rationale**: atomic rejection of malformed bundles; OSC-006 owns scheduling and the late policy
  and replaces the immediate path. Applying immediately matches what most receivers do for the
  "immediately" time tag (1), which controllers send almost always.
- **Alternatives**: drop bundles with a future time tag until OSC-006 (would silently ignore
  controllers that stamp "now" as an absolute time).

## OSC-002-D7 Fuzz and allocation bound

- **Decision**: one fixed-seed SplitMix64 fuzz of 24,000 packets: random bytes, byte mutations of
  valid seed packets (messages with every type, nested bundles), truncations, and size-field
  mutations (write 0, −1, 0x7FFFFFFF, off-by-4 into blob and element size words). For each
  accepted packet: re-encode equals input, decoded payload bytes ≤ datagram size, depth ≤ 4,
  elements ≤ 64. Each rejected packet has a typed error (the typed `throws` makes that structural).
- **Rationale**: owner rule 7 (≤ 1 s); counters, not Instruments, show the allocation bound.
