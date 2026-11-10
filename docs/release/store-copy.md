# Store listing and in-app help review (task T110; FR-062)

Reviewed 2026-11-10 against `docs/test-reports/compatibility-report.md`. **The report has no row
rated "Works" or "Partial"** (Gates 1 and 2 waived, ADR-0001 rulings 18 and 19; Stage Decision
"Claimable sources: None"). So the listing and the in-app text make **no compatibility claim**: no
named third-party app, no "system audio" or "any app" wording, no iPad-specific claim. The only
wording for System/App Capture is the Stage Decision's: "where iOS allows it".

## App Store listing (draft)

**Name**: projectM-iOS (store name; "projectM" and "projectM Visualizer" were taken on the App Store, owner choice 2026-11-10). The home-screen name stays "projectM".

**Subtitle**: Music visualizer

**Category**: Music; secondary Entertainment

**Promotional text**: Turn sound into motion with the projectM visualization engine.

**Description**:

> projectM turns audio into full-screen visuals, using the open-source projectM engine and a
> collection of classic Milkdrop presets.
>
> Choose a source:
> • System/App Capture: visualize audio from content you choose to share, where iOS allows it.
>   iOS asks each time and shows that sharing is on.
> • Microphone: visualize sound in the room.
> • In-App Playback: visualize the built-in reference track.
>
> Browse presets, mark favorites, or jump to a random one. Controls fade away so the visuals
> fill the screen, in portrait or landscape.
>
> Your audio stays on your device: it is processed in memory only, never recorded or sent
> anywhere. The app collects no data and makes no network connections.
>
> Photosensitivity: the visuals can flash. Turn on Reduce flashing in Settings (on by default
> when Reduce Motion is on).
>
> Free and open source: https://github.com/Coastrnaut/projectm-ios

**Keywords**: visualizer, music, milkdrop, projectm, audio, visuals, microphone

**What's New (1.0)**: First release.

## In-app text

The app has no help screen; its user-facing descriptions are the chooser's FR-080 lines and the
usage descriptions, all verbatim from `contracts/ui-states.md` (`Packages/CaptureUI/.../UIStrings.swift`,
`Apps/ProjectMiOS/Info.plist`). None names an app or promises capture.

## Claim check

| Statement | Kind | Basis |
|-----------|------|-------|
| "visualize audio from content you choose to share, where iOS allows it" | Capability, unscoped by design | Stage Decision product wording (compatibility report); no source rated, so no app is named |
| "iOS asks each time and shows that sharing is on" | System behavior | FR-002 (picker for every start); T040 |
| Microphone, In-App Playback descriptions | Feature | FR-080 strings (`contracts/ui-states.md`) |
| Presets, favorites, random, controls, orientation | Feature | US4, US5 (T080-T091) |
| Audio stays on the device; no data collected; no network | Privacy | FR-060, FR-068; `docs/privacy-policy.md`; `docs/release/app-privacy.md` |
| Reduce flashing, on by default with Reduce Motion | Accessibility | FR-072; T103, T104 |
| Compatibility with a named app, "system audio", "works with any app" | **Not made** | No "Works" row (FR-062) |
| iPad-specific claim | **Not made** | No iPad "Works" row (FR-062) |

Every compatibility claim must cite a "Works" row; there are none, so there are no compatibility
claims. If T051/T052 later rate a source "Works", a scoped line ("Tested with <app> <version> on
iOS <range>, iPhone[/iPad]") may be added with its report row cited here.
