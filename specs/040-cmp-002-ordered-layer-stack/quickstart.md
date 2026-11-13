# Quickstart: validating CMP-002

From the repository (or worktree) root on the Mac.

1. Host package tests (stack rules, acceptance, apply semantics):
   `swift test --package-path Packages/Compositor` — all pass; `LayerStackTests` and
   `LayerStackApplyTests` included (GPU tests skip without a Metal device).
2. Linux shape (stack rules without Metal):
   `swift test --package-path Packages/Compositor --scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`
   — `LayerStackTests` run and pass.
3. Simulator: from `Packages/Compositor`,
   `xcodebuild test -scheme Compositor -destination id=<udid> -test-timeouts-enabled YES -default-test-execution-time-allowance 180`.
4. App: `xcodegen generate`, then `xcodebuild test` of `projectM-iOS` with
   `-only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/CameraUITests -only-testing:projectM-iOSUITests/CameraPrivacyStatusUITests`
   — the Camera visual behaves as before.
5. Docs: `python3 scripts/validate_docs.py` and `python3 scripts/check_compliance.py` print OK.

Expected acceptance result (CMP-002-S1): `testReorderingRedAndBlueChangesTopmostColor` reads blue,
then red after the move, within 1/255 on every pixel.

Device (CMP-002-T15 `{device}`, open): per-layer frame cost of a 4-layer stack on D1-D3.
