# Quickstart: OSC-011 Local Peer Discovery

1. Package: `swift test --package-path Packages/PerformanceControl --filter OSCDiscovery` — pure rules and the host loopback (may skip without mDNS).
2. Scripts: `python3 scripts/test_scripts.py`, `python3 scripts/check_compliance.py`, `python3 scripts/check_permission_catalog.py`.
3. App: `xcodegen generate`; build-for-testing on "OSC11 iPhone 17"; `test-without-building -only-testing:projectM-iOSTests/OSCDiscoveryCoordinatorTests -only-testing:projectM-iOSUITests/OSCDiscoveryUITests`.
4. Built app: `python3 scripts/check_network_symbols.py <Debug .app>` → OK; `plutil -extract NSBonjourServices json -o - <app>/Info.plist` → `["_projectm-osc._udp"]`.
5. `{device}`: two devices on one Wi-Fi; B: OSC on + "Let nearby devices find this one"; A: OSC on + "Find nearby devices" → B listed with its local address within 10 s; "Use as send destination" + Send OSC on → a scene change on A reaches B (B's OSC Routes shows an unknown-address count rising for `/projectm/scene`). Turning A's switch off empties the list.
