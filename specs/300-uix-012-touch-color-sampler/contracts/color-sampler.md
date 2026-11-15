# Contract: UIX-012 color sampler

- **C1 `PreviewPixelMapping.pixel(at:)`** (FrameCapture, pure): returns nil for non-finite input, a point outside the split output rect, or (fit) outside the picture rect; otherwise `x = min(floor(u·W), W−1)`, `y = min(floor(v·H), H−1)` with u, v the point's fraction of the picture rect.
- **C2 `CapturedPixels.sampledColor(x:y:)`** (FrameCapture): nil out of bounds; straight linear RGBA in 0…1 per research D4, for all three layouts (bottom-up rows flipped).
- **C3 `ColorSamplerCoordinator`** (app, main actor):
  - `begin(_ target)` → refusal text or nil (enters sampling); refusals: "Nothing to sample", "The picture is on the external display", "The output is blacked out", "Resume to sample a colour", the scene lock's text.
  - `sample(at:window:placement:)` → requests one frame (ignored while one is in flight); on arrival maps and writes; rejection keeps sampling with "Tap inside the picture"; failure/timeout keeps sampling with "Couldn't read the picture. Try again."
  - Write: `endCoalescing()`, target write, `recordStep(label: "Sample <name>")`; unchanged colour records nothing; announcement "<name> set to red R%, green G%, blue B%" on `.parameter`.
  - `cancel()` ends sampling, cancels the request, records nothing.
- **C4 UI identifiers**: `eyedropper.<key>` (value: the colour in spoken form), `colorSamplingLayer`, `colorSamplingBanner`, `colorSamplingCancel`.
