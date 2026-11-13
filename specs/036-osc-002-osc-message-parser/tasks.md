# Tasks: OSC-002 OSC Message Parser

**Input**: Design documents from `specs/036-osc-002-osc-message-parser/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/osc-parser.md, quickstart.md

**Tests**: requested by the row (unit fuzz) and the spec (OSC-002-S1 to S5). Budgets (owner rule 7):
a unit test about 1-2 s, at most 10 s; the package suite under 1 minute.

Paths are relative to the repository root; `PC` = `Packages/PerformanceControl`.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] OSC-002-T01 Run `python3 scripts/check_compliance.py` and `swift test --package-path Packages/PerformanceControl` on the unchanged worktree and record the baseline pass count in `docs/test-reports/osc-message-parser.md`

## Phase 2: Foundational (model types, blocks every story)

- [ ] OSC-002-T02 Extend `OSCArgument` in `PC/Sources/PerformanceControl/OSC/OSCMessage.swift` with `string(String)` (`s`), `blob([UInt8])` (`b`), `int64(Int64)` (`h`), `double(Double)` (`d`), `true` (`T`), `false` (`F`), `nil` (`N`), `impulse` (`I`); `numericValue` is the value for `f`, `i`, `h`, `d` and nil otherwise; bit-exact equality and hashing for `float` and `double`; add `OSCLimits.maximumBundleDepth = 4` ("top-level bundle is 1") and `OSCLimits.maximumBundleElements = 64` ("per datagram, all levels")
- [ ] OSC-002-T03 Create `PC/Sources/PerformanceControl/OSC/OSCPacket.swift`: `OSCTimeTag` (`seconds: UInt32`, `fraction: UInt32`, `immediately` = (0, 1)), `OSCBundle` (`timeTag`, `elements: [OSCPacket]`), `OSCPacket` (`message`, `bundle`) with `messages` (depth-first, packet order)
- [ ] OSC-002-T04 Add the reasons `invalidString`, `invalidBlobSize`, `truncatedBundle`, `invalidElementSize`, `bundleTooDeep`, `tooManyElements` to `OSCDecodeError` in `PC/Sources/PerformanceControl/OSC/OSCDecoder.swift`, keeping the twelve OSC-001 keys unchanged

## Phase 3: User Story 1 - Strings, booleans and bundles decode (P1) 🎯 MVP

**Goal**: every well-formed packet with the new types and bundles decodes exactly and re-encodes to the same bytes; the receiver applies a bundle's messages.

**Independent Test**: valid fixtures in `OSCPacketDecoderTests`, dispatcher bundle cases, a bundle over loopback.

- [ ] OSC-002-T05 [US1] Decode the new argument types in the shared message decoder in `PC/Sources/PerformanceControl/OSC/OSCDecoder.swift` per contract P1 (strings valid UTF-8 → else `invalidString`; blob size ≥ 0 and size + padding ≤ bytes left checked before copying → else `invalidBlobSize`; `h`/`d` need 8 bytes → else `truncatedArgument`)
- [ ] OSC-002-T06 [US1] Add `OSCDecoder.decodePacket(_:)` with the bundle path (16-byte header, element sizes, depth ≤ 4, ≤ 64 elements, recursion only per nested bundle) in `PC/Sources/PerformanceControl/OSC/OSCDecoder.swift`; `decode(_:)` keeps returning `bundleUnsupported` for a bundle
- [ ] OSC-002-T07 [US1] Encode every new type and `OSCPacket`/`OSCBundle` in `PC/Sources/PerformanceControl/OSC/OSCEncoder.swift`
- [ ] OSC-002-T08 [P] [US1] Valid fixtures in `PC/Tests/PerformanceControlTests/OSCPacketDecoderTests.swift`: hand-written bytes for every type, an empty bundle, a nested bundle with three messages and time tags; exact decoded values and byte-exact re-encode (OSC-002-S3)
- [ ] OSC-002-T09 [US1] Dispatcher bundles in `PC/Sources/PerformanceControl/OSC/OSCDispatcher.swift`: decode with `decodePacket`, `OSCDispatchOutcome.bundle([OSCDispatchOutcome])` applied in packet order immediately (time tag ignored; OSC-006), `bundles` counter, `applied`/`ignored` per message; `h`/`d` are numeric
- [ ] OSC-002-T10 [US1] Dispatcher tests in `PC/Tests/PerformanceControlTests/OSCDispatcherTests.swift`: a bundle with `/projectm/test` applies it, order (last write wins), counters, a malformed element applies nothing, a double is applied, `T` is wrong arguments
- [ ] OSC-002-T11 [US1] Loopback test in `PC/Tests/PerformanceControlTests/OSCLoopbackIntegrationTests.swift`: a bundle holding `/projectm/test 0.42` sent over loopback changes the test value (OSC-002-S4)

## Phase 4: User Story 2 - Malformed packets are rejected safely (P1)

**Goal**: the row's acceptance criterion.

**Independent Test**: the malformed table and the fuzz in `OSCPacketDecoderTests`.

- [ ] OSC-002-T12 [P] [US2] Malformed table in `PC/Tests/PerformanceControlTests/OSCPacketDecoderTests.swift`, each case mapped to its exact reason: truncation at every 4-byte boundary of a representative bundle, misaligned and unterminated strings, invalid UTF-8, negative/huge/past-end blob sizes, element size 0/unaligned/past the end, a short bundle, nesting depth 5, 65 elements, unknown tags (`c`, `[`), a 17th argument counted across no-payload tags (`tooManyArguments`), a bundle element that starts with neither `/` nor `#bundle` and a non-ASCII address in an element (`invalidAddress`), a blob whose padding runs past the end (`invalidBlobSize`) (OSC-002-S1)
- [ ] OSC-002-T13 [US2] Fixed-seed structure-aware fuzz (≥ 20,000 packets: random bytes, byte mutations, truncations, size-word mutations) in `PC/Tests/PerformanceControlTests/OSCPacketDecoderTests.swift`: no crash, accepted packets re-encode exactly, decoded payload ≤ datagram size, depth ≤ 4, elements ≤ 64, both outcomes seen (OSC-002-S2)

## Phase 5: User Story 3 - OSC-001 behavior unchanged (P2)

**Goal**: regressions.

**Independent Test**: OSC-001's suites.

- [ ] OSC-002-T14 [US3] Update only the two intentionally changed OSC-001 cases in `PC/Tests/PerformanceControlTests/OSCDecoderTests.swift` (`,s` now decodes; use `,c` for `unsupportedTypeTag`; `decode(_:)` still returns `bundleUnsupported`), add the new keys to the distinct-key test, and run all OSC-001 tests (OSC-002-S5)

## Phase 6: Polish

- [ ] OSC-002-T15 Update the header comments (OSC-002-R12: the `OSC/` files import nothing) of the changed OSC files and the package comment in `PC/Package.swift` if needed; run `python3 scripts/check_compliance.py` (no Network import in `OSC/`) and `python3 scripts/validate_docs.py`
- [ ] OSC-002-T16 Run the package once on an iOS 27.2 simulator (`xcodebuild test -scheme PerformanceControl`, own simulator, deleted afterwards, PosterBoard reports counted) and write results, limits, reasons and decisions to `docs/test-reports/osc-message-parser.md`

## Dependencies

- T01 → T02-T04 → US1 (T05-T07 before T08-T11) → US2 (T12-T13 need T05-T07) → US3 (T14) → T15-T16.
- T08 and T12 are in the same new file; [P] only against other files.

## Implementation Strategy

MVP is US1 plus US2 together (the decoder is shared and the row is P0 on safety); US3 is the
regression gate. Commit after each phase.
