# Contract: Motion policy and its test hooks (ACC-001)

## C1 — App code

- Every app-owned decorative animation goes through `MotionPolicy`:
  `.reduceMotionAware(policy.controlsAnimation, value: v)` or `policy.decoration(_:)` /
  `policy.seconds(_:)` for imperative code.
- A safety fade (flash safety, content) is written `.animation(MotionPolicy.safetyFade(...), value:)`
  and is never shortened by Reduce Motion.
- `scripts/check_motion_policy.py` exits 1 and lists `path:line` for any `withAnimation(`,
  `.animation(` or `UIView.animate` in `Apps/projectM-iOS` (excluding `Tests/`, `UITests/` and
  `MotionPolicy.swift`) that does not contain `reduceMotionAware(` or `MotionPolicy.` on the same
  line; exit 0 otherwise.

## C2 — DEBUG test hooks (absent from Release)

| Hook | Kind | Contract |
|---|---|---|
| `-uitestReduceMotion YES\|NO\|system` | launch argument | YES/NO: starting Reduce Motion state instead of the system's; the system notification is then ignored. `system`: the real setting, panel shown (research D5). |
| `simulateReduceMotionToggle` | small test button (only with the argument) | Flips the override and calls `systemReduceMotionChanged`, exactly as the system notification does. |
| `motionProbe` | accessibility value (beside the toggle, only with the argument) | `reduce=<on\|off> controls=<seconds\|none>`; seconds is the last controls transition's duration with two decimals (`0.00`, `0.20`), `none` before the first one. |
