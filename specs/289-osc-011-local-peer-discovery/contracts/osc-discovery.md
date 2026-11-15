# Contract: OSC-011 discovery

## D1 Package (PerformanceControl, pure)

- `OSCDiscovery.serviceType == "_projectm-osc._udp"`, `OSCDiscovery.domain == "local."`, `maximumPeers == 16`, `maximumNameLength == 63`.
- `OSCDiscovery.announcedName(suffix: UInt16) -> String` ("projectM 0A1F"); `randomAnnouncedName()`.
- `OSCDiscovery.cleanName(_:) -> String`: drops control characters, trims, cuts to 63 characters; empty → "Unnamed device".
- `OSCDiscovery.activity(browse:advertise:oscEnabled:appActive:) -> Activity`.
- `OSCDiscovery.peers(_ raw: [OSCDiscoveredPeer], excluding: String?) -> [OSCDiscoveredPeer]`: cleans, drops non-local, leaves out own name, sorts by name, caps at 16.
- `OSCDiscoveredPeer.destination: OSCSendDestination?`.
- `protocol OSCPeerBrowsing: AnyObject, Sendable { func start(events:); func cancel() }` — after `cancel()` no event is reported.
- `OSCDatagramTransport.advertise(_ name: String?)` (default no-op); `OSCReceiver.setAdvertisement(_:)` applies to the current transport and every later one.

## D2 Transport (OSCTransport/, Network)

- `NetworkOSCPeerBrowser`: `NWBrowser(for: .bonjour(type: OSCDiscovery.serviceType, domain: OSCDiscovery.domain))`, peer-to-peer off, cellular prohibited; resolution as research D3; reports `.peers` after each change.
- `NetworkDatagramTransport.advertise(name)`: sets `listener.service = NWListener.Service(name:type:domain:)` (nil withdraws), before start or live.

## D3 App

- `OSCDiscoveryCoordinator(osc:defaults:makeBrowser:)`; `setBrowse(_:)`, `setAdvertise(_:)`, `conditionsChanged()` (called from `OSCReceiverCoordinator.apply()`), `allow(_:)`, `useAsSendDestination(_:)`; `peers`, `statusText`, `isBrowsing`, `advertisedName`.
- Settings › OSC row "Nearby Devices" (`oscDiscoveryLink`) → screen with `oscDiscoveryBrowseToggle`, `oscDiscoveryAdvertiseToggle`, `oscDiscoveryStatus`, rows `oscDiscoveredPeer_<i>` with `oscDiscoveryAllow_<i>`, `oscDiscoveryUseAsDestination_<i>`.
- Launch argument `-uitestFakeDiscovery` (DEBUG): the browser reports two fixed local peers.
