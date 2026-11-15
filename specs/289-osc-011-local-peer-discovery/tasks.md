# Tasks: OSC-011 Local Peer Discovery

**Input**: `specs/289-osc-011-local-peer-discovery/` (spec, plan, research, data-model, contracts/osc-discovery.md, quickstart)
**Tests**: requested by the roadmap acceptance ("Discovery disabled by default and no central relay is used").

## Phase 1: Setup

- [X] OSC-011-T01 Write ADR-0100 (Bonjour discovery and announcing, two opt-in switches, the scan rules) in `docs/adr/0100-osc-local-peer-discovery.md` — Verified 2026-11-15: docs/adr/0100-osc-local-peer-discovery.md and README index; validate_docs OK

## Phase 2: Foundational (pure package)

- [X] OSC-011-T02 [P] `OSCDiscovery` (serviceType `_projectm-osc._udp`, domain `local.`, at most 16 peers, names cleaned to "at most 63 characters, no control characters", announced name "projectM " + 4 hex digits, activity rule, peer filter excluding non-local and own name), `OSCDiscoveredPeer` (`destination` via `OSCSendDestination`), `OSCBrowserEvent`, `OSCPeerBrowsing` in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCDiscovery.swift` — Verified 2026-11-15: OSCDiscoveryTests (7) pass on the macOS host (swift test, 0.005 s)
- [X] OSC-011-T03 `OSCDatagramTransport.advertise(_:)` (default no-op) and `OSCReceiver.setAdvertisement(_:)` applied to the current and every later transport in `OSC/OSCDatagramTransport.swift`, `OSC/OSCReceiver.swift` — Verified 2026-11-15: OSCDiscoveryTests.testReceiverAdvertisementReachesCurrentAndLaterTransports; OSCReceiverTests (8) still pass
- [X] OSC-011-T04 [P] Package tests: names, cleaning (a few fuzz-style inputs), activity truth table, filter (non-local dropped, own name left out, cap 16, sorted), receiver advertisement passes to a spy transport and survives a restart, nil withdraws, in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCDiscoveryTests.swift` — Verified 2026-11-15: swift test --filter "OSCDiscovery|OSCReceiverTests": 16 tests pass; full PerformanceControl suite 337 tests, 0 failures, 33 s

## Phase 3: US2 Discovery off by default (P3) — MVP

**Independent test**: a fresh defaults store with OSC on: zero browsers created, no advertisement passed to the receiver.

- [X] OSC-011-T05 [US2] `OSCDiscoveryCoordinator` (keys `settings.osc.discovery.browse`, `settings.osc.discovery.advertise`, absent → off; injected `makeBrowser`; `conditionsChanged()`), wired in `OSCReceiverCoordinator.apply()` and `AppCoordinator.connectAfterInit` in `Apps/projectM-iOS/Coordinators/OSCDiscoveryCoordinator.swift` — Verified 2026-11-15: OSCDiscoveryCoordinatorTests (7) pass on "OSC11 iPhone 17" (iOS 27.2)
- [X] OSC-011-T06 [US2] Key lists: `ALLOWED_KEYS` (`scripts/run_device_tests.py`), `LibrarySettingsPolicy.excludedKeys`, `LibraryErasePolicy` (`oscDiscoveryKeys` in the Settings erase), the `-uitestResetNotice` reset in `AppCoordinator`, `LibraryBackupAppTests` app keys and excluded set — Verified 2026-11-15: LibraryBackupAppTests and SettingsTests pass on "OSC11 iPhone 17"; LibraryBackup package 87 tests pass
- [X] OSC-011-T07 [US2] App tests: default off with a spy factory (0 browsers, receiver advertisement nil, status "Off") across OSC on/off and background in `Apps/projectM-iOS/Tests/OSCDiscoveryCoordinatorTests.swift` — Verified 2026-11-15: OSCDiscoveryCoordinatorTests.testDiscoveryIsOffByDefaultAcrossOSCAndForegroundChanges: 0 browsers, receiver advertisement nil, no transport asked to announce

## Phase 4: US3 Discovery stops when it should (P3)

- [X] OSC-011-T08 [US3] App tests: browse on creates one browser; off / OSC off / background cancel it and empty the list; advertise on passes the name to the receiver only while OSC is on and the app active; withdrawn (nil) otherwise, in `OSCDiscoveryCoordinatorTests.swift` — Verified 2026-11-15: OSCDiscoveryCoordinatorTests.testBrowserStartsOnlyWithOSCAndStopsOnEveryCondition, testAnnouncingFollowsItsSwitchOSCAndForeground, testFailureIsShownAndNotRetried

## Phase 5: US1 Find and use a nearby device (P3)

- [X] OSC-011-T09 [US1] `NetworkOSCPeerBrowser` (NWBrowser for the one type, peer-to-peer off, cellular prohibited, IPv4 resolution by a UDP connection that sends nothing, 5 s timeout, local check) in `Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/NetworkOSCPeerBrowser.swift`; `NetworkDatagramTransport.advertise` (`listener.service`) — Verified 2026-11-15: OSCDiscoveryLoopbackTests on the macOS host (real NWListener.service + NetworkOSCPeerBrowser) and check_network_symbols OK on the Debug app
- [X] OSC-011-T10 [US1] Host loopback: own announcement found by the browser within 5 s (XCTSkip when the host's mDNS does not answer) in `OSCDiscoveryLoopbackTests.swift` — Verified 2026-11-15: OSCDiscoveryLoopbackTests.testOwnAnnouncementIsFoundWithALocalAddress passed on the macOS host (0.81 s, not skipped): own service found with its port and a local address
- [X] OSC-011-T11 [US1] `OSCDiscoveryView` (two switches, disabled with a note while OSC is off; status; rows with Allow and Use as send destination) and the "Nearby Devices" row in `SettingsView.oscSection`, in `Apps/projectM-iOS/Views/OSCDiscoveryView.swift` — Verified 2026-11-15: OSCDiscoveryUITests passes on "OSC11 iPhone 17" (20.9 s); type-check budget flags: 0 warnings
- [X] OSC-011-T12 [US1] App tests: no auto-approval (fake results reach neither the allow list nor the destination), Allow adds, Use as send destination sets host and port and leaves Send OSC off, IPv6-only peer has no destination, in `OSCDiscoveryCoordinatorTests.swift` — Verified 2026-11-15: OSCDiscoveryCoordinatorTests.testFoundDevicesAreNeverTrustedWithoutATap, testIPv6LinkLocalPeerOffersNoDestination
- [X] OSC-011-T13 [US1] `-uitestFakeDiscovery` (DEBUG) fake browser with two local peers in `Apps/projectM-iOS/Debug/UITestFakeDiscovery.swift`; UI test: switches off by default, turning OSC and Find on shows the list in `Apps/projectM-iOS/UITests/OSCDiscoveryUITests.swift` — Verified 2026-11-15: OSCDiscoveryUITests.testSwitchesDefaultOffAndFindShowsTheList passes (20.9 s)

## Phase 6: US4 No relay (P3)

- [X] OSC-011-T14 [US4] `NSBonjourServices: [_projectm-osc._udp]` and the usage string (discovery) in `project.yml`; the same text in `PermissionCatalog.swift`; privacy policy section in `docs/privacy-policy.md` — Verified 2026-11-15: check_permission_catalog OK; PermissionCatalogTests pass; built Info.plist NSBonjourServices = ["_projectm-osc._udp"]
- [X] OSC-011-T15 [US4] `check_compliance.py`: NWBrowser / NWListener.Service only in the two reviewed files, the only Bonjour type is `_projectm-osc._udp` (Swift and `NSBonjourServices`), no URLSession / host names / `.hostPort(` in the browser file; tests in `scripts/test_scripts.py` — Verified 2026-11-15: test_scripts ComplianceDiscoveryTests (4) pass; check_compliance OK
- [X] OSC-011-T16 [US4] `check_network_symbols.py`: discovery APIs only next to the `NetworkOSCPeerBrowser` marker; service APIs removed from the generic listener allow; tests in `scripts/test_scripts.py` — Verified 2026-11-15: test_scripts NetworkSymbolScanTests (11) pass; check_network_symbols OK on the Debug app (19 images)
- [X] OSC-011-T17 [US4] App test: the built Info.plist's `NSBonjourServices == [OSCDiscovery.serviceType]`, in `OSCDiscoveryCoordinatorTests.swift` — Verified 2026-11-15: OSCDiscoveryCoordinatorTests.testInfoPlistDeclaresOnlyTheAppsBonjourType

## Phase 7: Polish

- [X] OSC-011-T18 Run the repo checks, the package suite, the app tests (Discovery, Settings, LibraryBackupApp, PermissionCatalog, OSC send/peers/receiver) and the UI test; `check_network_symbols.py` and `check_privacy_manifest.py` on the Debug app; type-check budget — Verified 2026-11-15: repo checks OK (compliance, docs, motion, permission catalog, status events), test_scripts 184 tests OK, check_privacy_manifest OK, check_network_symbols OK, app unit tests 50 pass, UI test pass
- [ ] OSC-011-T19 {device} Two devices on one Wi-Fi: B announces, A finds B with its local address within 10 s, "Use as send destination" + Send OSC reaches B; turning A's switch off empties the list (quickstart step 5)

## Dependencies

T02 → T03 → T05 → (T07, T08); T09 → T10; T05 → T11 → T13; T14 → T17; T15, T16 independent. US2 is the MVP (default off).
