# Quickstart: VIS-003 Waveform Oscilloscope

```bash
swift test --package-path Packages/VisualGenerators --filter 'Waveform|Oscilloscope'
swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
swift test --package-path Packages/RenderGoldens --filter Oscilloscope
# Re-record the golden on purpose (review the PNG first):
GOLDEN_RECORD=1 swift test --package-path Packages/RenderGoldens --filter OscilloscopeGoldenTests
```

App: Settings → Visual → Oscilloscope; Line and Window appear; Glow applies. UI test:
`-only-testing:projectM-iOSUITests/OscilloscopeUITests`.

Device (`{device}`, final phase): on D1 with Instruments (Allocations + Metal System Trace), 60 s of
the reference track with the oscilloscope: no allocation growth in the frame loop, frame time within
the VIS-001 budget.
