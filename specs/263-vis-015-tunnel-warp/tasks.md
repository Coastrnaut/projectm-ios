# Tasks: VIS-015 Tunnel Warp

**Input**: `specs/263-vis-015-tunnel-warp/` (spec, plan, research, data-model, contracts/tunnel.md)

## Phase 1: Foundational - shared tunnel module (VIS-015-R3 to R6)

- [ ] VIS-015-T01 `TunnelPace`, `TunnelTempo` (valid when bpm finite, > 0 and confidence ≥ 0.5), `TunnelMapping` (CPU mirror: depth v = 0.5 / max(r, 1e-3) + phase, ring 0.55 + 0.45 cos 2πv, two-octave seamless texture, fog smoothstep(0.02, 0.5, r)), `TunnelShader.function` (MSL) and `TunnelDrive` (target min(pace × bpm/60, 3) else min(1.5 × pace, 3), × 0.5 Reduce Motion; τ 0.5 s; phase += speed · dt mod 4096; brightness 0.5 + 0.3 × low ≤ 0.8) in `Packages/VisualGenerators/Sources/VisualGenerators/TunnelWarp.swift`.
- [ ] VIS-015-T02 `NoiseFieldConfiguration.tunnelPace` (0 = off; 0.5/1/2; a tunnel forces `wedges` 0) and `tunnel(pace:reduceMotion:palette:)` in `NoiseFieldConfiguration.swift`.

## Phase 2: User Stories 1 + 2 - tempo mapping and smooth fallback (VIS-015-R4, R5; S1, S2)

- [ ] VIS-015-T03 [US1] [US2] `TunnelDriveTests` in `Packages/VisualGenerators/Tests/VisualGeneratorsTests/TunnelDriveTests.swift` with an injected 60 Hz clock: 120 BPM settles at exactly 2 × 60 BPM; at a tempo change every frame advances the phase by speed × dt and the speed changes by at most the one-pole bound; BPM 0, nil, NaN, −5 and confidence 0.3 ease to the base speed with no NaN; the phase never runs backwards and wraps invisibly; first frame takes the target; Linux shape.

## Phase 3: User Story 3 - safety (VIS-015-R6 to R8; S3, S4)

- [ ] VIS-015-T04 [US3] `NoiseFieldFlashAreas` samples the tunnel through `TunnelMapping`; `TunnelFlashTests` (`TunnelFlashTests.swift`): speed ≤ 3 rings/s for 0…1000 BPM and every pace, half with Reduce Motion; brightness ≤ 0.8; bursts alternating with silence stay within the envelope in all 17 areas with Reduce flashing on and off; texture continuous across the angle cut and periodic in depth.

## Phase 4: User Story 1 - the picture on Metal (VIS-015-R1 to R3, R10, R13; S5)

- [ ] VIS-015-T05 [US1] `NoiseFieldGenerator`: `tempo`, `tunnelDrive`, third entry point `vis_tunnel_fragment` with its own lazily built pipeline, phase and brightness into the existing uniform slots (layout unchanged).
- [ ] VIS-015-T06 [US1] `TunnelRenderTests` (GPU) in `TunnelRenderTests.swift`: GPU agrees with the CPU mirror; two renders identical; centre dark and no NaN; the tunnel moves faster at 120 than at 60 BPM on the GPU; switching modes in place gives a fresh generator's frames; Noise Field and Kaleidoscope render tests unchanged.
- [ ] VIS-015-T07 [US1] `TunnelGoldenTests` + goldens in `Packages/RenderGoldens` (macOS host, iOS Simulator); README entry.

## Phase 5: User Story 4 - the app (VIS-015-R9, R11, R12; S6)

- [ ] VIS-015-T08 [US4] Visual choice `tunnel`, key `settings.tunnel.pace` (`half`/`beat`/`double`, else `beat`), `TunnelOptions` Pace picker, host style `.tunnel(pace:)` with in-place update and the `tunnelTempo` closure (connected in `AppCoordinator+LFOs.swift`), accessibility value, scene capture as no layer; key in `ALLOWED_KEYS`, FILE-005 policy, `allKeys` (UI-test reset).
- [ ] VIS-015-T09 [P] [US4] `TunnelAppTests` (setting persists and falls back; key in every list; host names itself, changes pace in place, reads the tempo closure per frame, switches with Noise Field/Kaleidoscope in place; scene capture no layer); `SettingsTests`, `CameraVisualTests`, `LibraryBackupAppTests` updated and passing.
- [ ] VIS-015-T10 [P] [US4] `TunnelUITests`: choose Tunnel, Pace offered at "1 ring per beat", Bars not, choose 2, value "2 rings per beat…", source started once (< 30 s).

## Phase 6: Polish

- [ ] VIS-015-T11 Touched package suites, Linux shape, RenderGoldens, repo checks, privacy manifest and network symbol scans, type-check budget, PosterBoard counts.
- [ ] VIS-015-T12 {device} On D1 with music, Tunnel holds the display's frame rate on the PERF-001/007 overlay, and a tapped tempo speeds it up smoothly; Reset eases it back.

## Dependencies

T01 → T02 → T03, T04, T05; T05 → T06, T07, T08 → T09, T10; all → T11. T12 needs a device.

## Parallel examples

T03 and T04 (different test files) after T02; T09 and T10 after T08.

## Implementation strategy

MVP = T01-T03 (the acceptance: tempo mapping and smooth fallback, proven by pure drive tests); then the picture
(T05-T07), then the app (T08-T10).
