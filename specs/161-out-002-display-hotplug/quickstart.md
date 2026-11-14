# Quickstart: OUT-002 Display Connect Handling

## A. Host and simulator (Mac)

1. `swift test --package-path Packages/PresentationLifecycle --filter HotPlugSettleTests` — settle and hold rules.
2. App unit tests on the iOS 27.2 simulator: `-only-testing:projectM-iOSTests/HotPlugAcceptanceTests`
   plus `ExternalDisplayCoordinatorTests`, `OutputBlackoutCoordinatorTests`, `StatusEventsTests`.
3. UI test: `-only-testing:projectM-iOSUITests/HotPlugUITests` (DEBUG fake display, `-uitestExternalDisplay`):
   a bounced connect moves nothing and leaves no resource; a blacked-out connect is black; the
   source starts once.

Simulator results are never device evidence.

## B. Devices `{device}` (OUT-002-T12)

On D1, D2 (iOS 27) and D3 (iPadOS 26.5), with a USB-C/HDMI adapter and AirPlay:
1. Visualizer running with a scene: plug in, unplug, plug in, unplug. Expect the visual to move each
   time after about 0.3 s, the same preset and parameters, audio uninterrupted, VoiceOver announcing
   connected and disconnected.
2. Start a recording (a native spectrum), plug in a display: the display stays black, the recording
   continues; stop the recording: the visual moves to the display.
3. Black out, plug in: the display is black from the start.
4. Wiggle the connector quickly: no back-and-forth.
