# Contract: OSC parser (OSC-002)

Extends `specs/032-osc-001-osc-receiver/contracts/osc-receiver.md` C1 and C3. Module
`PerformanceControl`, folder `Sources/PerformanceControl/OSC/`; imports nothing.

## P1 Decoding

```swift
public enum OSCDecoder {
    /// OSC-001 entry point, unchanged contract: one message; a bundle → .bundleUnsupported.
    public static func decode(_ bytes: [UInt8]) -> Result<OSCMessage, OSCDecodeError>
    /// A message or a bundle (OSC-002).
    public static func decodePacket(_ bytes: [UInt8]) -> Result<OSCPacket, OSCDecodeError>
}
```

Order of checks for `decodePacket`: size > 1,472 → `oversized`; empty → `empty`; starts with
`#bundle\0` → bundle path; else message path. Both: length not a multiple of 4 → `notAligned`.

Message path (each element of a bundle uses the same path on its exact slice): OSC-001's address
and type-tag rules, then per tag:

| Tag | Check | Error |
|---|---|---|
| `f` `i` | 4 bytes left | `truncatedArgument` |
| `h` `d` | 8 bytes left | `truncatedArgument` |
| `s` | NUL inside the data, padding fits and is zero, UTF-8 valid | `unterminatedString`, `badPadding`, `invalidString` |
| `b` | 4 bytes for size; size ≥ 0 and size + pad ≤ bytes left (before copying); pad zero | `truncatedArgument`, `invalidBlobSize`, `badPadding` |
| `T` `F` `N` `I` | none | — |
| other | — | `unsupportedTypeTag(tag)` |

Then no bytes may be left (`trailingBytes`).

Bundle path at depth d (top level 1): d > 4 → `bundleTooDeep`; fewer than 16 bytes →
`truncatedBundle`; then while bytes remain: fewer than 4 bytes for the size or size ≤ 0, not a
multiple of 4 or larger than what is left → `invalidElementSize`; the 65th element in the datagram →
`tooManyElements`; the element is a bundle if it starts with `#bundle\0`, else a message.

Guarantees: never traps; recursion depth ≤ 4; every stored byte (address, strings, blobs) is copied
from the datagram, so decoded payload ≤ datagram size; no capacity is reserved from a packet value.

## P2 Encoding

```swift
public enum OSCEncoder {
    public static func encode(_ message: OSCMessage) -> [UInt8]   // OSC-001, now every type
    public static func encode(_ packet: OSCPacket) -> [UInt8]
}
```

For every accepted input `x`, `encode(decodePacket(x)) == x` (canonical form).

## P3 Dispatch

`OSCDispatcher.handle(_:)` uses `decodePacket`. A message gives OSC-001's outcomes. A bundle gives
`.bundle([OSCDispatchOutcome])`, one per message, depth-first, all applied before `handle` returns;
the time tag is ignored (OSC-006). Counters: see data-model.md.
