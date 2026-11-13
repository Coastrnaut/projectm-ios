# Tasks: FILE-012 No-Telemetry Verification

**Input**: `specs/076-file-012-no-telemetry-verification/` (spec, plan)

Budgets (owner rule 7): each script test about 1-2 s (≤ 10 s), each UI test < 30 s. Simulator results
are never device evidence. No app behaviour changes (FILE-012-R11).

## Phase 1: US1 — the binaries cannot make network requests on their own (P1)

**Independent test**: scan the three builds; scan a fixture binary that calls `socket`/`connect`.

- [ ] FILE-012-T01 [US1] `scripts/check_network_symbols.py`: image discovery (Mach-O and fat magic), per-architecture `otool -L` and `nm -m -u`/`nm -U`, demangling, rules and allowlists (plan D3, D4), `--release`, `--json` (FILE-012-R1, R2, R3)
- [ ] FILE-012-T02 [US1] Tests in `scripts/test_scripts.py`: recorded `otool`/`nm` output for each forbidden framework and symbol class, Network symbols outside the OSC image, a Release outbound API, a Debug loopback sender, StoreKit allowed; macOS-only positive control compiling C that calls `socket`/`connect`/`getaddrinfo` (skipped elsewhere) (FILE-012-R4, S2)
- [ ] FILE-012-T03 [US1] Run the scan on the Debug simulator, Release simulator and Release device builds; record findings (FILE-012-S1)
- [ ] FILE-012-T04 [US1] CI step after the projectM-iOS generic-iOS build in `.github/workflows/ios-ci.yml` (FILE-012-R5)

## Phase 2: US2, US3 — runtime observation (P1)

**Independent test**: the observer's own tests; then the two observed runs.

- [ ] FILE-012-T05 [US2] `scripts/observe_app_network.py`: process discovery for one simulator, `lsof` sampler, simulator log stream, probe, classification for `none` and `osc:<port>`, JSON report, exit codes (FILE-012-R6, R7)
- [ ] FILE-012-T06 [US2] Tests in `scripts/test_scripts.py` for the observer's pure functions: lsof field parsing, process filtering by simulator, socket and log classification in both modes, blind-observer failures (FILE-012-R6)
- [ ] FILE-012-T07 [US2] `Apps/projectM-iOS/UITests/NoTelemetryUITests.swift`: four normal-use tests (notice/chooser/playback; seeded Photo/Video/Text and spectra; Save Frame and a short recording; show cues and Clear Caches) with OSC off and the store stubbed (FILE-012-R8)
- [ ] FILE-012-T08 [US3] Same file: `testUserEnabledOSCListensOnly` (OSC on in Settings on port 47131, hold for the probe, off) (FILE-012-R8)
- [ ] FILE-012-T09 [US2] [US3] Observed runs on an own iOS 27.2 simulator: the four tests under `--expect none`, the OSC test under `--expect osc:47131 --probe`; PosterBoard report count before and after (FILE-012-S3, S4, S5)

## Phase 3: US4 — the record (P2)

- [ ] FILE-012-T10 [US4] `docs/test-reports/no-telemetry.md` (layers, what each proves and does not, commands, results, dates) and a FILE-012 paragraph in `docs/release/app-privacy.md` (FILE-012-R9)
- [ ] FILE-012-T11 {device} D1: App Privacy Report (or the owner's Mac proxy) during the quickstart session with OSC off, then with OSC on; expected: no app network activity with OSC off, only local-network listening with it on (FILE-012-R10)

## Phase 4: Polish

- [ ] FILE-012-T12 Gates: `check_compliance.py`, `validate_docs.py`, `test_scripts.py`, `check_privacy_manifest.py` on the Debug app, the existing OSC UI tests still pass (FILE-012-R11)

## Dependencies

T01 → T02, T03, T04. T05 → T06, T09. T07, T08 → T09. T03, T09 → T10. Everything → T12. T11 needs D1
and the owner.

## Analysis (speckit-analyze, 2026-11-13)

Coverage: every requirement maps to a task (R1-R3 T01; R4 T02; R5 T04; R6 T05-T06; R7 T05, T09; R8
T07-T08; R9 T10; R10 T11; R11 T12) and every success criterion to a verifying task (S1 T03; S2 T02;
S3-S5 T09). One fix applied: the plan's observer failure rules now name both halves of FILE-012-R7
(the probe's peer socket in `lsof` and a server-side connection event in the log). No constitution
conflicts; no ambiguous terms left.
