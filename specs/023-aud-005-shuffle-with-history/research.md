# Research: AUD-005 Shuffle with history

## AUD-005-D1: Generator

- **Decision**: SplitMix64 (Steele, Lea and Flood 2014; public domain constants
  `0x9E3779B97F4A7C15`, `0xBF58476D1CE4E5B9`, `0x94D049BB133111EB`). Bounded index: `next() % n`
  (bias below 2^-50 for n ≤ 2^14, documented). Cycle seed: `SplitMix64(seed ^ (cycle &* 0x9E3779B97F4A7C15)).next()`.
  Shuffle: Fisher-Yates from the last index down, `j = bounded(i + 1)`.
- **Rationale**: tiny, fast, fully specified, identical on every platform and Swift version.
- **Alternatives**: `SystemRandomNumberGenerator` (not reproducible); `Array.shuffled(using:)` and
  `Int.random(in:using:)` (the standard library does not promise its algorithm across versions);
  GameplayKit (Apple-only, not on Linux).

## AUD-005-D2: Storage

- **Decision**: optional keys in `queue.json` version 1, written only while Shuffle is on; the seed as
  16 lowercase hex digits. See data-model.md.
- **Rationale**: the AUD-004-D2 pattern: an older app still reads the record; Shuffle Off records stay
  byte-identical to AUD-004's golden bytes.
- **Alternatives**: version 2 (older apps would treat the file as newer and stop storing edits); a JSON
  number for the seed (values above 2^53 lose precision in many readers); a separate file.

## AUD-005-D3: How the queue learns the direction of a move

- **Decision**: `PlaybackMove` (`start`, `next`, `previous`, `endOfTrack`) passed by the transport to
  `MutablePlayOrder.playbackDidMove(to:by:)`; the protocol extension's default forwards to
  `playbackDidMove(to:)`.
- **Rationale**: inferring the direction from the id is ambiguous when the same track sits both before
  and after the cursor in the history (cycles may replay a track).
- **Alternatives**: inference from the id (ambiguous); the queue driving the transport (inverts the
  AUD-003 design where edits never call transport commands).

## AUD-005-D4: History model

- **Decision**: a list of identifiers (≤ 100) with a cursor at the current track. Previous: the entry
  before the cursor that is still queued (entries no longer queued are dropped at removal). Next with
  entries after the cursor: the next entry. `start` and new Next/end-of-track moves truncate the
  entries after the cursor and append. The played part of a cycle (`order[0..<played]`) is kept in play
  order (each newly played track moves to position `played`), so after a relaunch the history is
  `order[0..<played]` (last 100).
- **Rationale**: matches the browser-style "back and forward" users know from music players, and is
  reproducible from a seed and a script of commands.

## AUD-005-D5: Avoiding an immediate repeat across cycles

- **Decision**: the next cycle is generated from `cycleSeed(seed, cycle + 1)` over the queue in queue
  order; when its first entry is the track that just played and there are two or more, it swaps with the
  last entry.
- **Alternatives**: regenerate until different (unbounded loop, harder to document); rotate (changes
  every position).

## AUD-005-D6: Import position

- **Decision**: a newly imported track goes to `played + h % (unplayed + 1)` where
  `h = SplitMix64(seed ^ fnv1a64(id)).next()`, so the position does not depend on launch order or on
  Swift's randomized `Hasher`.
