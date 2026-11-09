# Draft question to Apple: Screen Recording entitlement on iOS 27

For the Apple Developer Forums (tags: ScreenCaptureKit, Entitlements) or a DTS request. Written
2026-11-09 (ADR-0001 ruling 15). The owner sends it; record the answer in ADR-0001.

**Status (2026-11-09, ruling 16):** on hold. The owner found the capability is offered only to
organization accounts and removed the entitlement; send this only if T040 fails with `-3803`.

---

**Title:** How does a third-party iOS 27 app get com.apple.developer.screen-recording for ScreenCaptureKit?

I'm building an iOS app that uses ScreenCaptureKit on iOS/iPadOS 27 to capture **audio** from
content the user chooses in the system content-sharing picker (`SCContentSharingPicker.present()`,
then an `SCStream` with `capturesAudio = true` and an `.audio` output). Video frames are discarded;
nothing is recorded or sent off the device.

Apple's sample "Capturing screen content on iOS" (CapturingScreenContentInIOS.zip) declares the
entitlement `com.apple.developer.screen-recording = true`, and its README says to select a team in
Signing & Capabilities "so the app can be provisioned with the Screen Recording entitlement".

With my paid developer team, automatic signing in Xcode 27.2 (27B52) fails with:

> Entitlement com.apple.developer.screen-recording not found and could not be included in profile.

I found no Screen Recording capability for my App ID in Certificates, Identifiers & Profiles, and
no reference page for this entitlement. `SCStreamError.missingEntitlements` (-3803) exists but
doesn't name an entitlement.

Questions:

1. Does ScreenCaptureKit capture on iOS 27 (via `SCContentSharingPicker` and `SCStream`) require
   `com.apple.developer.screen-recording` for a third-party app?
2. If yes, how is it obtained (a capability to enable, or a request form), and is it available
   for App Store distribution?
3. If no, should the sample's entitlement be removed, and is `NSScreenCaptureUsageDescription` the
   only requirement?

Thanks!
