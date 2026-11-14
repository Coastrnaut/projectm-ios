# Quickstart: SCN-011 validation

1. `swift test --package-path Packages/ShowControl --filter SceneTemplate` — bundled templates decode with no warnings, licence records complete, copies independent (contract T1, T2, T4).
2. App unit tests `SceneTemplateAcceptanceTests` on simulator "SCN11 iPhone 17": instantiate twice → two IDs and files; edit copy 1 → copy 2 and the bundle file byte-identical; delete copy 1 → copy 2 loads; every template validates against the app registry (T3).
3. UI test `SceneTemplateUITests`: Settings → Show → Add from Template… → Pulse Rings → cue appears (under 30 s; T5).
