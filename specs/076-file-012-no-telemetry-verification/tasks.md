# Tasks: FILE-012 No-Telemetry Verification

**Input**: `specs/076-file-012-no-telemetry-verification/` (spec, plan)

Budgets (owner rule 7): each script test about 1-2 s (≤ 10 s), each UI test < 30 s. Simulator results
are never device evidence. No app behaviour changes (FILE-012-R11).

## Phase 1: US1 — the binaries cannot make network requests on their own (P1)

**Independent test**: scan the three builds; scan a fixture binary that calls `socket`/`connect`.

- [X] FILE-012-T01 [US1] `scripts/check_network_symbols.py`: image discovery (Mach-O and fat magic), per-architecture `otool -L` and `nm -m -u`/`nm -U`, demangling, rules and allowlists (plan D3, D4), `--release`, `--json` (FILE-012-R1, R2, R3) — Verified 2026-11-13: `check_network_symbols.py` on the Debug simulator (19 images), Release simulator (4), Release device (4) and Debug device (6) builds: OK, every Network import classified (Debug simulator: 59 listener-side + 4 DEBUG loopback-sender imports in the PerformanceControl framework; Release: listener-side only in `projectM-iOS`), StoreKit reported as allowed
- [X] FILE-012-T02 [US1] Tests in `scripts/test_scripts.py`: recorded `otool`/`nm` output for each forbidden framework and symbol class, Network symbols outside the OSC image, a Release outbound API, a Debug loopback sender, StoreKit allowed; macOS-only positive control compiling C that calls `socket`/`connect`/`getaddrinfo` (skipped elsewhere) (FILE-012-R4, S2) — Verified 2026-11-13: `python3 scripts/test_scripts.py NetworkSymbolScanTests` 9 tests pass including the macOS clang positive control (socket, connect, getaddrinfo found; a clean binary passes); full script suite 134 tests, 7.5 s
- [X] FILE-012-T03 [US1] Run the scan on the Debug simulator, Release simulator and Release device builds; record findings (FILE-012-S1) — Verified 2026-11-13: the four scans above (JSON in the gitignored `.autonomous/netscan-*.json`); ANGLE `libEGL`/`libGLESv2` and `projectM-4` have no findings
- [ ] FILE-012-T04 [US1] CI step after the projectM-iOS generic-iOS build in `.github/workflows/ios-ci.yml` (FILE-012-R5) — step added 2026-11-13; its command run locally on the same product path (`Debug-iphoneos`, 6 images, OK); the CI run itself is pending until the branch is pushed

## Phase 2: US2, US3 — runtime observation (P1)

**Independent test**: the observer's own tests; then the two observed runs.

- [X] FILE-012-T05 [US2] `scripts/observe_app_network.py`: process discovery for one simulator, `lsof` sampler, simulator log stream, probe, classification for `none` and `osc:<port>`, JSON report, exit codes (FILE-012-R6, R7) — Verified 2026-11-13: dry runs on the FILE12 iPhone 17 (iOS 27.2) simulator wrapping `simctl launch`: OSC on 47129 with `--probe` OK (listener + probe peer in lsof, 42 relevant log events all listener/server-side); OSC off OK (0 sockets, 13 bookkeeping events); negative control (OSC on, `--expect none`) fails with 9 problems
- [X] FILE-012-T06 [US2] Tests in `scripts/test_scripts.py` for the observer's pure functions: lsof field parsing, process filtering by simulator, socket and log classification in both modes, blind-observer failures (FILE-012-R6) — Verified 2026-11-13: `python3 scripts/test_scripts.py AppNetworkObserverTests` 8 tests pass
- [X] FILE-012-T07 [US2] `Apps/projectM-iOS/UITests/NoTelemetryUITests.swift`: four normal-use tests (notice/chooser/playback; seeded Photo/Video/Text and spectra; Save Frame and a short recording; show cues and Clear Caches) with OSC off and the store stubbed (FILE-012-R8) — Verified 2026-11-13: five tests (the visuals test was split in two after it took 40.8 s) pass on the FILE12 iPhone 17 (iOS 27.2) simulator: notice/chooser/playback 6.4 s, seeded Photo/Video/Text 16.3 s, spectra and projectM 19.9 s, Save Frame and recording 12.4 s, show cues and Clear Caches 15.1 s
- [X] FILE-012-T08 [US3] Same file: `testUserEnabledOSCListensOnly` (OSC on in Settings on port 47131, hold for the probe, off) (FILE-012-R8) — Verified 2026-11-13: `testUserEnabledOSCListensOnly` passes (16.9 s)
- [X] FILE-012-T09 [US2] [US3] Observed runs on an own iOS 27.2 simulator: the four tests under `--expect none`, the OSC test under `--expect osc:47131 --probe`; PosterBoard report count before and after (FILE-012-S3, S4, S5) — Verified 2026-11-13: `observe_app_network.py --expect none` around the five tests: OK, 5 app processes, 192 samples over 85.5 s, 0 sockets, 65 log events of which 0 relevant; `--expect osc:47131 --probe` around the OSC test: OK, 1 process, 45 samples over 36.9 s, the listener `UDP *:47131` and the probe's peer `127.0.0.1:47131->127.0.0.1:61566` only, 60 relevant log events (18 listener, connection C1 server-side); PosterBoard reports 32 before and after

## Phase 3: US4 — the record (P2)

- [X] FILE-012-T10 [US4] `docs/test-reports/no-telemetry.md` (layers, what each proves and does not, commands, results, dates) and a FILE-012 paragraph in `docs/release/app-privacy.md` (FILE-012-R9) — Verified 2026-11-13: report written with the commands and results above; app-privacy.md FILE-012 paragraph cites it; `validate_docs.py` OK
- [ ] FILE-012-T11 {device} D1: App Privacy Report (or the owner's Mac proxy) during the quickstart session with OSC off, then with OSC on; expected: no app network activity with OSC off, only local-network listening with it on (FILE-012-R10)

## Phase 4: Polish

- [X] FILE-012-T12 Gates: `check_compliance.py`, `validate_docs.py`, `test_scripts.py`, `check_privacy_manifest.py` on the Debug app, the existing OSC UI tests still pass (FILE-012-R11) — Verified 2026-11-13: `check_compliance.py` OK, `validate_docs.py` OK, `test_scripts.py` 134 tests OK (7.5 s), `check_privacy_manifest.py` OK on the Debug simulator app, OSCReceiverUITests (17.6 s) and OSCNetworkAccessUITests (16.5 s) pass; no app source changed (only a UI test file added)

## Dependencies

T01 → T02, T03, T04. T05 → T06, T09. T07, T08 → T09. T03, T09 → T10. Everything → T12. T11 needs D1
and the owner.

## Analysis (speckit-analyze, 2026-11-13)

Coverage: every requirement maps to a task (R1-R3 T01; R4 T02; R5 T04; R6 T05-T06; R7 T05, T09; R8
T07-T08; R9 T10; R10 T11; R11 T12) and every success criterion to a verifying task (S1 T03; S2 T02;
S3-S5 T09). One fix applied: the plan's observer failure rules now name both halves of FILE-012-R7
(the probe's peer socket in `lsof` and a server-side connection event in the log). No constitution
conflicts; no ambiguous terms left.
