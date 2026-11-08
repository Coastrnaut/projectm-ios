# Test Devices (FR-032, FR-034)

Fill this in **before any device testing** (task T017). Record the exact values; do not guess.
The reference device is the newest capture-capable iPhone available to the project (spec Delivery
Gating) and is used for Gate 2, SC-005–SC-009, SC-013–SC-015, and ADR-0003.

## Inventory (recorded 2026-11-08 from the project owner)

| ID | Device | Device name | Part number | OS version | OS build | Model identifier | Owner |
|----|--------|-------------|-------------|------------|----------|------------------|-------|
| D1 | iPhone 15 | iPhone77 | MTLV3LL/A | iOS 27.0.1 | 24A446 | iPhone15,4 | project owner |
| D2 | iPad Pro 13-inch (M5) | iPad77 | MDYJ4LL/A | iPadOS 27.2 | 24B119 | iPad17,3 | project owner |
| D3 | iPad (A16) | iPadC | MD4A4LL/A | iPadOS 26.5 | 23F77 | iPad15,7 | project owner |

OS build and model identifier recorded 2026-11-08 with `xcrun devicectl list devices` (Xcode 27.2)
on the project Mac, with all three devices paired and Developer Mode enabled. This confirms D1 is the
base iPhone 15 (`iPhone15,4`). If a device's OS is updated, re-record its row before the next run.

## Project device set (FR-032, spec Clarifications 2026-11-08)

The project tests on exactly these three devices. The project owner will not buy others.

| Device | Role | Modes tested |
|--------|------|--------------|
| D1 iPhone 15, iOS 27.0.1 | **Reference device**; capture-capable iPhone | System/App Capture, Microphone, In-App Playback |
| D2 iPad Pro M5, iPadOS 27.2 | Capture-capable iPad | System/App Capture, Microphone, In-App Playback |
| D3 iPad A16, iPadOS 26.5 | iOS 26 fallback-only path; "oldest" performance tier | Microphone, In-App Playback (System/App Capture must show as unavailable) |

**Keep D3 on iPadOS 26.5.** Do not update it: it is the only device covering the iOS 26 path.

D1 (27.0.1) and D2 (27.2) run different iOS 27 versions. Record the exact version on every report
row. If System/App Capture behaves differently between them, note the OS version as a possible cause.

## Not applicable (owner decision 2026-11-08)

| Original role or requirement | Status | Effect |
|------------------------------|--------|--------|
| Second capture-capable iPhone (old SC-001) | **N/A** | Capture results come from one iPhone model (D1) plus one iPad (D2) |
| iPhone on iOS 26 (old FR-032) | **N/A** | The iOS 26 path is verified on D3 (iPad) only |
| Current-generation iPhone (old FR-032) | **N/A** | Performance is published for D1–D3 only |

These do **not** block any phase, gate, or task. Their only effect is on claims (FR-062):
compatibility and performance statements cover only the device classes and OS versions tested
above, e.g. "tested on iPhone 15 (iOS 27.0.1) and iPad Pro M5 (iPadOS 27.2)".

Status: **device set final and fully recorded (T017, 2026-11-08).** No device results exist.
