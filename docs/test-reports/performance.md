# Performance Report

All values must come from physical devices listed in [devices.md](devices.md). Status: **no
measurements yet.**

## Phase A real-time check (Constitution VII; task T050)

| Adapter | Device | Run length | Heap allocations on audio thread (0) | Lock acquisitions (0) | Pass? |
|---------|--------|------------|--------------------------------------|-----------------------|-------|
| System/App Capture | | 60 s | | | |
| Microphone | | 60 s | | | |
| In-App Playback | | 60 s | | | |

## Plan Phase B exit (task T063)

| Adapter | Allocations (0) | Locks (0) | Capture + pipeline CPU, 30 min (< 15% of one core) | Pass? |
|---------|-----------------|-----------|----------------------------------------------------|-------|

## ADR-0003 renderer measurements (Gate 3)

| Option | Device | Test presets OK | Starter presets OK (≥ 95%) | fps ≥ 55 for 95% (ref) / ≥ 30 (oldest) | App size Δ (≤ 30 MB) | Flash limiter cost (< 2 ms) | Pass? |
|--------|--------|-----------------|----------------------------|-----------------------------------------|----------------------|-----------------------------|-------|

## Stage 2 success criteria (Gate 4)

| Criterion | Target | D1 iPhone 15 (reference) | D2 iPad Pro M5 | D3 iPad A16 | Pass? |
|-----------|--------|------------------|---------------|-------------|-------|
| SC-005 frame rate | ≥ 55 fps for 95% of 10 min (60 fps cap on 120 Hz) | | | | |
| SC-006 audio→visual delay | median < 150 ms (20 clicks) | | n/a | n/a | |
| SC-007 preset switch | 95% first frame < 1 s; blend ≤ 2 s | | | | |
| SC-008 memory | drift ≤ 10% (min 5→30); peak < 300 MB | | | | |
| SC-009 cycles + lifecycle | 0 crashes | | | | |
| SC-013 thermal | never critical; ≥ 30 fps; no termination | | | | |
| SC-014 battery | ≤ 20% per 60 min | | | | |
| SC-015 cold launch | < 2 s D1 / < 4 s D3 | | | | |

## Stage 2 thresholds (finalized at Gate 4)

| Threshold | Initial | Final | Evidence |
|-----------|---------|-------|----------|
