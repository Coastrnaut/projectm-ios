# Contract: Text layer (`TextLayer` target)

## Spec and cleaning (every host)

- `TextSanitizer.clean(_ raw: String) -> (message: String, wasCut: Bool)`: CR LF / CR / U+2028 /
  U+2029 → LF; tab → space; every other `Cc` scalar removed; `Cf` kept; then at most
  `TextSanitizer.maximumCharacters` (280) `Character`s and `maximumLines` (8) lines (later line
  breaks become spaces). `wasCut` is true when characters were dropped by the limit.
- `TextOverlaySpec` — see data-model; `encodedForStorage() -> Data` (sorted keys, `"version": 1`),
  `static decodeStored(_:) -> TextOverlayDecodeResult`.
- `TextDirection.of(_:)`, `TextAlignmentChoice.side(for:)`.

## Rasterizer (CoreText hosts)

- `TextRasterizer.render(_ spec: TextOverlaySpec, pictureWidth: Int, pictureHeight: Int) -> TextRendering?`
  — nil when the message is empty or a size is < 1. Pure function of its inputs: equal inputs give
  byte-identical `pixels` (MED-009-R8). The rendering lies inside the picture. Thread-safe to call
  from one thread at a time per call (no shared state).

## Layer source (Metal hosts)

- `TextLayerSource(device:)`: `layerName` "text", fallback `.transparent`.
- `spec: TextOverlaySpec` — settable any time on the compositor's thread (R17); a change starts one
  rasterization on the layer's serial queue at the last prepared picture size; a newer change wins
  (generation counter); the previous texture is shown until the new one is ready, an empty message
  drops it at once.
- `prepare(picture:device:)` — remembers the size; a new size starts a rasterization.
- `render(into:commandBuffer:frame:audio:)` — takes the newest texture only if the slot's lock is
  free this instant; throws `.notReady` without a texture; otherwise a clear pass on `picture` and one
  blit of the texture to (x, y). No allocation beyond Metal's encoder objects, no lock wait, no I/O,
  no text drawing.
- `state: TextLayerState`, `onStateChange` (main actor), `waitUntilRendered()` (tests),
  `lastRendering` (tests, DEBUG diagnostics: the CPU rendering behind the current texture).
