# Implementation Plan: OSC-003 OSC Parameter Routes

**Branch**: `feature/osc-003` | **Date**: 2026-11-14 | **Spec**: `specs/191-osc-003-parameter-routes/spec.md`

## Summary
Replace OSC-001's single fixed route with an allowlisted route table to MOD-001 parameter IDs, feed routed
values into MIDI-003's live-value path, and list the routes in Settings with per-route toggles and small
validated user aliases. No change to the transport or network scope.

## Technical Context
Swift 6.4, SwiftUI, Xcode 27.2. Pure-Swift logic in `Packages/PerformanceControl` (Linux-tested);
app glue in `Apps/projectM-iOS`. Tests: XCTest package tests with a fake clock, app unit tests on the iOS
27.2 simulator, one XCUITest under 30 s.

## Constitution Check
- Public APIs only; no new networking symbol (`check_network_symbols`); OSC transport unchanged (FR-068, ADR-0008).
- Local-first and private: stored keys hold addresses and parameter IDs only; values are memory only.
- Sensory safety: routed values pass the ACC-012 clamp (same order as MIDI).

## Project Structure
- `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCParameterRoutes.swift` (new)
- `Packages/PerformanceControl/Sources/PerformanceControl/OSC/ExternalLiveValues.swift` (new)
- `OSCDispatcher.swift`, `OSCReceiverCatalog.swift`, `OSCReceiver.swift` (extended)
- `Apps/projectM-iOS/Coordinators/OSCRoutesCoordinator.swift`, `Views/OSCRoutesView.swift` (new)
- `OSCReceiverCoordinator.swift`, `AppCoordinator.swift`, `SettingsView.swift` (small edits)
- Keys: `LibrarySettings.swift`, `scripts/run_device_tests.py`, UI-test reset.
