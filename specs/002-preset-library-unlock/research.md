# Research: Full Preset Library Unlock (feature 002)

Numbering starts at R-21 so it never collides with feature 001's R-01 to R-16.

## R-21 Preset sources and pinning

- **Decision**: Five git submodules of the projectM team's repositories, pinned to the commits
  scanned on 2026-11-10, shallow, under `Vendor/presets/`: cream-of-the-crop `0180df21f5e0`,
  projectm-classic `14a6244a7d32`, milkdrop-original `e03b83e3338d`, en-d `fff71ea81223`,
  milkdrop-texture-pack `6368812f27bc`. Pins move only with an ADR-0004 update.
- **Rationale**: Constitution IX (exact pins); the owner asked for submodules, not copies; upstream
  repositories need no patches, so forks would add upkeep only.
- **Alternatives considered**: forks under the owner's account (no benefit until a patch is
  needed); copying files (rejected by the owner); downloading packs at run time (violates FR-101
  and feature 001 FR-068, and App Review guideline 2.5.2 for interpreted content).

## R-22 Index format and de-duplication

- **Decision**: `scripts/build_preset_index.py` walks the Included folder and the four packs,
  computes each file's git blob hash (`git hash-object`, the same identity used in the scan),
  keeps the first occurrence in priority order Included → cream-of-the-crop → projectm-classic →
  milkdrop-original → en-d, skips non-`.milk` files, blocklisted hashes and load-sweep exclusions,
  and writes `PresetIndex.json` (one compact record per preset) and `PresetPacks.json` (per pack:
  title, source URL, commit, license statement, author count, preset count). Output is committed;
  `--check` regenerates in memory and fails on any difference (CI docs job; submodules are fetched
  there).
- **Rationale**: decoding one 2 MB JSON file is far cheaper than enumerating 13,000 files and
  parsing a 13,000-row Markdown table at launch; committing the output keeps builds reproducible
  without running Python in Xcode.
- **Alternatives considered**: SQLite with FTS (heavier, unnecessary at 13,000 entries: an
  in-memory substring scan is well under 50 ms); a Run Script build phase (makes every build depend
  on Python and the submodules' state).

## R-23 Identity of presets

- **Decision**: a preset's `id` is `<source>/<path inside the source>`, where the Included source
  keeps today's form (`frontend-uwp/<file>.milk`), so favorites and `lastPresetID` survive
  (FR-104). Pack presets use `<pack>/<relative path>`. The content hash is stored but is not the
  id (ids stay readable in favorites and logs).
- **Alternatives considered**: hash as id (breaks the 1.0 favorites unless mapped; unreadable).

## R-24 Purchase and entitlement (StoreKit 2)

- **Decision**: one non-consumable product, `org.projectmios.ProjectMiOS.fullLibrary`, price tier
  $1.99. `LibraryStore` loads `Product.products(for:)`, checks
  `Transaction.currentEntitlements` at launch and listens to `Transaction.updates` for the app's
  lifetime; `isUnlocked` is true only for a verified, unrevoked transaction of that product.
  `AppStore.sync()` backs Restore Purchases. No unlock flag is stored (FR-110); StoreKit caches
  entitlements on the device, so the unlock works offline (FR-107).
- **Testing**: a StoreKit configuration file (`ProjectMiOS.storekit`) for local runs and
  `SKTestSession` in tests (purchase, failure, Ask to Buy, refund).
- **Alternatives considered**: original StoreKit (deprecated patterns); receipt validation on a
  server (violates FR-122).

## R-25 Textures

- **Decision**: add `-[PMBridge setTextureSearchPaths:]` calling the documented
  `projectm_set_texture_search_paths`, and pass the bundled texture pack folder (and the pack root
  folders, which some presets use for co-located textures) when the engine is created.
- **Rationale**: Constitution VIII (documented API only); presets name textures by file name.

## R-26 Browser structure and performance

- **Decision**: SwiftUI `NavigationStack` with `List` per folder; rows are plain value types from the
  index (no file access while scrolling). All A-Z uses sections by first letter with a section
  index. Search filters the in-memory index with a precomputed folded (case- and diacritic-free)
  key per preset, debounced 150 ms, grouped by pack, capped at 200.
- **Rationale**: `List` is lazy; the largest folder (tryptonaut, 1,228) and All (12,943) are
  long but light; precomputed keys keep search linear and cheap.

## R-27 Scopes and persistence

- **Decision**: `PresetScope` is an enum (included, pack, folder path, favorites, search(query),
  all). Persist `settings.presetScope` as a short string (`pack:cream-of-the-crop`,
  `folder:cream-of-the-crop/Fractal/Nested Spiral`, `favorites`, `all`, `included`); a search
  scope is stored as `all` (spec Clarifications).
- **Alternatives considered**: storing the scope's preset list (stale after updates; more data
  than FR-123 allows).

## R-28 Detecting broken presets before release

- **Decision**: RendererLab gains `RL_MODE=loadsweep` with `RL_SHARD=i/n`: it loads each indexed
  preset into the engine (no 2 s render) on the simulator and writes the ids that fail;
  `build_preset_index.py --exclusions <file>` folds them into the index. Run at every pin change.
  Feature 001 FR-045 still handles failures at run time (excluded for the session, FR-118).

## R-29 License basis for selling access

- **Decision** (spec Clarifications, decided under the owner's standing approval): the purchase
  sells access to the app's full bundled library under the projectM team's redistribution basis
  for these packs; an author-request blocklist is honored every release; packs without a license
  file are treated the same way and the risk is recorded; ADR-0007 holds the decision and the
  review of each pack. ADR-0005 (LGPL, App Store) is unaffected: presets are data, not engine code.
- **Alternatives considered**: keep the full library free (no revenue, simplest); sell only
  explicitly licensed presets (almost none exist); per-pack purchases (more store products and UI
  for little benefit).
