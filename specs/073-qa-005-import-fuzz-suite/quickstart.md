# Quickstart: QA-005 Import Fuzz Suite

## Default run (CI budget)

```bash
swift test --package-path Packages/ImportFuzz
```

Expected: every test passes; the whole package takes under 10 s on the Mac host (Debug), each suite
about 2 s or less; each suite prints one line `QA-005 <suite>: inputs=… accepted=… refused=… digest=0x…`.

## Linux shape on the Mac

```bash
swift test --package-path Packages/ImportFuzz -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL \
  -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path Packages/ImportFuzz/.build/linuxshape
```

## Larger run on demand (never in CI)

```bash
FUZZ_ITERATIONS=5000 swift test --package-path Packages/ImportFuzz
FUZZ_SEED=0x1234 FUZZ_ITERATIONS=20000 swift test --package-path Packages/ImportFuzz --filter OSCFuzzTests
```

## Reproducing a failure

A violation names the suite, seed, iteration and strategies. Rerun only that suite with the same
`FUZZ_SEED` (and `FUZZ_ITERATIONS` at least iteration + 1); the input is rebuilt exactly (contract
H1). Save it under `Tests/ImportFuzzTests/Fixtures/Corpus/<format>/repro-<id>.<ext>` and add a
regression test in the parser's own package (QA-005-R9).
