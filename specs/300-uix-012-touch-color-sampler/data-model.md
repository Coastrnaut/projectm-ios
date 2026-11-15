# Data Model: UIX-012 Touch Color Sampler

- **PreviewFit** (`stretch`, `fit`, `fill`).
- **PreviewPixelMapping**: `viewSize` (points, the visual's full size), `splitScale` (> 0, default 1), `splitOrigin` (points, default 0), `fit`, `pictureWidth`/`pictureHeight` (pixels, > 0), `pixelAspect` (> 0, default 1). `pixel(at:)` → `PreviewPixel(x, y)` or nil.
- **SampledColor**: straight linear `red`, `green`, `blue`, `alpha` (Double, 0…1); `sRGB` components; `spoken` text ("red 20%, green 40%, blue 60%").
- **ColorSampleTarget** (app): `name`, `space` (`linear` | `sRGB`), `read() -> (r, g, b)` in its space, `write(r, g, b)` keeping alpha.
- **ColorSamplerCoordinator state**: `idle` → `sampling(target)` → (`reading` while a request is in flight) → `idle`; `message` (banner text); `reopenSettings` flag.
