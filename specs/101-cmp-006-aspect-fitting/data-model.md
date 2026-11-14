# Data Model: CMP-006 Aspect Fitting

## LayerFitMode (Compositor)

`String` raw values, `CaseIterable`: `fill`, `fit`, `stretch`, `pixelAccurate`.

## LayerFit (Compositor)

| Field | Type | Rule |
|---|---|---|
| mode | LayerFitMode | |
| anchor | LayerPoint | content fractions; each component clamped to 0…1; non-finite reads 0.5; default (0.5, 0.5) |

`LayerFit.default` = fill at the centre (what photo and video draw when no fit is set).

## LayerFitPlacement (Compositor)

Inputs: content width and height (pixels), output width and height (pixels), `LayerFit`, output
pixels per content pixel (pixelAccurate only; default 1, non-finite or ≤ 0 reads 1).
Any size ≤ 0 gives the identity (visible 1, offset 0).

| Field / derived | Meaning |
|---|---|
| visibleWidth, visibleHeight | output size in content fractions |
| offsetX, offsetY | content coordinate of the output's top-left corner |
| `textureCoordinate(x:y:)` | `offset + p·visible` (outside 0…1: transparent) |
| `contentRect` | content's rectangle in output fractions: origin `−offset ÷ visible`, size `1 ÷ visible` |
| `pixelAspect` | output pixels per content pixel horizontally ÷ vertically (1 except stretch) |
| `contentToOutput` | `LayerTransformMatrix`, normalized content → normalized output |
| `placed(transform:outputWidth:outputHeight:)` | `transform.matrix(aspect) * contentToOutput` |

## LayerCompositeSettings (Compositor) — changed

Adds `fit: LayerFit?` (default nil = the layer's own default).

## LayerFitting (Compositor, Metal) — new protocol

`AnyObject`, `var fit: LayerFit? { get set }`. Adopted by `ImageLayerSource` and `VideoLayerSource`.

## VideoPictureGeometry (VideoLayer)

Placement on the upright size + `CameraRotation`; `textureCoordinate(x:y:)` returns the texture
coordinate after rotation, nil-free (outside 0…1 means transparent).

## SceneFit (SceneFormat) — new

| Field | Type | Saved |
|---|---|---|
| mode | String | `composite.fit.mode`, required inside `fit`; any string kept |
| anchor | LayerPoint | `composite.fit.anchor`, optional (centre), clamped 0…1 with `valueClamped` |

`SceneComposite.fit: SceneFit?` (nil: field absent). `SceneLiveState.preservedFits:
[LayerInstanceID: SceneFit]` keeps unknown modes for capture. New `SceneIssue` code
`unsupportedFitMode` (warning; repair-report note).
