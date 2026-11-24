# QA-011 device run D1 20261124T183541Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `288df54f0f41d310ed60a601ea6421eb25e12ff7`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-24T18:35:41Z, finished 2026-11-24T18:52:06Z
- Summary: fail 2
- Record SHA-256: `8041a46891c76e564dafe67a1a2e8cc79d03fb6e2fd73fd5a7d54a7d2f443a91`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `rendererlab-flashcost` | fail | 273.7 | part of FX-019-T22 | 28 presets, median 1.75 ms, max 4.39 ms per frame (limit 2.0 ms); over: frontend-uwp/Martin N AdamFX Infusion = Phat+Yin+EoS_Mandala Chaser Ft AdamFX n Martin - The Beast Mandala Chaser FX H.milk (2.56 ms, rounds 0.99-5.42, dimmed 100%, IQR off 4.63 on 4.90), frontend-uwp/ORB - Mega Spectrum.milk (3 |
| `xctrace-perf004` | fail | 601.1 | PERF-004-T16 | perf004: first attempt the trace has not changed for 60 s after the app exited; recorded again; xctrace did not end by itself and was stopped (perf004: the trace has not changed for 60 s after the app exited); no os-signpost table exported (trace saved: False) |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `rendererlab-flashcost` | `docs/test-reports/qa-011/runs/D1/20261124T183541Z/artifacts/RendererLab-angle-flashcost-2026-11-24T183732Z.json` | 51415 | `05f46336ce5097ee3c1f7bc73cfa5ff8cd027478425299252b9fb05d10ba6ed8` | yes |
| `xctrace-perf004` | `Build/qa-011/D1/20261124T183541Z/logs/xctrace-perf004-perf004.log` | 349 | `941dd89f8c6d9ebf86b9ce4cac4316db91cbbd5d890156c05e92de05255946e4` | no |
| `xctrace-perf004` | `Build/qa-011/D1/20261124T183541Z/logs/xctrace-perf004-perf004-retry.log` | 349 | `941dd89f8c6d9ebf86b9ce4cac4316db91cbbd5d890156c05e92de05255946e4` | no |
| `xctrace-perf004` | `docs/test-reports/qa-011/runs/D1/20261124T183541Z/artifacts/xctrace-perf004-automation-perf004-2026-11-24T184714Z.json` | 376 | `60b624de44b1368320596ff2cca3c1f8e4fe120d07f63d7a91b1d2a00cf19364` | yes |
| `xctrace-perf004` | `docs/test-reports/qa-011/runs/D1/20261124T183541Z/artifacts/xctrace-perf004-verdict.json` | 296 | `bc716d25c47600d5928c8b85fc99b68a898c266974f95438b9f823abe4a9eb9a` | yes |
