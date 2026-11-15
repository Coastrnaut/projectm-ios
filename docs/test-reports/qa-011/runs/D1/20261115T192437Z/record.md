# QA-011 device run D1 20261115T192437Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `1a9a1724869813ac82890fa16b434b93ac6ff54b` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T19:24:37Z, finished 2026-11-15T19:27:48Z
- Summary: pass 1, fail 1
- Record SHA-256: `e0701c1345ecf97d39a9f3f37b9615a0eae6d45a7ab92e1c29c14e5e87544eba`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `xctest-goldens` | fail | 88.4 | QA-003-T17 | 1 tests, 0 failures, 3 skipped; exit 65; QA-006 qa006-scene-soak [iOS, deviceAllocatedSize]: pass; cycles measured 10; slope 0 B/cycle (limit 65536); high-water 7880704 (warm-up 7880704, bound 9977856) / QA-006 qa006-scene-soak cycle 0: high-water 7782400, end 7766016, pool live 786432, misses 8, fo |
| `xctest-soak-600` | pass | 101.8 | QA-006-T13 | 1 tests, 0 failures, 0 skipped; QA-006 qa006-scene-soak-600s [iOS, deviceAllocatedSize]: pass; cycles measured 190; slope 0 B/cycle (limit 65536); high-water 2375680 (warm-up 2375680, bound 44 / QA-006 qa006-scene-soak-600s cycle 0: high-water 2277376, end 2260992, pool live 786432, misses 8, footpr |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `xctest-goldens` | `Build/qa-011/D1/20261115T192437Z/logs/xctest-goldens.log` | 3246643 | `2d24b26902db62a15dfe35029481c4ed820051928b3afb0ee150f4cf858903a4` | no |
| `xctest-goldens` | `Build/qa-011/D1/20261115T192437Z/xcresult/xctest-goldens.xcresult` | 532849 | `780a0786c4ffa6670f17ddb1771905b3929ecda798c38de548ec5aae6922c123` | no |
| `xctest-goldens` | `docs/test-reports/qa-011/runs/D1/20261115T192437Z/artifacts/xctest-goldens-02E16130-A5CE-4B58-8FF4-1A898D2D4C1D.json` | 5516 | `4e3d6c4e25a930b0565eaba3590d42de86a48b168f6826da4151734ddd45ca23` | yes |
| `xctest-goldens` | `docs/test-reports/qa-011/runs/D1/20261115T192437Z/artifacts/xctest-goldens-09F7A6A6-B271-431C-B1B3-6565C03F4BD2.json` | 6408 | `6ce6713f95c11fbc93cebda3ef65eb15cc5570b7b57bf7dd6b75313b1802d9d9` | yes |
| `xctest-goldens` | `docs/test-reports/qa-011/runs/D1/20261115T192437Z/artifacts/xctest-goldens-6D55665B-4D83-46A1-AB15-EE56FE2B2A7B.json` | 24613 | `bded25238e3e33449da0f82440b9771ddedba1d276399cb2ec94136dd2260350` | yes |
| `xctest-soak-600` | `Build/qa-011/D1/20261115T192437Z/logs/xctest-soak-600.log` | 297020 | `9d62776a7f215b1f9ba966bc1bda49460bb8c0234bb7e26679aa555256d975a5` | no |
| `xctest-soak-600` | `Build/qa-011/D1/20261115T192437Z/xcresult/xctest-soak-600.xcresult` | 58447 | `ce9763e32ab553477f815d959450da7add7dacdaf8e3df7abdd6bad36b723644` | no |
| `xctest-soak-600` | `docs/test-reports/qa-011/runs/D1/20261115T192437Z/artifacts/xctest-soak-600-9BA66BC4-A210-448A-A0A4-DE062BE08059.json` | 235220 | `64f5e770069adbfca7ebcb78099ca63d68231bb8791286afd1f3be6d675d39b5` | yes |
