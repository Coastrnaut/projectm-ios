# Quickstart: PRE-005 Preset Energy Facets

1. Package (host; Linux in CI): `swift test --package-path Packages/PresetLibrary --filter PresetEnergyFacetTests`
   — fixtures static / slow drift / fast noise → Calm / Moderate / Energetic with pinned scores; filter; PNG
   field round trip; index migrations (S1, S2).
2. Engine (simulator "PRE5 iPhone 17"): `PresetThumbnailRunnerTests` — a time-driven preset drawn twice gives
   identical samples and score (S3).
3. App unit (simulator): `PresetEnergyFacetAppTests` (S4).
4. UI (simulator, under 30 s): `PresetEnergyFacetUITests` with `-uitestThumbnailFixture` (S5).
5. Repo checks: compliance, docs, motion policy, permission catalog, status events, script tests; privacy
   manifest and network symbols on the Debug app; `LibraryBackupAppTests`.
