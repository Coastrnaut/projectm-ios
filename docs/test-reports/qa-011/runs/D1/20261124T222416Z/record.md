# QA-011 device run D1 20261124T222416Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state disconnected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `634ce4dab3246e054ed0317e03be8a11d1a88f53`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-24T22:24:16Z, finished 2026-11-24T22:31:28Z
- Summary: fail 1
- Record SHA-256: `3ab1cf685a64d748fa7867ff6e28fb9ccd3dc87eeb992c533d78f0871e2422d9`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `rendererlab-flashcost` | fail | 330.2 | part of FX-019-T22 | 28 presets, pass (GPU timer + CPU encoding) median 8.11 ms, max 9.98 ms per frame (limit 2.0 ms; medians GPU 7.73, CPU 0.35, excluded round trip 0.86 ms); on - off of separate frames median 1.63, max 4.54 ms; over: frontend-uwp/EoS - dark side of the moon (plus a few more hits and a pill).milk (pass |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `rendererlab-flashcost` | `docs/test-reports/qa-011/runs/D1/20261124T222416Z/artifacts/RendererLab-angle-flashcost-2026-11-24T222612Z.json` | 58438 | `38c577c52ab664db4ceed7fcf2b1aecfa5e5eef8586d93dcc47eb3104db2a542` | yes |
