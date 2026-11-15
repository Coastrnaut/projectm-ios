# Data Model: UIX-006 Touch Gesture Mapping

## PerformanceGesture (enum, String raw values, precedence order)

| Case | Raw | Rank (lower wins) | Title |
|---|---|---|---|
| threeFingerTap | `threeFingerTap` | 0 | Three-finger tap |
| twoFingerSwipeLeft | `twoFingerSwipeLeft` | 1 | Two-finger swipe left |
| twoFingerSwipeRight | `twoFingerSwipeRight` | 2 | Two-finger swipe right |
| twoFingerSwipeUp | `twoFingerSwipeUp` | 3 | Two-finger swipe up |
| twoFingerSwipeDown | `twoFingerSwipeDown` | 4 | Two-finger swipe down |
| twoFingerTap | `twoFingerTap` | 5 | Two-finger tap |

## GestureAction (enum, String raw values)

`none`, `nextCue` ("Next cue (Go)"), `previousCue`, `nextPreset`, `previousPreset`, `tapTempo`, `toggleHUD`
("Show/hide HUD"). No blackout, restore or editing action exists in the type.

## GestureShortcutConfiguration (struct, Codable, Equatable)

- `isEnabled: Bool` (default false)
- `mapping: [PerformanceGesture: GestureAction]` (missing → `defaultMapping[gesture] ?? .none`)
- `action(for:)`, `setting(_:for:)`; `json` / `init(json:)` (unknown names ignored, damaged JSON → default)

## GestureTouchSummary (struct)

`maxTouches: Int`, `translation: (dx, dy)` average displacement in points, `maxDisplacement: Double`, `duration: TimeInterval`.

## GestureClassifier / GestureShortcutResolver (pure)

- `GestureClassifier.recognise(_ summary) -> Set<PerformanceGesture>` (thresholds in `GestureThresholds`).
- `GestureShortcutResolver.resolve(_ recognised, configuration, voiceOverRunning) -> GestureShortcutResolution?` (`gesture`, `action`), nil when off, VoiceOver, or nothing mapped.

## Stored key

`settings.gestures.shortcuts` (String, JSON of the configuration). FILE-005 included; FILE-011 Settings erase; removed by `-uitestResetNotice`.
