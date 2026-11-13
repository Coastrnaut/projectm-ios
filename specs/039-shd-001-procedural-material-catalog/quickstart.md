# Quickstart: SHD-001 Procedural Material Catalog

## Prerequisites

The Mac Studio (Xcode 27.2, iOS 27.2 simulator runtime). No submodules are needed for the package.

## Host (CPU and GPU tests)

```bash
swift test --package-path Packages/Compositor --filter ProceduralMaterialsTests
```

Expected: every test passes; GPU tests run on the Mac's GPU (they skip only without a Metal
device). The suite takes well under a minute.

## Linux shape (CPU only)

```bash
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL \
  -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter ProceduralMaterialsTests
```

Expected: catalog, values, motion and source-safety tests pass; GPU files compile out.

## Simulator

```bash
cd Packages/Compositor
xcodebuild test -scheme Compositor -destination id=<udid> CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180
```

## Scenarios

1. **Loads at documented defaults** (S1): `MaterialRenderTests.testEveryMaterialLoadsAtDefaults`.
2. **Descriptors valid** (S2): `MaterialCatalogTests.testRegistryValidates`.
3. **No external code** (S3): `MaterialSourceSafetyTests`.
4. **Deterministic** (S4): `MaterialRenderTests.testRendersAreDeterministic`.
5. **No flashing at defaults** (S5): `MaterialFlashSafetyTests.testDefaultsStayInsideReduceFlashingEnvelope`.
6. **Extremes** (S6): `MaterialRenderTests.testExtremesStayValid`,
   `MaterialFlashSafetyTests.testExtremesWithFullMusicStayInsideAlwaysOnBudget`.
7. **Golden** (S7): `MaterialRenderTests.testGoldenSignatures`.

## Device (S8, SHD-001-T19 `{device}`)

Per-material GPU frame cost on D1-D3 at full screen: open; not run by this row.
