# Quickstart: PRE-010 Preset Quick Audition

Checks (simulator "PRE10 iPhone 17", iOS 27.2; simulator results are not device evidence):

1. Unit: `-only-testing:projectM-iOSTests/PresetAuditionAcceptanceTests` — acceptance (S1), Keep (S2),
   failures (S3), committed selection ends a preview, Preview availability.
2. UI (under 30 s): `-only-testing:projectM-iOSUITests/PresetAuditionUITests` — seed Calm tags, choose
   A from "Tagged: Calm", preview two others, Cancel, close the browser: `currentPreset` is A and the
   scope line still starts with "Tagged".
3. Manual (optional, any device): open Presets, touch and hold a row → Preview; the bar shows the
   name; Cancel brings the original back; Keep closes the browser on the previewed preset.
4. Repo checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
   `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`.
