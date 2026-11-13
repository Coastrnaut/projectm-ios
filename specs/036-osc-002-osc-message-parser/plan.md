# Implementation Plan: OSC-002 OSC Message Parser

**Branch**: `feature/osc-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/036-osc-002-osc-message-parser/spec.md`

## Summary

Extend OSC-001's bounded decoder in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/`
instead of writing a second one. `OSCArgument` gains `string`, `blob`, `int64`, `double`, `true`,
`false`, `nil` and `impulse`; a new `OSCPacket` (message or bundle), `OSCBundle` and `OSCTimeTag`
model bundles. `OSCDecoder.decodePacket(_:)` decodes either, with every packet-declared length
(blob size, bundle element size) checked against the bytes left before anything is read or
allocated, nesting capped at 4 and elements at 64 per datagram; `OSCDecoder.decode(_:)` stays the
message-only entry point and still returns `bundleUnsupported` for a bundle. `OSCEncoder` encodes
every new type and bundles, so every accepted packet re-encodes byte for byte. `OSCDispatcher`
decodes with `decodePacket` and applies a bundle's messages immediately in packet order
(OSC-006 owns time-tag scheduling). Tests: a table of malformed cases mapped to exact reasons,
valid fixtures, a fixed-seed structure-aware fuzz (≤ 1 s) with round-trip and payload-size bounds,
dispatcher bundle cases and a bundle over the real loopback listener.
Research: [research.md](research.md); entities: [data-model.md](data-model.md); API:
[contracts/osc-parser.md](contracts/osc-parser.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode), Xcode 27.2; CI also Xcode 26.

**Primary Dependencies**: none new. The parser imports nothing (not Foundation, not Network).

**Storage**: none.

**Testing**: XCTest. `swift test --package-path Packages/PerformanceControl` on the macOS host and
in Linux CI; `xcodebuild test -scheme PerformanceControl` once on an iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26.0+, macOS 15+ (host tests), Linux (CI).

**Project Type**: SwiftPM library package (no app change).

**Performance Goals**: one bounded pass per datagram (≤ 1,472 bytes); recursion only per nested
bundle, at most 4 frames; the fixed-seed fuzz of at least 20,000 packets finishes in under 1 s on
the host (OSC-002-S2), measured by the test run time, never asserted on the wall clock.

**Constraints**: no allocation sized from an unchecked packet-declared length; no C stdio globals;
no main-actor mutation in XCTest setUp/tearDown; explicit closure types for Xcode 26; unit tests
about 1 s, package suite < 1 min (owner rule 7).

**Scale/Scope**: about 350 lines of package Swift changed or added, 400 lines of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Pure Swift standard library | Pass |
| II-III Capture | Not touched | Pass (n/a) |
| IV Truthful labeling | No UI change | Pass (n/a) |
| V No universal claims | No controller is named as working | Pass |
| VI Modular boundaries | Parser stays pure and transport-agnostic; Network code stays in `OSCTransport/` (FR-068 as amended, ADR-0008) | Pass |
| VII Real-time safety | Decoding runs on the transport's serial queue, never on audio | Pass |
| VIII ProjectM fidelity | Only `/projectm/test` is routed; nothing reaches projectM | Pass |
| IX Dependencies | None added; OSC 1.0 format plus the common 1.1 tags, implemented from the public spec | Pass |
| X Evidence | Host, Linux and simulator tests; device LAN stays OSC-001's open `{device}` task | Pass |
| Security (imported data is untrusted) | Every length checked before use; bounded depth, elements and payload; typed errors | Pass |

Post-design re-check: unchanged (Pass). No ADR: nothing overrides a default; decisions are in the
spec's Clarifications and research.md.

## Project Structure

### Documentation (this feature)

```text
specs/036-osc-002-osc-message-parser/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/osc-parser.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/PerformanceControl/
├── Sources/PerformanceControl/OSC/
│   ├── OSCMessage.swift        # OSCArgument new cases, OSCLimits (+ bundle limits)
│   ├── OSCPacket.swift         # new: OSCPacket, OSCBundle, OSCTimeTag
│   ├── OSCDecoder.swift        # decodePacket, new reasons; decode(_:) unchanged contract
│   ├── OSCEncoder.swift        # new types, bundles
│   └── OSCDispatcher.swift     # bundle outcome, bundles counter
└── Tests/PerformanceControlTests/
    ├── OSCDecoderTests.swift            # OSC-001 cases (two updated for this row)
    ├── OSCPacketDecoderTests.swift      # new: fixtures, malformed table, fuzz
    ├── OSCDispatcherTests.swift         # + bundle cases
    └── OSCLoopbackIntegrationTests.swift # + a bundle over loopback
docs/test-reports/osc-message-parser.md  # results
```

**Structure Decision**: same files as OSC-001 plus one model file; the parser stays one decoder.

## Complexity Tracking

None.
