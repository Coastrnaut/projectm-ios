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

## Follow-ups

1. **2026-11-19, prompt-flow on D2 (iPadOS 27.2), testC:** the settle and the 5 s limit count only while the
   application is active (`isActive`), so a browse running while iOS's prompt shows cannot grant before the answer.
2. **2026-11-19, QA-011 pass 9 on D2, testC still failing:** iOS's prompt appeared and was answered Don't Allow, yet
   no denied notice showed within 15 s and the receiver listened (`OSC listening`, `osc=listening`). The run kept no
   record of what the browse reported, so the cause could not be read from the logs. Decided (owner rules 4 and 12):
   - A browse that saw the application inactive is **restarted** when it is active again, before anything is
     decided: a browse already running when the person answered need not report the new policy, while a fresh browse
     reports the denial (`kDNSServiceErr_PolicyDenied`) at once. When the scene itself went inactive the receiver
     already stopped and restarted the probe; this covers the case where only the application's state changed. Still
     bounded: each run stops after 5 s of active time at most, and no browse runs while OSC is off or the app is in
     the background.
   - DEBUG builds keep the probe's last 12 events (`LocalNetworkAccessProbe.history`: starts, browsing, inactive,
     restart, a failure with its code, the decision; never a peer's name) in the hidden `localNetworkProbe` text, and
     `testC_UIX015LocalNetworkExplainerThenPrompt` prints it and names it in its failure, so the next device run says
     which events came. Host tests: `LocalNetworkAccessProbeTests` (restart after inactive; the diagnostic).
   - To confirm on D2 with the prompt-flow batch. If the probe then shows a fresh browse that reports `browsing` and
     no denial after Don't Allow, a browse alone cannot report a denial on iPadOS 27.2 and this ADR needs another
     signal.
3. **2026-11-24, prompt-flow on D1 (iPhone 15, iOS 27.0.1), testC failing on every D1 run (2026-11-22 to 2026-11-24):**
   iOS showed the prompt, the test tapped Don't Allow, and the probe reported
   `access=granted runs=1 running=no | start 1, browsing, stop, settled → granted`. No `inactive` entry: on iOS 27.0.1
   the Local Network prompt left the application active, so the 2 s settle ran out with the prompt still on screen
   (Continue at 11.99 s, prompt read at 13.1 s, Don't Allow tapped at 14.46 s) and the browse was cancelled before the
   answer. The same evidence shows what does report a denial: on D2 the browse still running reported
   `failed policyDenied` after Don't Allow, and on D3 a fresh browse after the answer did (`start 2, browsing, failed
   policyDenied`). Decided (owner rules 4 and 12):
   - A grant that rests only on the settle is **unconfirmed**. It is published at once (no notice, no explainer
     change), but a fresh browse follows after 2 s of active time, and again after each unconfirmed settle, until
     30 s have passed since the first browse of the launch; a settle after that is final. A policy denial or a found
     service is final at once. A denial after a provisional grant changes the answer to denied, which shows the
     notice (D1's test waits 15 s; the first recheck comes about 4 s after the first browse).
   - Still bounded: each browse stops after 5 s of active time at most; the rechecks stop with the receiver (OSC
     off, the app inactive or in the background) and resume with it only while the answer is not final; at most
     about ten 2 s browses per launch when access is granted and no projectM device answers. A browse remains a
     multicast DNS query for projectM's own service type, so Decision 6 holds; the privacy policy's "for a few
     seconds at most" now reads "in a few short looks over half a minute at most, once each time the app is opened".
   - `LocalNetworkAccessProbe.isFinal` tells the two states apart; the DEBUG trace writes
     `settled → granted (unconfirmed)` and `recheck`. Host tests: `LocalNetworkAccessProbeTests` (an unconfirmed
     grant is rechecked and a later denial decides; rechecks end with a final grant after the window; stopping
     cancels a pending recheck and a found service is final).
   - To confirm on D1 with the prompt-flow batch: the expected trace is `start 1, browsing, stop, settled → granted
     (unconfirmed), recheck, start 2, browsing?, failed policyDenied, stop, event → denied`. If a fresh browse on
     iOS 27.0.1 reports only `browsing` after Don't Allow, a browse cannot report the denial there and this ADR needs
     another signal.
