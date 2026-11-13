# Data Model: PERF-006 Memory Warning Recovery

Nothing is stored. All values live in memory for the session.

## MemoryPressureLevel

`warning` | `critical`. The system warning maps to `warning`; `critical` comes from tests and the DEBUG
probe (research PERF-006-D1).

## MemoryPressureTier

`cache` (run on every signal) | `optional` (run on escalation, restored after the cool-down).

## MemoryPressureRelease

| Field | Type | Rule |
|---|---|---|
| bytes | Int ≥ 0 | freed bytes; 0 when nothing was held |
| items | Int ≥ 0 | freed objects (pictures, contexts, hosts, chunks) |
| bytesEstimated | Bool | true when `bytes` is an estimate (research D5) |

## MemoryPressureResponder (protocol, main actor, held weakly)

| Member | Rule |
|---|---|
| `memoryPressureName` | stable, no user content |
| `memoryPressureTier` | fixed for the responder's lifetime |
| `reclaimableBytes` | current estimate of what a release would free (≥ 0) |
| `releaseForMemoryPressure(_ level)` | idempotent; returns what it freed |
| `restoreAfterMemoryPressure()` | optional tier only; safe when not shed |

## MemoryPressureStepResult

`name`, `tier`, `release` (MemoryPressureRelease).

## MemoryPressureReport

| Field | Rule |
|---|---|
| level | the signal handled |
| escalated | true when optional steps ran or were already shed and the cool-down was extended |
| steps | cache steps first (registration order), then optional steps that ran |
| freedBytes | sum of `steps.release.bytes` |
| shedUntil | end of the cool-down (seconds, monotonic) or nil |

## MemoryPressureRecovery state

| State | Meaning | Transitions |
|---|---|---|
| idle | no optional step shed | escalating signal → shedding(until = now + coolDown) |
| shedding(until) | optional steps shed | escalating signal → shedding(now + coolDown); `restoreIfDue(now ≥ until)` → idle (each shed responder restored once) |

Counters: `recoveries`, `escalations`, `restores`, `totalFreedBytes`; `lastSignalTime` decides
repeats (`now − last ≤ repeatWindow`). An optional responder registered while shedding is shed at
once and restored with the others.
