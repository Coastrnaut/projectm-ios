# Test Devices (FR-032, FR-034)

Fill this in **before any device testing** (task T017). Record the exact values; do not guess.
The reference device is the newest capture-capable iPhone available to the project (spec Delivery
Gating) and is used for Gate 2, SC-005–SC-009, SC-013–SC-015, and ADR-0003.

## Inventory (recorded 2026-11-08 from the project owner)

| ID | Device (as reported) | Part number | OS version | OS build | Model identifier | Owner |
|----|----------------------|-------------|------------|----------|------------------|-------|
| D1 | iPhone 15 (reported as "iPhone 15m") | MTLV3LL/A | iOS 27.0.1 | *TBD* | *TBD* | project owner |
| D2 | iPad Pro 13-inch (M5) | MDYJ4LL/A | iPadOS 26.5 → **to be updated to iPadOS 27** (decided 2026-11-08) | *TBD (record after update)* | *TBD* | project owner |
| D3 | iPad (A16) | MD4A4LL/A | iPadOS 26.5 | *TBD* | *TBD* | project owner |

Still to record from each device before its first test run (do not infer them from the part number):
- **OS build**: Settings › General › About › iOS/iPadOS Version (tap the version to show the build).
- **Model identifier**: Xcode › Window › Devices and Simulators (e.g. `iPhone15,4`). Also confirm
  D1's exact model name there (iPhone 15 / 15 Plus / 15 Pro / 15 Pro Max).

## Role assignment (FR-032)

| Role (FR-032) | Device | Status |
|---------------|--------|--------|
| Oldest obtainable iOS 26-capable iPhone, on iOS 26 (fallback modes) | — | **Gap**: no iPhone on iOS 26 is available. D3 (iPad A16 on iPadOS 26.5) covers the iOS 26 fallback-only path in the meantime, but it is an iPad, not the iPhone FR-032 requires |
| iPhone on the earliest OS with System/App Capture | D1 (iOS 27.0.1) | Assigned, assuming capture first appears in iOS 27 (RI-004, task T035). If capture first appears in a later 27.x, D1 must be on that version |
| Current-generation iPhone | — | **Gap**: iPhone 15 is not the current generation |
| iPad (oldest obtainable iPadOS 26-capable preferred) | D3 (iPad A16) | Assigned (fallback modes on iPadOS 26.5) |
| **Reference device** (newest capture-capable iPhone) | D1 (iPhone 15) | Assigned: it is the only capture-capable iPhone available |
| Capture-capable iPad (SC-001) | D2 (iPad Pro M5) | Assigned 2026-11-08; pending its update to iPadOS 27. Use the same 27.x version as D1 where possible |

D2 is the capture-capable iPad. D3 must **stay on iPadOS 26.5** (do not update it): it is the only
device covering the iOS 26 fallback-only path.

## Coverage against SC-001 and FR-032

| Requirement | Needed | Available now | Gap |
|-------------|--------|---------------|-----|
| SC-001: capture sources on ≥ 2 capture-capable iPhones | 2 | 1 (D1) | 1 more iPhone on iOS 27 |
| SC-001: capture sources on ≥ 1 iPad | 1 capture-capable iPad | D2, once on iPadOS 27 | closes when D2 is updated |
| SC-001: fallback sources on every FR-032 device | all roles | D1, D2, D3 | — |
| FR-032: iPhone on iOS 26 | 1 | 0 | an iPhone kept on iOS 26, or an owner-approved substitution of D3 |
| FR-032: current-generation iPhone | 1 | 0 | a current-generation iPhone |

Until the gaps are closed, Stage 1 runs can proceed on D1–D3, but SC-001 and FR-032 cannot be marked
met. The project owner either obtains the missing devices or records an approved waiver or spec
change in the compatibility report's Stage Decision (FR-033).

Status: **inventory recorded; D2 update to iPadOS 27 pending; OS builds and model identifiers pending; 3 FR-032/SC-001 gaps open (second iOS 27 iPhone, iOS 26 iPhone, current-generation iPhone).** No
device results exist.
