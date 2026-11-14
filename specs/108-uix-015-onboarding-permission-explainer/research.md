# Research: UIX-015 Onboarding Permission Explainer

## D1 Where the explainer gates
- **Decision**: at the user's pick: the Camera visual row in Settings and turning on the OSC receiver toggle.
- **Rationale**: the Camera visual is session-only (no scene, show or recovery restores it; checked:
  `recordedVisual(…, beforeCamera:)`), so the row is the only way the camera starts. OSC is turned on only
  by the toggle (the badge only stops it). Gating there shows the explainer right before iOS's prompt.
- **Alternatives**: gating in the camera host before `start()` (would show the sheet over the
  visualizer after Settings closes, separated from the pick; rejected).

## D2 Status per permission
- **Decision**: camera: DEBUG `-uitestCamera <scenario>` maps the stand-in scenario
  (granted/denied/restricted, never-asked → notDetermined, unavailable → nil); otherwise nil when
  `AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position:)` finds no camera (iOS never
  asks; CAM-002-R10), else `PermissionCatalog.state(cameraAuthorization:)`. Local network: iOS has no
  query; the catalog's observed state (listening → granted, policy failure → denied), else notDetermined.
- **Rationale**: one mapping (FILE-013's), injectable for tests.

## D3 Explained flag
- **Decision**: `permission.explained.camera`, `permission.explained.localNetwork`, set on Continue; for
  local network also set when OSC is enabled at launch or the listener is seen listening or denied.
- **Rationale**: local network has no status query, so the flag is the only memory that iOS asked;
  for the camera it also covers the stand-in, whose answer lives only in memory.

## D4 Harness suppression
- **Decision**: reuse UIX-001's rule (`GuidedFirstScenePolicy.isSuppressed` shape) with the opt-in
  argument `-uitestPermissionExplainers`.
- **Rationale**: about 20 UI tests pick Camera or toggle OSC; they test other features.

## D5 Dismiss
- **Decision**: denied and restricted camera notices offer Dismiss; the coordinator keeps a per-attempt
  flag reset when the Camera visual is released or created.
- **Alternatives**: auto-hide after a few seconds (rejected: a VoiceOver user could miss it).

## D6 Fallback texts (new, owned by the catalog)
- Camera notice fallback: "Showing the spectrum only." (CAM-001's wording for no camera).
- Local network notice fallback: "OSC control is unavailable; everything else works as usual."
- Explainer fallbacks: camera "If you don't allow it, the Camera visual shows the spectrum only.";
  local network "If you don't allow it, OSC control stays unavailable and everything else works."
- Explainer note: "iOS asks next. You can change this later in Settings."
