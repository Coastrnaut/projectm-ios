# Contract: primary-screen manifest and checks (QA-009)

## M1 Manifest

`Apps/projectM-iOS/UITests/PrimaryScreensManifest.swift` holds `PrimaryScreens.all`. Each required
control is written `RequiredControl("<identifier>", .<type>)` on one line, so `scripts/qa009_manifest_check.py`
can parse it. Adding a primary screen = adding an entry plus three one-line test methods.

## M2 Checks per screen and layout

For each required control, in manifest order:

1. it exists within 5 s (lazy rows: after the one scroll);
2. its label, trimmed, is non-empty and differs from its identifier;
3. it is wholly inside the visible area (below a navigation bar, above a bottom search field; inside the
   controls' scroll view for overlay controls) and hittable, with at most one scroll (research D3).

Then the system audit (research D2) passes with only the existing per-element filters.

## M3 Failure messages

`[<screen> @ <layout>] <control>: <what failed>` for controls; `[<screen> @ <layout>] audit: <issue>` for
audit findings, with a screenshot attached on failure.

## M4 Source check

`python3 scripts/qa009_manifest_check.py` exits non-zero and names each manifest identifier that appears
nowhere in `Apps/projectM-iOS` sources outside the test targets: neither as a string literal `"<id>"` nor
as a literal prefix (`"<prefix>` followed by `\(` or `" +`) whose remainder is a plausible dynamic part.
`scripts/test_scripts.py` runs it on the repository and on a fixture with a renamed identifier.

## M5 Run split

Default: `standard` and `ax5`. `TEST_RUNNER_QA009_FULL=1` adds `ax3`.
