# Quickstart: VIS-016 Starfield Flight

```bash
swift test --package-path Packages/VisualGenerators --filter Starfield
swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter Starfield
swift test --package-path Packages/RenderGoldens --filter Starfield
```

Expected: 5000 requested gives exactly 2000 active; reset restores the initial positions bit for bit; 60 Hz and
jittery frame times agree; the golden matches.

App: Settings → Visual → Starfield; Speed picker and Stars stepper. Device (`{device}`): D1 with music, the
PERF-001/007 overlay holds the display's frame rate at 2000 stars, Fast.
