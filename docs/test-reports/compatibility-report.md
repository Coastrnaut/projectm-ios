# Source Compatibility Report (FR-030–FR-034)

> **No source is rated, and none will be in Stage 1: T051-T053 are not required and Gates 1 and 2
> are waived (owner ruling 2026-11-09, ADR-0001 ruling 19). No source is claimed to work.** Preliminary System/App Capture runs
> with Spotify on D1 and D2 (2026-11-09) are recorded below but not rated. A row may be rated "Works" only
> with a CaptureLab diagnostics export from a physical device showing non-silent audio (FR-031).
> Screenshots of the picker or UI are not evidence. Simulator results are never evidence.

Devices: see [devices.md](devices.md). Exports: `docs/test-reports/exports/<device>/<source>/`.

## Rating scale (FR-031)

- **Works**: Active audio in at least 95% of one-minute windows across a 10-minute run with
  CaptureLab foregrounded, and dropped audio under 1%.
- **Partial**: Active audio observed, but the "Works" thresholds are missed, or it works only for
  some content or only until a lifecycle event (e.g., lock). The limitation must be written.
- **Does not work**: No audio received, or silent only, throughout the run.

## Source matrix

One row per device × source. Sources (FR-030): Spotify, Apple Music, YouTube Music, Safari video,
In-App reference audio, Microphone.

| Device role | Device model | OS build | Toolchain | Source | Source app version | Capture mode | Picker selection | Audio arrived | Non-silent | Sample rate | Channels | Latency avg / worst (ms) | Interruption / end behavior | Result | Limitation (required if Partial) | Repro steps | Export file(s) |
|-------------|--------------|----------|-----------|--------|--------------------|--------------|------------------|---------------|------------|-------------|----------|--------------------------|-----------------------------|--------|----------------------------------|-------------|----------------|
| D1 | iPhone 15 `iPhone15,4` | iOS 27.0.1 (24A446) | Xcode 27.2 (27B52) | Spotify | not recorded | System/App Capture | not recorded | yes | yes | 48000 | 2 | n/a (buffer cadence 20.0 / 36.8) | none in this run | *not rated: one 20.8 s run; FR-031 needs 10 min (T051)* | | Start Spotify playback, open CaptureLab, System/App Capture, pick in the system picker, stay in CaptureLab | `exports/D1/spotify/CaptureLab-20261109-221348.json` |
| D2 | iPad Pro 13-inch (M5) `iPad17,3` | iPadOS 27.2 (24B119) | Xcode 27.2 (27B52) | Spotify | not recorded | System/App Capture | not recorded | yes | yes | 48000 | 2 | n/a (buffer cadence 18.9 / 1057.4; 68 late buffers, 0 dropped; first audio after 1.5 s) | none in this run | *not rated: one 22.4 s run; FR-031 needs 10 min (T051)* | | Same as D1 | `exports/D2/spotify/CaptureLab-20261109-222214.json` |
| | | | | Spotify | | System/App Capture | | | | | | | | *untested* | | | |
| | | | | Apple Music | | System/App Capture | | | | | | | | *untested* | | | |
| | | | | YouTube Music | | System/App Capture | | | | | | | | *untested* | | | |
| | | | | Safari video | | System/App Capture | | | | | | | | *untested* | | | |
| D3 | iPad (A16) `iPad15,7` | iPadOS 26.5 (23F77) | Xcode 27.2 (27B52), Debug | In-App reference audio | n/a | In-App Playback | n/a | yes | yes | 44100 | 2 | n/a (buffer cadence 99.9 / 116.7) | stopped by the user | *not rated: one 7.2 s run; FR-031 needs 10 min (T051)* | | Launch CaptureLab on D3, In-App Playback, Stop. System/App Capture showed "Requires a newer iOS version" (tester note) | `exports/D3/in-app/CaptureLab-20261109-222812.json` |
| | | | | In-App reference audio | n/a | In-App Playback | n/a | | | | | | | *untested* | | | |
| | | | | Microphone (room sound) | n/a | Microphone | n/a | | | | | | | *untested* | | | |

Copy the six rows for each device in devices.md (SC-001: System/App Capture sources on D1 and D2;
fallback sources on D1, D2, and D3. On D3, iPadOS 26, System/App Capture rows are expected to read
"unavailable — Requires a newer iOS version").

## Gate 2 — sustained capture (spec Delivery Gating)

For each source rated "Works", on the reference device, 30-minute foreground capture:

| Source | Unrecovered stream failures (0) | Dropped audio (< 1%) | Median start-to-first-audio (< 2 s) | Capture + classifier CPU (< 15% of one core) | Memory growth min 5 → 30 (≤ 10%) | Pass? |
|--------|---------------------------------|----------------------|-------------------------------------|----------------------------------------------|----------------------------------|-------|

## Stage 1 thresholds (finalized here before Stage 2; task T054)

| Threshold | Initial | Final | Evidence |
|-----------|---------|-------|----------|
| Active: peak / duration | −50 dBFS / 250 ms | −50 dBFS / 250 ms | T040 scenario 1 on D1, D2 ("Active audio" within 0.26 s on D1) |
| Silent: peak / duration | −60 dBFS / 2 s | −60 dBFS / 1.5 s (owner ruling 2026-11-09) | SC-003 on D1: 23 cycles, all within 2 s |
| No-audio timeout | 5 s | 5 s | Unit tests only: on device, iOS sends silent buffers instead of no data (T040 scenario 3) |
| Prolonged-silence hint | 60 s | 60 s | D1 nothing-playing run: hint shown (about 50-60 s, tester estimate) |
| Start/stop cycle interval | 200 ms | 200 ms | CaptureKit unit tests (50 rapid cycles); no device measurement |
| Works: windows / dropped | 95% / < 1% | 95% / < 1% (unused in Stage 1) | No ratings: Gates 1 and 2 waived (ADR-0001 ruling 19) |

## Stage Decision (FR-033)

| Stage | Decision (go / no-go) | Approver | Date | Evidence | Claimable sources |
|-------|-----------------------|----------|------|----------|-------------------|
| Stage 1 → Stage 2 | **go** | Project owner (Coastrnaut) | 2026-11-09 | Gate 0 met (ADR-0001/0002 accepted); T040 (`t040-us1.md`) and T041 (`t041-lifecycle.md`) on D1, D2, D3 with exports; System/App Capture delivered non-silent Spotify audio on D1 and D2 in short runs; Gates 1 and 2 waived, T049-T053 and T113 not required (ADR-0001 rulings 18, 19); ADR-0005 conditional go (T055) | **None**: no source is rated under FR-031. Product wording: "System/App Capture, where iOS allows it", plus Microphone and In-App Playback |
