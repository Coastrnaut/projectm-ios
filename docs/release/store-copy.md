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

## Feature 002 additions (full preset library, T240)

Reviewed 2026-11-10. Still no compatibility claim.

**In-App Purchase** (App Store Connect, T242): "Full Preset Library",
`org.projectmios.ProjectMiOS.fullLibrary`, non-consumable, $1.99. Description: "Unlocks the projectM
team's full preset library: 12,913 more presets."

**Description**: add this paragraph after the "Browse presets" one:

> Includes 28 presets. A one-time purchase unlocks the projectM team's full preset library: 12,913
> more presets from the Cream of the Crop, projectM Classic, Milkdrop Original and En D packs.
> Browse them by pack and folder, search by name or author, and keep favorites across packs. The
> library is already in the app, so it works offline.

Replace "Free and open source" with "Open source", because the app now offers an in-app purchase.
Replace "The app collects no data and makes no network connections." with "The app collects no
data; the only network use is the App Store's own purchase and restore."

**Keywords**: add "presets".

**What's New (1.1)**: The full projectM preset library (12,913 more presets) as a one-time
purchase, with a new browser: packs, folders, search and favorites across packs.

| Statement | Kind | Basis |
|-----------|------|-------|
| "Includes 28 presets" | Feature | Index: 28 Included (`docs/test-reports/preset-library.md`) |
| "12,913 more presets" and the four pack names | Feature | Index counts, ADR-0007, README 18.1 |
| "works offline" | Feature | Archive bundled (R-30); entitlement from StoreKit's local records (FR-110); device check T239 |
| Browse by pack and folder, search, favorites across packs | Feature | FR-111-FR-114; PresetLibraryUITests |
| Only network use is the App Store's | Privacy | FR-122; `docs/privacy-policy.md` |

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
