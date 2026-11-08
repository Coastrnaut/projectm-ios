## Summary

<!-- What changed and which tasks (Txxx) / requirements (FR-/SC-) it covers. -->

## Constitution checklist (required on every merge)

- [ ] I. Public Apple APIs only. No private APIs, undocumented entitlements, DRM circumvention, or capture-restriction bypasses (`scripts/check_compliance.py` passes)
- [ ] II. Nothing here assumes external-app audio works beyond what the compatibility report shows
- [ ] III. System/App Capture uses ScreenCaptureKit only; no ReplayKit, no extension
- [ ] IV. Source labels and audio states are truthful (ui-states contract)
- [ ] V. No universal-capture or app-compatibility claims
- [ ] VI. Module boundaries respected (capture types stay in CaptureKit)
- [ ] VII. Real-time callbacks: no allocation, locks, logging, or main-thread work
- [ ] VIII. No changes under `Vendor/` (or a patch-log entry in `docs/projectm-patches.md`)
- [ ] IX. New dependencies are pinned and license-reviewed
- [ ] X. Tests added/updated; device-only claims backed by recorded device evidence
- [ ] Platform: build/test results from Windows are reported as "pending macOS"

## Test evidence

<!-- CI link, swift test output, device exports. Say explicitly what could not be run. -->
