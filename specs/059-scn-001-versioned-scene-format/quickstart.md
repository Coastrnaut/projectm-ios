# Quickstart: SCN-001 Versioned Scene Format

Prerequisites: the Mac Studio toolchain (`python3 scripts/verify_environment.py`). No simulator or
device is needed (no app change).

```bash
cd Packages/SceneFormat
swift test                                    # host: round trip, property, validation, limits, live
swift test --scratch-path .build/linuxshape \
  -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
swift test --package-path ../Compositor --filter LayerStack     # CMP-002 restore amendment
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py   # from the repo root
```

Expected: every test passes; the suite runs in well under a minute (SCN-001-S5).

| Scenario | Test | Expected |
|---|---|---|
| All-kinds fixture round trip (S1) | `SceneRoundTripTests` | bytes identical, documents equal |
| 500 seeded random scenes (S1) | `ScenePropertyTests` | 0 failures, under 1 s |
| Live stack round trip (S2) | `SceneLiveAdapterTests` | equal stack, snapshot, bindings |
| Refusals and issues (S3) | `SceneDecodeErrorTests`, `SceneValidationTests` | exact messages |
| Unknown content (S4) | `SceneForwardCompatibilityTests` | byte-identical |
