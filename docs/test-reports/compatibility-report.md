# Source Compatibility Report (FR-030–FR-034)

> **No source has been tested yet. No source is claimed to work.** A row may be rated "Works" only
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
| | | | | Spotify | | System/App Capture | | | | | | | | *untested* | | | |
| | | | | Apple Music | | System/App Capture | | | | | | | | *untested* | | | |
| | | | | YouTube Music | | System/App Capture | | | | | | | | *untested* | | | |
| | | | | Safari video | | System/App Capture | | | | | | | | *untested* | | | |
| | | | | In-App reference audio | n/a | In-App Playback | n/a | | | | | | | *untested* | | | |
| | | | | Microphone (room sound) | n/a | Microphone | n/a | | | | | | | *untested* | | | |

Copy the six rows for each device in devices.md (SC-001: System/App Capture sources on at least two
capture-capable iPhones and one iPad; fallback sources on every device).

## Gate 2 — sustained capture (spec Delivery Gating)

For each source rated "Works", on the reference device, 30-minute foreground capture:

| Source | Unrecovered stream failures (0) | Dropped audio (< 1%) | Median start-to-first-audio (< 2 s) | Capture + classifier CPU (< 15% of one core) | Memory growth min 5 → 30 (≤ 10%) | Pass? |
|--------|---------------------------------|----------------------|-------------------------------------|----------------------------------------------|----------------------------------|-------|

## Stage 1 thresholds (finalized here before Stage 2; task T054)

| Threshold | Initial | Final | Evidence |
|-----------|---------|-------|----------|
| Active: peak / duration | −50 dBFS / 250 ms | | |
| Silent: peak / duration | −60 dBFS / 2 s | | |
| No-audio timeout | 5 s | | |
| Prolonged-silence hint | 60 s | | |
| Start/stop cycle interval | 200 ms | | |
| Works: windows / dropped | 95% / < 1% | | |

## Stage Decision (FR-033)

| Stage | Decision (go / no-go) | Approver | Date | Evidence | Claimable sources |
|-------|-----------------------|----------|------|----------|-------------------|
| Stage 1 → Stage 2 | *pending* | | | | *none yet* |
