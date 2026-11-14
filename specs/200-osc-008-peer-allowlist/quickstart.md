# Quickstart: OSC-008 OSC Peer Allowlist

1. Package tests (any host): `swift test --package-path Packages/PerformanceControl --filter OSCPeer` — rule,
   text form, acceptance (unapproved host cannot change a routed parameter; approved applies), seeded fuzz.
2. Loopback integration (macOS host): `--filter OSCLoopbackIntegrationTests` — with the allowlist on and
   127.0.0.1 not approved a real UDP datagram changes nothing; after approving it, it applies.
3. App unit tests on "OSC8 iPhone 17": `-only-testing:projectM-iOSTests/OSCPeersCoordinatorTests`.
4. UI test: `-only-testing:projectM-iOSUITests/OSCPeersUITests` — open Settings › OSC › Approved Devices,
   turn the switch on, see the empty-list note.
5. `{device}` LAN check: OSC on, allowlist on, send from a second device on Wi-Fi: nothing changes and it
   appears under Recently blocked; tap Allow; its next message changes the glow.
