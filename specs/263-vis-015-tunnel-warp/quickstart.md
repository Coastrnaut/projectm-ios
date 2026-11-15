# Quickstart: VIS-015 Tunnel Warp

```bash
swift test --package-path Packages/VisualGenerators --filter 'Tunnel|Kaleidoscope|NoiseField'
swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter 'Tunnel'
swift test --package-path Packages/RenderGoldens --filter 'Tunnel|Kaleidoscope|NoiseField'
```

Expected: 120 BPM settles at exactly twice the 60 BPM speed; BPM 0 eases to the base speed with no jump; goldens match.

App: Settings → Visual → Tunnel; Pace picker; tap tempo in the controls and watch the rings speed up smoothly; Reset
eases back to the base speed. Device (`{device}`): D1 with music, the PERF-001/007 overlay holds the display's frame
rate and the tunnel follows a tapped tempo.
