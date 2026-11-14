# Contract: Playback balance (AUD-010)

## C1 CaptureKit

- `InAppPlaybackBackend.setMonitorBalance(_ balance: Double)`: protocol requirement with a default
  no-op extension (scripted backends). `AVInAppPlaybackBackend` keeps the value and applies it to the
  current graph and to every graph it builds later (start, media-services rebuild).
- `InAppPlaybackSource.monitorBalance: Double` (default 0): validated with `MonitorBalance.validated`
  and forwarded to the backend on every set, whether or not a session is running.
- `InAppPlaybackGraph.monitorBalance: Double`: sets the pan of the main mixer's input into the balance
  node. Never cuts, never discards, never touches the tap.
- Guarantee (R3): what `PCMSink` receives does not depend on `monitorBalance`.

## C2 App

- `PlaybackBalanceSetting(defaults:)`, `position`, `reset()`, `onChange`, `isAvailable(for:)`,
  `text(for:)`, `positionKey` (contract in data-model.md).
- `PlaybackBalanceSection(balance:available:)`: identifiers `playbackBalanceSlider` (ACC-005 spec
  label "Balance"), `playbackBalanceValue`, `playbackBalanceCenter`. Double-tap on the slider resets.
- `SettingsView.playbackBalance` / `playbackBalanceAvailable` (nil hides the section, e.g. previews).
