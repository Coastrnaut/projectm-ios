# Test report: PRE-015 User preset duplication

Spec: `specs/010-pre-015-user-preset-duplication/`. Branch `feature/pre-015`, Mac Studio,
Xcode 27.2, iOS 27.2 simulator "iPhone 18 Pro". 2026-11-12. Simulator results are not device
evidence (Constitution X).

## Acceptance ("Editing clone leaves bundled hash unchanged")

`UserPresetDuplicationAppTests.testEveryIncludedPresetDuplicatesAndEditsWithoutChangingTheBundle`
reads the app's own 28 Included files and its generated `PresetIndex.json` at run time. For each
preset: the bundled file's git blob hash equals the index hash; the preset is duplicated through
`UserPresetsCoordinator.duplicate`; the copy is edited and saved through `saveEdit` (a line
appended); the bundled bytes and hash are compared again after the duplicate and after the edit.
Result: **28 of 28 duplicated and edited; every bundled file and hash unchanged**; each copy's
stored file changed to the saved text; the bundled preset still loads from its bundle file (not
from a copy); favorites and collections naming the bundled id still resolve to it.

Finding: two Included files are byte-identical ("UWP" and "Stahlregen & fiSHbRaiN + flexi +
Geiss + shifter - Stonecraft (Beetle Relief mix)"). An edit that made one copy's text equal the
other copy's text is correctly refused ("the same as … which is already in My Presets").

## Store layer (host)

`swift test --package-path Packages/PresetLibrary`: 166 tests, 0 failures, 1 skipped (the
PRE-012 corpus test; the packs are not checked out in a feature worktree). Run twice. New suites:

- `UserPresetsMigrationTests` (7): v1 golden → v2 (only the version changes), v2 golden, origin
  consistency, backup kept until the migrated file is saved, version 3 left untouched.
- `UserPresetStoreGuardTests` (4): every create, write, move, copy and delete of add, update,
  replace, remove, trial records and migration is inside the store directory; a path outside
  (including `..` tricks) is refused and not touched; a symlinked store directory works.
- `UserPresetDuplicationTests` (11): byte-identical copy into a read-only "bundle" fixture whose
  bytes, hash and modification date stay unchanged; refusals store nothing; repeat and numbering;
  limits; the purchase boundary and refund hold.
- `UserPresetEditingTests` (11): saved edit replaces the text (content-addressed, old text
  deleted); every refusal and failing check leaves every stored byte identical and the old text
  playable; record-save failure removes the new text; an app that ends during an edit's check
  keeps the last good version (not quarantined) and reports it once; Latin-1 decoding.

## App (simulator)

All app unit tests: 106 run, 1 failure, the known environmental
`PresetTests.testBundledIncludedScopeMatchesRelease1_0` (needs the full library). UI tests:
`UserPresetEditingUITests` (4: duplicate from a row, failing save with the reason shown, Keep
Editing, valid save through the real off-screen engine, Discard Changes, duplicate the current
preset from the controls and the repeat refusal, the editor at Accessibility XXXL with every
control present and hittable), `UserPresetsUITests` (3), `PresetCollectionsUITests` (7),
`VisualizerUITests` (2): 16 tests, 0 failures. Both runs gave the same result. `Rendering-Package` (28 tests) and
`ANGLERendering` (51 tests), not changed by this feature, passed twice as a regression check.
Compliance, docs and 96 script tests pass.

## Not verified

- S7 on D1 (editor opens a 524,288-byte preset in under 2 s) and a VoiceOver pass on a device:
  final device stage (PRE-015-T26).
- The full pack library (12,913 presets) is not checked out in the feature worktree; pack
  copies were tested with a synthetic locked pack and the archive read path is the existing
  `PresetArchive` used for playing.
- Swiping the editor down with unsaved changes is blocked, not asked about (spec R16).
