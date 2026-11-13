# No-telemetry verification (FILE-012)

Spec: `specs/076-file-012-no-telemetry-verification/`. Roadmap acceptance: "Local proxy test sees no
connections except explicit StoreKit or user-enabled LAN."

**Result, 2026-11-13 (Mac Studio, Xcode 27.2, iOS 27.2 simulator):** no application-initiated network
activity was found. The built binaries contain no networking code except the OSC listener and
StoreKit linkage; with OSC off, a scripted session of normal use opened no socket and produced no
network log event in the app's process; with OSC turned on by the user, the only endpoint was the
UDP listener on the chosen port. **These are simulator and build results, not device evidence.** The
device check (FILE-012-T11) is open.

## Layer 1: binary scan (`scripts/check_network_symbols.py`)

What it does: every Mach-O image in the app bundle, every architecture: `otool -L` (linked libraries)
and `nm -m -u` (imported symbols with their source library); Network Swift symbols are demangled.

| Rule | Result |
|---|---|
| Forbidden libraries: CFNetwork, WebKit, JavaScriptCore, SafariServices, AuthenticationServices, MultipeerConnectivity, NetworkExtension, SystemConfiguration, CloudKit, PushKit, MapKit, GameKit, libresolv | none linked |
| BSD socket and resolver functions (`socket`, `connect`, `bind`, `listen`, `accept`, `send*`, `recv*`, `getaddrinfo`, `gethostbyname*`, `res_*`, `DNSService*`) | none imported |
| URL loading, socket streams, reachability, Bonjour, web views, browsers (`URLSession`, `NSURLConnection`, `CFHTTP*`, `CFSocket`, `SCNetworkReachability`, `NSNetService`, `WKWebView`, `SFSafariViewController`, `ASWebAuthenticationSession`, `MCSession`) | none imported |
| Network.framework | linked and imported only by the image that defines `NetworkDatagramTransport` (the OSC transport, ADR-0008) |
| Network APIs | listener side only (NWListener, NWParameters, NWEndpoint, NWInterface, NWError, IPv4/IPv6Address, NWConnection receive/start/cancel/state/endpoint); no C-level `nw_*` |
| Outbound Network APIs (`NWConnection(host:port:using:)`, `send`) | only in Debug, in the image that defines the DEBUG-only `OSCLoopbackSender` (OSC-001-R19); absent from Release, and `--release` fails if the sender is present |
| StoreKit | linked (allowed: purchase and restore requests are made by iOS's store service) |

Runs, 2026-11-13:

| Build | Images | Result |
|---|---|---|
| Debug, iOS Simulator (with the injected unit-test bundle) | 19 | OK. PerformanceControl framework: Network linked, 59 listener-side + 4 loopback-sender imports. `projectM-iOS.debug.dylib`: StoreKit |
| Release, iOS Simulator (`--release`) | 4 | OK. `projectM-iOS` (packages linked in): Network listener-side only, StoreKit |
| Release, generic iOS device (`--release`) | 4 | OK. `projectM-iOS`: 53 listener-side Network imports, StoreKit |
| Debug, generic iOS device (what CI builds) | 6 | OK. `projectM-iOS.debug.dylib`: 59 listener-side Network imports, StoreKit |

ANGLE (`libEGL`, `libGLESv2`) and projectM (`projectM-4`) have no findings in any build.

The scan's own tests (`NetworkSymbolScanTests`, 9 tests) feed recorded tool output for every rule and,
on macOS, compile a C program that calls `getaddrinfo`, `socket` and `connect`: the scan fails on it
and passes an empty program (positive control). CI runs the scan on the Debug generic-iOS app after the
app build (`.github/workflows/ios-ci.yml`).

**Proves:** no image in the bundle can open a socket, resolve a name or load a URL through the APIs
listed, and the only Network-framework code is the OSC listener (plus the loopback sender in Debug).
**Does not prove:** what system frameworks do internally. Foundation and AVFoundation APIs that accept a
URL (`Data(contentsOf:)`, players) could reach the network with a remote URL without importing any
networking symbol; the app's sources use them with local file URLs only, which no scan proves. A
symbol list also cannot prove that the listener's code is reached only when the user enables OSC; that
is the runtime layer's job and OSC-001's tests.

## Layer 2: runtime observation on the simulator (`scripts/observe_app_network.py`)

Method: a simulator app is a Mac process on the Mac's network stack, so the Mac can observe it
directly. The observer wraps the `xcodebuild test-without-building` command and, for the whole run:

1. finds every process of `projectM-iOS` installed in the given simulator (`ps`; each UI test
   relaunches the app);
2. samples their internet sockets (`lsof -a -i -n -P -F pftPn -p <pids>`), requested every 0.2 s; with
   `ps` and `lsof` each pass took about 0.45 s on the Mac Studio (192 samples in 85.5 s);
3. records the simulator's log events from the `com.apple.network*` and `com.apple.CFNetwork*`
   subsystems for the app's process (`xcrun simctl spawn <udid> log stream --style ndjson`). These
   record a connection's creation even when it closes between two socket samples;
4. with `--expect osc:<port> --probe`: when the app's UDP listener appears, sends one OSC datagram
   from 127.0.0.1 to it and then requires both layers to show the resulting peer.

Classification: with `--expect none` any socket and any log event fails, except launch bookkeeping
(`activity` events that report app-launch durations, and `networkd_settings_read_from_file_locked`),
which appear with no networking at all. With `osc:<port>`, only the listener on the port, inbound peers
from the probe, listener events and connections the log describes as server-side pass; outbound
sockets, client connections, resolver and URL-loading events fail. A blind run fails: no app process
seen, no log stream, or a requested probe not seen.

Does it really see simulator sockets? Yes, checked by hand and then by the observer itself:

- by hand, 2026-11-13: with OSC on (port 47129), `lsof -a -i -n -P -p <pid>` listed `UDP *:47129`; after
  a datagram from the Mac, also `UDP 127.0.0.1:47129->127.0.0.1:55802`; with OSC off it listed nothing.
  The log stream showed `[L1]` listener and `[C1 … udp, server …]` connection events for the same
  datagram;
- negative control: launching the app with OSC on under `--expect none` failed with 9 problems (the
  listener socket and 8 listener log events);
- every OSC run with `--probe` must see the probe in both layers, or it fails as blind.

Runs, 2026-11-13, own simulator "FILE12 iPhone 17" (iOS 27.2), Debug build, store stubbed
(`-uitestUnlocked NO`):

| Run | Tests (`NoTelemetryUITests`) | Result |
|---|---|---|
| `--expect none` | notice → chooser → In-App Playback and a preset switch (6.4 s); seeded Photo, Video, Text (16.3 s); Circular and Linear Spectrum, projectM (19.9 s); Save Frame PNG and a short recording of the Photo visual (12.4 s); four show cues and Settings › Storage › Clear Caches (15.1 s) | **OK**: 5 app processes, 192 samples, **0 sockets**, 65 log events, **0 relevant** |
| `--expect osc:47131 --probe` | OSC turned on in Settings, listening on 47131 for 3 s, turned off (16.9 s) | **OK**: 1 process, 45 samples, sockets `UDP *:47131` (listener) and `127.0.0.1:47131->127.0.0.1:61566` (the probe) only; 60 relevant log events: listener events and one server-side connection (the probe); **0 outbound** |

Commands:

```bash
U=<simulator udid>; T=projectM-iOSUITests/NoTelemetryUITests
python3 scripts/observe_app_network.py --udid $U --executable projectM-iOS --expect none --report none.json -- \
  xcodebuild test-without-building -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination id=$U \
  -derivedDataPath <dd> CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:$T/testNoticeChooserAndInAppPlayback -only-testing:$T/testVisualsWithSeededPhotoVideoAndText \
  -only-testing:$T/testSpectraAndProjectM -only-testing:$T/testSaveFrameAndShortRecording \
  -only-testing:$T/testShowCuesAndStorageCleanup
python3 scripts/observe_app_network.py --udid $U --executable projectM-iOS --expect osc:47131 --probe \
  --report osc.json -- xcodebuild test-without-building … -only-testing:$T/testUserEnabledOSCListensOnly
```

**Proves (simulator):** during that session the app's own process opened no network socket and the
networking stack logged no connection, listener or resolver for it; with OSC on, the only endpoint was
the user-enabled local UDP listener, which made no outbound connection.

**Does not prove:**

- *Work done by other processes for the app.* StoreKit requests (made by iOS's store service; stubbed
  here), crash and diagnostic reporting by the OS, App Store updates, push: these are not
  application-initiated, and the observer filters on the app's process, so it does not see them.
- *The device.* The device has its own network stack and system services; the simulator shares the
  Mac's. Simulator results are never device evidence: FILE-012-T11.
- *Code paths outside the session.* The session covers the main flows (notice, chooser, In-App Playback,
  preset switches, the native visuals with seeded Photo, Video and Text, Settings, Storage and Clear
  Caches, Save Frame, a recording, show cues, OSC on and off). Imported audio, the camera, the preset
  browser and purchase sheets were not driven; Layer 1 covers them statically.
- *Raw sockets shorter than one sample.* Not logged by the networking stack; the binary scan shows no
  image imports socket functions, so the app has no code to open one.
- *That the listener closed when the user turned OSC off.* The app's status showed "Off" (and
  OSCReceiverUITests covers it); the observer does not check that the socket disappeared.

## Layer 3: device (`{device}` FILE-012-T11, open)

On D1: Settings › Privacy & Security › App Privacy Report on; run the session of Layer 2 by hand with
OSC off (notice, chooser, In-App Playback, visuals, Save Frame, a recording, show cues, Clear Caches);
then the report's entry for projectM-iOS should list no "App Network Activity". Repeat with OSC on and
a sender on the local network: the app is expected to show local-network listening only. Alternatively
the owner sets up a Mac proxy (Charles or mitmproxy) and reads its log for the session. Not run.

## Gates on 2026-11-13

`check_compliance.py` OK; `validate_docs.py` OK; `test_scripts.py` 134 tests OK (7.5 s, 1 skipped:
non-macOS path); `check_privacy_manifest.py` OK on the Debug simulator app; OSCReceiverUITests and
OSCNetworkAccessUITests still pass (17.6 s, 16.5 s); PosterBoard crash reports 32 before and after.
