# Data Model: FX-010 Echo Feedback

## EchoFeedback (Compositor, plain Swift)

| Field | Type | Range / default | Notes |
|-------|------|-----------------|-------|
| isEnabled | Bool | false | |
| count | Int | 0…4 (`cap`), 3 | > 4 → 4; < 0 → 0; 0 is inactive |
| delaySeconds | Double | 0.01…0.5, 0.1 | NaN → default, clamp |
| decay | Double | 0.1…0.9, 0.6 | NaN → default, clamp |
| weightCap | Double | 0…1, 1 | not user-set; ACC-012 lowers it (`limited(by:)`) |

Derived: `isActive` (enabled, count ≥ 1, weightCap > 0), `weights(valid:)` (n = min(count, valid) weights, sum ≤
weightCap), `historySize(width:height:)`, `historyBytesBound` (29,491,200), `downsample`, `referencePixel`,
`reference`.

## EchoSchedule (Compositor, plain Swift)

Fields: `valid` (0…4 stores), `newest` (slot index), `sinceStore` (seconds), `storeNow` (after a reset).
`mutating func advance(frameDuration:delay:) -> Bool` (store this frame?), `mutating func stored()`, `echoSlots(n)`
(slot of echo k = newest − (k − 1) mod 4), `nextSlot` (oldest), `reset()`.

## OutputEffectKind

… existing kinds, then `echo` (`fx.echo`, new, appended). Standard order ends with echo.

## Scene `effects` entry

`{"kind": "fx.echo", "enabled": Bool, "parameters": {"count": 0…4, "delay": 0.01…0.5, "decay": 0.1…0.9}}`; missing →
default, out of range → clamped and reported (`valueClamped`).

## App setting keys

`settings.echo.enabled` (Bool), `settings.echo.count` (Int as number), `settings.echo.delay` (Double seconds),
`settings.echo.decay` (Double). Absent → defaults; included in backups and erase; removed by the UI-test reset.
