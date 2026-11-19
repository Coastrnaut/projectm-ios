# ADR-0125: The OSC receiver browses once to obtain the Local Network permission

- **Status**: Accepted 2026-11-19 (decided under the owner's standing delegation; owner rules 4 and 12)
- **Feature**: OSC-001 (`specs/032-osc-001-osc-receiver`), with UIX-015 and FILE-013; found by QA-011's prompt-flow batch
- **Constitution**: I (public APIs only), VI (modular boundaries); Platform, Security & Privacy
- **Amends**: ADR-0100's scope (browsing was used only by "Find nearby devices"); `PermissionCatalog.state(localNetwork:)`
  ("listening proves access"); the privacy policy's "OSC control on your local network" section

## Context

The first prompt-flow run on D2 (iPad Pro M5, iPadOS 27.2) and D3 (iPad A16, iPadOS 26.5), 2026-11-19
(`.autonomous/logs/prompt-flow-D2-20261119-114732`, `prompt-flow-D3-20261119-114732`):

- Turning "OSC receiver" on opened the UDP listener (`NetworkDatagramTransport`), which reached "Listening on port
  9000" and iOS showed **no** Local Network prompt (D3 testD; testZ on both).
- iOS lists Local Network on the app's Settings page only after it has asked, so the permission could neither be
  granted nor turned off there (testZ: "Local Network is listed on the app's Settings page" failed on both).
- The app treated "listening" as "granted" (`PermissionCatalog.state(localNetwork:)`), so with access never asked it
  showed no explainer status change, no denied notice (FILE-013, D3 testD) and OSC-001-T26 ("the Local Network prompt
  appears on first enable") could not pass.

iOS has no API to query or request the Local Network permission. It asks when an app first uses the local network
in a way the privacy system mediates; a Bonjour browse is the documented trigger, and a browse that is not allowed
reports DNS-SD's `kDNSServiceErr_PolicyDenied` (-65570), which the app already maps to `.localNetworkDenied`.

## Decision

1. **One short browse when needed.** When the receiver starts (OSC on and the app active) and the answer is unknown
   this launch, `OSCReceiverCoordinator` runs `LocalNetworkAccessProbe`: one Bonjour browse with
   `NetworkOSCPeerBrowser(resolves: false)` for the app's own declared type `_projectm-osc._udp` in `local.` (already
   the only entry of `NSBonjourServices`). With `resolves: false` nothing found is resolved: no `NWConnection` or any
   other flow is created, nothing is announced, and found names are used only to decide.
2. **Answer.** A policy denial (from the browse, or the listener's own failure) is **denied**; a found service, or
   browsing for 2 s while the app stays active, is **granted**; anything else stays **unknown**. Listening alone
   proves nothing. iOS's prompt makes the app inactive, which stops the receiver and cancels the browse without a
   decision; the next start after the answer runs it again and decides.
3. **Bounded.** The browse stops as soon as it decides and after 5 s at most, and never runs while OSC is off or the
   app is not active. The answer is kept in memory for this launch only (iOS ends an app whose permission is revoked
   in Settings, so the next launch asks the browse again).
4. **Shown.** The denied notice (FILE-013, with Open Settings) shows while OSC is on and the answer is denied; the
   explainer (UIX-015) reads the same state, so it never shows after a denial.
5. **Scans unchanged.** `NWBrowser` stays in `OSCTransport/NetworkOSCPeerBrowser.swift`, which still browses exactly
   `.bonjour(type: OSCDiscovery.serviceType, domain: OSCDiscovery.domain)`; the app only creates the reviewed browser
   with a flag. `check_compliance.py` and `check_network_symbols.py` are not changed.
6. **Privacy.** The policy's OSC section says that the receiver looks for projectM's own service for a few seconds
   so that iOS can ask, connects to nothing it finds, keeps nothing and announces nothing. "Never connects out" stays
   true: a browse sends multicast DNS queries on the local link and opens no connection. Nothing leaves the local
   network and nothing is collected, so the App Privacy answer ("Data Not Collected") is unchanged.
7. **DEBUG fakes.** With `-uitestFakeOSC`, `-uitestOSCFailure` or `-uitestFakeDiscovery` the probe makes no browser
   (those runs use no real network); simulator results are never evidence for this.

## Consequences

- On a fresh install the first enable raises iOS's Local Network prompt (OSC-001-T26), after which Local Network is on
  the app's Settings page; a denial shows the catalog's notice. To confirm on D2 and D3 with the prompt-flow batch.
- A device with OSC on runs one browse of at most 5 s per launch while the answer is unknown.
- If a future iOS mediates plain UDP listening, the browse still decides first; nothing else depends on it.

## Alternatives rejected

- **Sending a datagram** to a local broadcast or multicast address: would make the receiver send, against OSC-001's
  "listens only" and ADR-0008's scope.
- **Announcing the receiver** (`NWListener.service`) on enable: reveals the device to its network without the user's
  separate "Let nearby devices find this one" choice (ADR-0100 Decision 2).
- **Waiting for inbound traffic** to make iOS ask: depends on a controller sending at the right time, and the prompt
  would appear mid-show instead of at the user's tap.
- **Keeping "listening means granted"**: false on D2 and D3; the denied notice could never appear.
