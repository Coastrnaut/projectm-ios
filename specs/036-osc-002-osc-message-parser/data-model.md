# Data Model: OSC-002 OSC Message Parser

## OSCLimits (extended)

| Limit | Value | Source |
|---|---|---|
| `maximumDatagramBytes` | 1,472 | OSC-001 |
| `maximumAddressBytes` | 255 | OSC-001 |
| `maximumArguments` | 16 per message, every tag counts | OSC-001 |
| `maximumBundleDepth` | 4 (top-level bundle is 1) | OSC-002-R6 |
| `maximumBundleElements` | 64 per datagram, all levels | OSC-002-R6 |

## OSCArgument (extended)

| Case | Tag | Wire payload | `numericValue` |
|---|---|---|---|
| `float(Float)` | `f` | 4 bytes | value |
| `int(Int32)` | `i` | 4 bytes | value |
| `string(String)` | `s` | UTF-8, NUL, zero pad to 4 | nil |
| `blob([UInt8])` | `b` | Int32 size ≥ 0, bytes, zero pad to 4 | nil |
| `int64(Int64)` | `h` | 8 bytes | value |
| `double(Double)` | `d` | 8 bytes | value |
| `true` / `false` | `T` / `F` | none | nil |
| `nil` | `N` | none | nil |
| `impulse` | `I` | none | nil |

Equality is bit-exact for `float` and `double`.

## OSCTimeTag

`seconds: UInt32` (since 1900-01-01), `fraction: UInt32`; `immediately` = (0, 1). Wire: 8 bytes
big-endian.

## OSCBundle

`timeTag: OSCTimeTag`, `elements: [OSCPacket]` (packet order). Wire: `#bundle\0`, time tag, then
per element an Int32 size followed by that many bytes.

## OSCPacket

`message(OSCMessage)` or `bundle(OSCBundle)`. `messages`: all messages depth-first in packet order.

## OSCDecodeError (extended)

OSC-001 keys unchanged: `oversized`, `empty`, `notAligned`, `unterminatedString`, `badPadding`,
`invalidAddress`, `missingTypeTags`, `tooManyArguments`, `unsupportedTypeTag`,
`truncatedArgument`, `trailingBytes`, `bundleUnsupported` (message-only entry point).

New: `invalidString`, `invalidBlobSize`, `truncatedBundle`, `invalidElementSize`, `bundleTooDeep`,
`tooManyElements`.

## OSCReceiverCounters (extended)

`bundles`: accepted bundle datagrams. `received`/`rejected`/`rejectedByReason` per datagram;
`applied`/`ignored` per message (a bundle of three messages adds three).
