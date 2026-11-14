# Contract: Image slideshow (MED-006)

## C1 — `SlideshowSettings` (ImageLayer, every platform)

- `static let maximumSlides = 20`, `secondsRange = 2...60`, `defaultSeconds = 5`,
  `beatChoices = [1, 2, 4, 8, 16]`, `defaultBeats = 4`.
- `init(enabled:slides:mode:seconds:beats:)` sanitizes (dedupe keeping the first, cap 20, clamp
  seconds, unknown beats → 4). `Codable`; `static func decode(_ data: Data?) -> SlideshowSettings`
  (nil or unreadable → `.off`), `var encoded: Data`.
- `var isActive: Bool`.

## C2 — `SlideshowSchedule` (ImageLayer, every platform)

- `init(count: Int)`; `index`, `nextIndex`, `changes`.
- `mutating func tick(now: UInt64, mode: SlideshowMode, seconds: Int, beats: Int,
  grid: SlideshowBeatGrid?, floorNanoseconds: UInt64) -> Int?`
  - First tick only records `now`. A step `now − lastTick` in (0, 1 s] is added to slide time and
    since-change time; otherwise nothing is added (beats in a skipped step are not counted).
  - With fewer than 2 slides: never changes.
  - Time (or Beats with `grid == nil`): change when slide time ≥ seconds × 10⁹ and since-change ≥ floor.
  - Beats with a grid: each grid beat in (lastTick, now] adds one to the count; change when a beat was
    crossed in this step, count ≥ beats and since-change ≥ floor. A nil→grid switch resets the count.
  - A change advances `index` to `nextIndex`, resets slide time, since-change time and the count, and
    increments `changes`.
- `mutating func restart(count: Int, index: Int = 0)`; `mutating func timingChanged()` (resets slide
  time and count, keeps since-change).
- `SlideshowSafetyFloor.nanoseconds(flashesPerSecond:)`.

## C3 — `ImageLayerSource.preload(_:)` (Metal)

- `func preload(_ url: URL)`: decodes on the load queue into the prepared slot (one entry; a newer
  preload replaces it). Never changes `content`, `state` or the drawn picture.
- Setting `content = .file(url)` when the prepared slot holds `url` with a texture: the texture is
  adopted synchronously under the new generation, state `.ready(w, h)`; the next render draws it
  (exactly one render; `renderDependencies` changes exactly once). Otherwise unchanged MED-001
  behaviour. `preparedURL` (tests).

## C4 — App

- `SlideshowStore` (Sendable struct): `key = "settings.photo.slideshow"`; `settings()` (drops IDs
  that no longer resolve and saves the cleaned value); `save(_:)`; `stage(at:) throws(ImageImportError)
  -> UUID` (through `PhotoStore.stage`); `release(_ ids: [UUID])`; `url(for:)`;
  `static func protectedIDs(_ defaults:) -> Set<UUID>` (read by `PhotoStore`).
- `SlideshowCoordinator` (@MainActor @Observable): `settings`, `isImporting`, `notice`, `thumbnails`;
  `setEnabled`, `setMode`, `setSeconds`, `setBeats`, `move(fromOffsets:toOffset:)`, `moveUp(_:)`,
  `moveDown(_:)`, `remove(atOffsets:)`, `clear()`, `photosPicked(_:)`, `filesPicked(_:)`,
  `importNow(at:)` (DEBUG), `restore(_ scene: SceneSlideshowValue?)`, `sceneValue`;
  `tick(now:grid:floorNanoseconds:) -> URL?`, `startURL`, `nextURL`, `shownIndex`, `changes`;
  `onPlaybackChange` (the host content must be re-chosen).
- `PhotoVisualHost.beforeFrame: (() -> Void)?`, `preload(_:)`.
- `AppCoordinator`: the photo host's content is the slideshow's current slide when active, else the
  photo; `slideshowTick()` from `beforeFrame`; grid only for `.manual`/`.stable` with phase.
- DEBUG probe `slideshowProbe` = `"<index> changes=<n>"`; DEBUG seed `-uitestSeedPhoto slideshow5`.

## C5 — Scene field (SceneFormat)

- `SceneSlideshow` (`enabled`, `storeIDs`, `mode`, `seconds`, `beats`) with `init?(json:)` and `json`.
- `SceneAsset.photoSlideshow: SceneSlideshow?` (photo assets only; nil removes; other kinds ignore).
