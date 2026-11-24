# QA-011 device run D1 20261124T191740Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `c01a032ff0a9c437f68e7b4ee5ba8f8eb628f382`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-24T19:17:40Z, finished 2026-11-24T19:29:14Z
- Summary: pass 1, fail 1
- Record SHA-256: `3cd106a3be039ac977cdf8d28ed8efb6710beafbf7058c526f351a03d4e04dad`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `rendererlab-flashcost` | fail | 318.9 | part of FX-019-T22 | 28 presets, pass alone median 2.80 ms, max 3.09 ms per frame (limit 2.0 ms); on - off of separate frames median 1.39, max 4.24 ms; over: frontend-uwp/EoS - dark side of the moon (plus a few more hits and a pill).milk (pass 3.01 ms, on - off 1.93 ms, rounds 1.13-2.62, dimmed 80%, IQR off 0.24 on 0.50 |
| `xctrace-perf004` | pass | 278.0 | PERF-004-T16 | 42 allocations: 14 at start, 28 at size changes; the visual was up 5.1 s after the start marker (perf004: saved 223 s after the app exited) |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `rendererlab-flashcost` | `docs/test-reports/qa-011/runs/D1/20261124T191740Z/artifacts/RendererLab-angle-flashcost-2026-11-24T191925Z.json` | 53766 | `1881475e938d844c771b898481f884e22334cf2b5cc8f486cc56f1461ca16802` | yes |
| `xctrace-perf004` | `Build/qa-011/D1/20261124T191740Z/logs/xctrace-perf004-perf004.log` | 585 | `eccd8aea3b27b15ac32b045d17cf889fd2d27007edab5c2b3a9bafcbee031dc1` | no |
| `xctrace-perf004` | `docs/test-reports/qa-011/runs/D1/20261124T191740Z/artifacts/xctrace-perf004-automation-perf004-2026-11-24T192516Z.json` | 415 | `2f244510f076d5773279dd4ae2189025fd6440e6685edbb013b34935424e47f2` | yes |
| `xctrace-perf004` | `docs/test-reports/qa-011/runs/D1/20261124T191740Z/artifacts/xctrace-perf004-verdict.json` | 431 | `be97376e5a18eed38a06e8bdb60cb580b1e023014b4257ee8b9521e597daae84` | yes |
