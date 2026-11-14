# Data Model: MOD-006 Threshold Trigger

## ThresholdTriggerSettings

| Field | Type | Rule |
|---|---|---|
| high | Double | finite, 0…1, > low |
| low | Double | finite, 0…1, < high |
| minimumIntervalSeconds | Double | finite, 0…60; default 0.1 |
| holdSeconds | Double | finite, 0…60; default 0 |

## ThresholdTrigger (state)

| Field | Meaning |
|---|---|
| settings | the settings above |
| isArmed | true at creation; false after a fire or consumed crossing until `value < low` |
| aboveSince | time the current run above `high` began (nil when not above) |
| lastFire | time of the last fire (nil before the first) |
| latestTime | the latest time seen (earlier times are clamped to it) |

Transitions per step (value v, time t):
1. t ← max(t, latestTime).
2. v not finite → aboveSince = nil; return false.
3. Disarmed: if v < low → armed. Return false.
4. Armed, v > high: aboveSince ?= t; if t − aboveSince ≥ hold: disarm, aboveSince = nil; fire iff
   lastFire is nil or t − lastFire ≥ interval (then lastFire = t).
5. Armed, v ≤ high: aboveSince = nil.

## ThresholdTriggerAction

`cue.next`, `cue.previous`, `blackout` (toggle). Same identifiers as MIDI-006.

## ThresholdTriggerBinding

source (`AudioFeatureSource`), action, settings. Bank: at most 8, evaluated in order.

## SceneTriggerEntry (scene `triggers[i]`)

An object kept verbatim. Read: `source` string, `action` string, `high` number, `low` number,
`minimumInterval` number (optional), `hold` number (optional).
