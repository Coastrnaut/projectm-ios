# Data Model: MED-011 Clock Overlay

## ClockOverlaySettings (plain Swift, `TextLayer`)
| Field | Type | Default | Rule |
|---|---|---|---|
| isShown | Bool | false | Off by default (R1) |
| hourCycle | ClockHourCycle (`twentyFourHour`, `twelveHour`) | twentyFourHour | Unknown raw value → default |
| showsSeconds | Bool | false | |
| style | TextOverlaySpec (message ignored, stored empty) | Menlo, bold, size 0.06, white, trailing, top, default outline | Clamped by `TextOverlaySpec` |

Stored as JSON `{"version":1,"isShown":…,"hourCycle":…,"showsSeconds":…,"style":{…}}` (sorted keys) in
UserDefaults `settings.clock.overlay`. `decodeStored`: `.settings`, `.unsupportedVersion(n)`, `.damaged`.

## ClockSource
`now: Date`, `timeZone: TimeZone`. `SystemClockSource` (wall clock, `TimeZone.current`); `FixedClockSource`
(tests, DEBUG fixture).

## ClockFormatter
`init(hourCycle:showsSeconds:locale:timeZone:)`; `string(for: Date) -> String`; `pattern`.

## ClockText
Holds a formatter and the last string. `update(at: Date) -> String?` returns the string only when it differs from
the last one. `spec(for:)` on settings = style with the string as the message.

## ClockSchedule
`delay(after: Date) -> TimeInterval` = time to the next whole second (0 < d ≤ 1).

## App state
`ClockOverlayCoordinator`: `settings` (saved on change), `currentText`, weak clock layers, tick task.
