# QA-011 device run D1 20261123T190422Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `546078782589680076fe5985ac038c882c9c94bb`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-23T19:04:22Z, finished 2026-11-23T19:40:08Z
- Summary: pass 19, fail 3
- Record SHA-256: `a43656b9928dde75469665cf24a4f6aa8c8aa29088fea0c06513a095c722ca0c`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 80.9 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-23T190658Z.json |
| `launches-sc015` | pass | 74.2 | QA-010-T12 | 11 launches recorded |
| `warmstart-perf009` | pass | 141.0 | PERF-009-T16 | cold 10 launches, library ready 246.1 ms; warm 11, 176.4 ms |
| `autorun-perf001-glow` | pass | 76.0 | part of PERF-003-T15 | report automation-perf001-2026-11-23T191150Z.json |
| `autorun-pre005` | pass | 132.0 | part of PRE-005-T17 | report automation-pre005-2026-11-23T191402Z.json |
| `rendererlab-flashcost` | fail | 210.0 | part of FX-019-T22 | 28 presets, median 1.86 ms, max 3.03 ms per frame (limit 2.0 ms); over: frontend-uwp/EoS - dark side of the moon (plus a few more hits and a pill).milk, frontend-uwp/EoS+Phat - Arm_upgrades - transformer.milk, frontend-uwp/fiShbRaiN - toffee cream and icing sugar.milk, frontend-uwp/Fvese - Snowflake |
| `xctrace-perf004` | fail | 239.2 | PERF-004-T16 | no PERF-004 texture allocation signposts: the visual used no pooled texture (choose one with effects: PROJECTM_VISUAL) |
| `xctrace-perf011` | fail | 308.8 | part of PERF-011-T21 | failed: no frames while away; 1 frames away, footprint 179.7 -> 161.4 MB, first frame 0.024425983428955078 s after the return |
| `autorun-perf012` | pass | 91.3 | part of QA-010-T12 | report performance-perf012-2026-11-23T192811Z.json |
| `thresholds` | pass | 0.0 | QA-010-T12 | QA-010 overall pass |
| `xctest-goldens` | pass | 93.7 | QA-003-T17 | 134 tests, 0 failures, 3 skipped; 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: s |
| `xctest-soak-600` | pass | 117.6 | QA-006-T13 | 1 tests, 0 failures, 0 skipped; QA-006 qa006-scene-soak-600s [iOS, deviceAllocatedSize]: pass; cycles measured 190; slope 0 B/cycle (limit 65536); high-water 2375680 (warm-up 2375680, bound 44 / QA-006 qa006-scene-soak-600s cycle 0: high-water 2277376, end 2260992, pool live 786432, misses 8, footpr |
| `xctest-materials` | pass | 13.6 | SHD-004-T20 | 5 tests, 0 failures, 0 skipped |
| `xctest-angle-layer` | pass | 10.9 | part of CMP-001-T20 | 9 tests, 0 failures, 0 skipped |
| `xctest-pre012-limits` | pass | 16.9 | part of PRE-012-T31 | 2 tests, 0 failures, 0 skipped |
| `bench-shd002` | pass | 185.8 | SHD-002-T24 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261123T190422Z/xcresult/bench-shd002.xcresult / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /    |
| `bench-rec003-encoder` | pass | 143.4 | part of REC-003-T23 | 3 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261123T190422Z/xcresult/bench-rec003-encoder.xcresult / Build/qa-011/D1/20261123T190422Z/xcresult/bench-rec003-encoder.xcresult |
| `bench-cmp008` | pass | 16.1 | CMP-008-T19 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261123T190422Z/xcresult/bench-cmp008.xcresult / CMP-008 GPU time per frame, 1920 × 1080 (ms): / case / median / p95 / / CMP-008 |
| `bench-cmp009` | pass | 13.2 | CMP-009-T19 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261123T190422Z/xcresult/bench-cmp009.xcresult / CMP-009 GPU time per frame, 1920 × 1080 (ms): / case / median / p95 / / CMP-009 |
| `bench-cmp010` | pass | 14.0 | CMP-010-T19 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261123T190422Z/xcresult/bench-cmp010.xcresult / CMP-010 GPU time per frame, 1920 × 1080 (ms): / case / median / p95 / / CMP-010 |
| `bench-expression` | pass | 10.7 | SHD-010-T13 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261123T190422Z/xcresult/bench-expression.xcresult / SHD-010 bench add: 16 formulas, cost 2032/frame, 3320 ns/frame, 1.63 ns/uni |
| `xctest-offline-export` | pass | 65.2 | REC-013-T14 | 4 tests, 0 failures, 0 skipped |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/automation-perf001-2026-11-23T190658Z.json` | 3202 | `9a7d2473aa689b90959389077b0e499e226fbe83131b2f49128b7aea312d432d` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/sc015.json` | 219 | `eddce9c29ebfb2459ac1b31c70c424e664f20a7aba4942de85ad926969137a37` | yes |
| `warmstart-perf009` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/perf009.json` | 3485 | `2a8f9ea05f2c6582c9471d48656637f60f97d4f2973fb3e98715f2e82692a473` | yes |
| `warmstart-perf009` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/perf009-summary.json` | 343 | `480a75ff7776c4fb8ab1b486327e399de10f16ecd82727b4a965c2d6a19b1e56` | yes |
| `autorun-perf001-glow` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/automation-perf001-2026-11-23T191150Z.json` | 3290 | `4e497632598a4a87e6b0cfb2b4424fd2c65a507e351f0f13956a1d95d4394706` | yes |
| `autorun-pre005` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/automation-pre005-2026-11-23T191402Z.json` | 22237 | `ee3cc25933369a66384f6ddf51c4df000eed33f4e4dd368104e74f6a299a3494` | yes |
| `rendererlab-flashcost` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/RendererLab-angle-flashcost-2026-11-23T191458Z.json` | 40300 | `cc51a875d3c90a3c57dff8921784941578fb2bbbf071cead83d821f34f19c90e` | yes |
| `xctrace-perf004` | `Build/qa-011/D1/20261123T190422Z/logs/xctrace-perf004-perf004.log` | 260 | `961302523de875e89f55e50cdea8e2aab389c6ba960a082aa88090834775fa52` | no |
| `xctrace-perf004` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/xctrace-perf004-automation-perf004-2026-11-23T191813Z.json` | 388 | `ab5173c0d18ef88c9132a4ff190898af0685dbd950f8e7d131382c202029faaf` | yes |
| `xctrace-perf004` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/xctrace-perf004-verdict.json` | 304 | `25c8af9ad2492f3f779d3a546384ea9ed9f89295ef1b94b736ad843e2830a2ee` | yes |
| `xctrace-perf011` | `Build/qa-011/D1/20261123T190422Z/logs/xctrace-perf011-perf011.log` | 309 | `cce8cf5a287a36d557c8d58134df862da3161caf6c836164fd67b7072d7082ee` | no |
| `xctrace-perf011` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/xctrace-perf011-automation-perf011-2026-11-23T192243Z.json` | 6600 | `d8d0eb13ef46fec3679770cbcfdb52c291e2379ea6d49e81b6500ebc09200386` | yes |
| `xctrace-perf011` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/xctrace-perf011-verdict.json` | 592 | `be6401041dc3247c6aa4e20ea86d3242298e6b46f5dc2e7103e48cd4d27166c7` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/performance-perf012-2026-11-23T192811Z.json` | 2515 | `5f434e7ae295cee794a28abca6661d169d2870a373d9ddea23fbeb52c9dca6bc` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/performance-verdict.json` | 1761 | `e1de40c4ec5efb10482730db44ab15e3d5dbcfc791c87fea3e5bda99b0e57970` | yes |
| `xctest-goldens` | `Build/qa-011/D1/20261123T190422Z/logs/xctest-goldens.log` | 3697383 | `9f324a3ff39e599bddce38b77ad7ac9f3d59a97b852a2613d05f4e8e1551dd79` | no |
| `xctest-goldens` | `Build/qa-011/D1/20261123T190422Z/xcresult/xctest-goldens.xcresult` | 578269 | `9720d0bed13960a26b3076eefab821bf72211966f7bdf1e5b2d304c2f8853f02` | no |
| `xctest-goldens` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/xctest-goldens-313B06B5-1101-4D82-838B-9B127CD69D7F.json` | 24614 | `ef297b1db0aa978d0aab255b49ef29398a4c84399bb2bc3cab4821746e765bc1` | yes |
| `xctest-goldens` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/xctest-goldens-851C2A84-D908-447F-902D-DAB8029CE37B.json` | 5516 | `efb5420319a4fce83c719a76233f915624aff901692dd70a33f31c7d9b32b859` | yes |
| `xctest-goldens` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/xctest-goldens-BBC59051-40D4-4142-9130-B235D0604E29.json` | 6407 | `f5abcbce80fa90f0da359bcf06fae998addd688520446d869c77f1b41b825606` | yes |
| `xctest-soak-600` | `Build/qa-011/D1/20261123T190422Z/logs/xctest-soak-600.log` | 477596 | `46ede0ff2217fb51cc9b3d934b27268eda81228f89370bcb8b904bb054c44cbf` | no |
| `xctest-soak-600` | `Build/qa-011/D1/20261123T190422Z/xcresult/xctest-soak-600.xcresult` | 65330 | `fc26b38add2ef0b7ea5557585090a315ffa0eb5508684966cd115fc53a52184d` | no |
| `xctest-soak-600` | `docs/test-reports/qa-011/runs/D1/20261123T190422Z/artifacts/xctest-soak-600-DAF37DF4-89D6-43A7-9688-3264C9DFBB03.json` | 235223 | `3c51ff5fc98b8e4aa84d6694040c54851f46829dfbd448c7de8f6079a03c060b` | yes |
| `xctest-materials` | `Build/qa-011/D1/20261123T190422Z/logs/xctest-materials.log` | 260908 | `55fa7e5b1ba20ad515cd874ecfd8e213ea120ad1ce7599f5ab87f6e2506b9fdf` | no |
| `xctest-materials` | `Build/qa-011/D1/20261123T190422Z/xcresult/xctest-materials.xcresult` | 43855 | `42ee1ee2eb45d29a79c6be265146ecccea6a70e85f450dcca1df907db794d5b7` | no |
| `xctest-angle-layer` | `Build/qa-011/D1/20261123T190422Z/logs/xctest-angle-layer.log` | 210213 | `182a10371cc5b8078d2704261d7999799e76094ccf385e244462c983ca9a7e57` | no |
| `xctest-angle-layer` | `Build/qa-011/D1/20261123T190422Z/xcresult/xctest-angle-layer.xcresult` | 45552 | `2c2b010362160d4f7e8556a5fef1e4131a3d49e1c124137080524fdacf956a34` | no |
| `xctest-pre012-limits` | `Build/qa-011/D1/20261123T190422Z/logs/xctest-pre012-limits.log` | 209603 | `a2ee77ff45c237088ba2f00332a4477292b7400e1f1feae10eff5f29a23976de` | no |
| `xctest-pre012-limits` | `Build/qa-011/D1/20261123T190422Z/xcresult/xctest-pre012-limits.xcresult` | 38287 | `114f33ee788bb9c935d5987ccb7a0fee0c1d1892d82eb2f1b096c77a151ca60e` | no |
| `bench-shd002` | `Build/qa-011/D1/20261123T190422Z/logs/bench-shd002.log` | 3846961 | `87d4031403fe02a2f98ef5589a14f560456f866785ae1ac4ab24db2e0944536f` | no |
| `bench-shd002` | `Build/qa-011/D1/20261123T190422Z/xcresult/bench-shd002.xcresult` | 302261 | `e86d0cc35c94313c6898d16abbfaca75ee1e5df51d2cd4a756a5f2f341f591f0` | no |
| `bench-rec003-encoder` | `Build/qa-011/D1/20261123T190422Z/logs/bench-rec003-encoder.log` | 442283 | `a455482ac6ddcdfa58bee0db3242deb41ba7172dd5dbec6ce3b19371fa53361a` | no |
| `bench-rec003-encoder` | `Build/qa-011/D1/20261123T190422Z/xcresult/bench-rec003-encoder.xcresult` | 54871 | `ed8304d14dafcb1dbf2a6c45fa33a189fcb42174cdedd1613a91e81c5aa2ad7a` | no |
| `bench-cmp008` | `Build/qa-011/D1/20261123T190422Z/logs/bench-cmp008.log` | 236170 | `b5c93ebb1b5399afc85b2ba716f07bec3d4e5edc26d22fd664b6ed132c1ad961` | no |
| `bench-cmp008` | `Build/qa-011/D1/20261123T190422Z/xcresult/bench-cmp008.xcresult` | 39848 | `2d0aa7a2b5a754d6e3e816e2bd2e7f4fe1ab2a3aec26d57b308016f82a268319` | no |
| `bench-cmp009` | `Build/qa-011/D1/20261123T190422Z/logs/bench-cmp009.log` | 237877 | `9e26ec2a750a839e16ee4bac9c6962bd94ae8c5cd4f08716dbd7d06f89591f15` | no |
| `bench-cmp009` | `Build/qa-011/D1/20261123T190422Z/xcresult/bench-cmp009.xcresult` | 39603 | `b1c16fac9eafa3144bfe873cea21479766e3cd6a895c83894074dbcb1a682849` | no |
| `bench-cmp010` | `Build/qa-011/D1/20261123T190422Z/logs/bench-cmp010.log` | 245842 | `8e1e8fb24ff09039499b818ed960d7eac5a667c3dad23212b882f1a8691bc68b` | no |
| `bench-cmp010` | `Build/qa-011/D1/20261123T190422Z/xcresult/bench-cmp010.xcresult` | 39886 | `18d94013c5cd4b859f4e44d3adbff852d1db933e13aaf29a601d03885b69ca76` | no |
| `bench-expression` | `Build/qa-011/D1/20261123T190422Z/logs/bench-expression.log` | 239651 | `dcd25a321a429e7b974342b26a725d035ab6b0badf71035dac65eec989f90651` | no |
| `bench-expression` | `Build/qa-011/D1/20261123T190422Z/xcresult/bench-expression.xcresult` | 39905 | `9bac77c1ee3a6f8e4215ae3fabe6f86f3d6b565168bbea6e0b406513862ffa89` | no |
| `xctest-offline-export` | `Build/qa-011/D1/20261123T190422Z/logs/xctest-offline-export.log` | 2871343 | `fbc65279901ff8b457370563144cd8ba730ecbe30da06da31fa83a497625db2a` | no |
| `xctest-offline-export` | `Build/qa-011/D1/20261123T190422Z/xcresult/xctest-offline-export.xcresult` | 370700 | `6aa77a01d45ef3c2d342351b391d4551ded9359059acf743a0376f1e05a6950c` | no |
