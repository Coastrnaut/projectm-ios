# Test report: SHD-008 Vector path editor

Feature: `specs/279-shd-008-vector-path-editor` (branch `feature/shd-008`). Host: the Mac Studio (build machine of
record), Xcode 27.2, Swift 6.4.2, simulator "SHD8 iPhone 17" (iOS 27.2). Simulator results are not device evidence;
no device run was made (SHD-008-T18 stays open).

Roadmap acceptance: "Saved path restores points and rejects self-intersecting invalid mask cases."

| Check | Test | Result |
|---|---|---|
| Self-intersecting paths rejected (bow-tie, 5-point figure-8, vertex touching an edge, collinear overlap, adjacent spike) | `VectorPathTests.testSelfIntersectingFamiliesAreRejected` | pass |
| Convex and concave paths accepted (square, arrow, L, collinear neighbours) | `VectorPathTests.testConvexAndConcavePathsAreAccepted` | pass |
| Minimum area, duplicate (consecutive and wrapping), range, count rules | `VectorPathTests.testAreaDuplicateRangeAndCountRules` | pass |
| JSON round trip exact; invalid list refused | `VectorPathTests.testCodingRestoresEveryPointExactlyAndRefusesAnInvalidList` | pass |
| Uniform samples inside the L, none in the notch (2000) | `VectorPathTests.testSamplesLieInsideAndCoverTheArea` | pass |
| Editing: bow-tie cannot close, closed edits that break the path refused with the last valid path kept | `VectorPathDraftTests` (3) | pass |
| Scene: decode → encode and decode → load → capture → encode keep every point exactly, byte-identical | `ScenePathMaskTests.testSavedPathRestoresEveryPointThroughDecodeLoadCaptureAndEncode` | pass |
| Scene: bow-tie, figure-8, duplicate, out-of-range, 2-point saved paths drop the mask with a `droppedField` naming the reason; the scene opens and the layer is unmasked | `ScenePathMaskTests.testInvalidSavedPathsDropTheMaskWithAWarningAndTheSceneOpens` | pass |
| GPU (host Metal): L path mask, 1631 far-inside pixels equal the unmasked layer, 3855 far-outside pixels exactly 0, coverage 1974.1 px vs polygon 1966.1 px (0.4 %), one masked draw, no extra pass | `LayerPathMaskTests.testPathMaskCoverageMatchesThePolygon` | pass |
| Emitter: seeded 10 s at 60 Hz and jittery frames, 600 attempts = ⌊60 × 10⌋, every particle inside the path, none in the notch, identical reruns | `VectorPathEmitterTests.testTenSecondSeededRunSpawnsEveryParticleInsideThePath` | pass |
| Emitter settings keep the path; a bow-tie stored path reads as the default | `VectorPathEmitterTests.testSettingsKeepThePathAndAnInvalidStoredPathReadsAsTheDefault` | pass |
| App: mask path chosen, edited, mapped to the compositor, one history step; emitter path persists through AppSettings | `VectorPathEditorTests` (2) on SHD8 iPhone 17 | pass |
| UI: bow-tie shows "The path crosses itself." with Close disabled; a triangle closes; the emitter keeps it | `VectorPathEditorUITests.testBowTieIsRefusedAndATriangleCloses` (29.5 s) | pass |

Regression runs: SceneFormat 205 tests (11 s); Compositor `LayerMask*` 17 tests; VisualGenerators `ParticleEmitter*`,
`ParticleFountain*`, `VectorPath*` 34 tests; Linux shape (`-DVISUAL_NO_METAL` subset 18 tests, `COMPOSITOR_NO_METAL`
build with tests); app `SettingsTests` (9), `LibraryBackupAppTests` (5), `ParticleEmitterEditorTests` (4),
`LayerInspectorTests`, `LayerInspectorRenderTests`, `SceneHistoryCoordinatorTests`, `LayerGradientEditTests` (23).
No new UserDefaults keys (the emitter path lives in `settings.particleFountain.emitter`). PosterBoard reports: 32
before, 32 after.
