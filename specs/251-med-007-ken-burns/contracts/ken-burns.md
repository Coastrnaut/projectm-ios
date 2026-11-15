# Contract: MED-007 Ken Burns

## K1 Model (`Compositor`, plain Swift)

- `KenBurnsMotion.crop(elapsedNanoseconds: 0, …)` returns `start` bit for bit; any `elapsed ≥ duration` returns
  `end` bit for bit; between, each of x, y, width, height is `a + (b − a) · easing.shaped(u)`, `u = elapsed / duration`.
- For any motion, each edge is monotonic in elapsed time; every returned rectangle is valid.
- `KenBurnsRect.clamped` always returns a valid rectangle; `init?(validating:)` returns nil for invalid input.

## K2 Photo layer (`ImageLayer`)

- With `kenBurns` set, the first drawn frame of a picture samples exactly the start rectangle, fitted with the
  layer's fit (pixel-accurate read as fit); the frame whose elapsed time reaches the duration samples the end
  rectangle; outside the crop (fit bars) is transparent.
- `reduceMotion`: every frame samples the start rectangle.
- `renderDependencies`: `time` while moving; still otherwise, its parameter generation changing with the fit, the
  movement or Reduce Motion.
- A new picture or a new movement restarts at the start rectangle; equal re-assignments change nothing.

## K3 Scene field (`SceneFormat`)

```json
"kenBurns": {"start": {"x": 0, "y": 0, "width": 1, "height": 1},
             "end": {"x": 0.1667, "y": 0.1667, "width": 0.6667, "height": 0.6667},
             "durationMilliseconds": 10000, "easing": "easeInOut"}
```

On a `photo` asset only; optional; no version change; malformed → absent.

## K4 App

- `settings.photo.kenBurns`: the same JSON; absent = off.
- Restoring a document with a photo layer sets the movement (absent → off); other documents leave it.
- While the slideshow is active, the layer's duration is the slide's dwell.
