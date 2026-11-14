# Data Model: MED-010 Logo Overlay

## LogoCorner (enum, raw value = saved name)

`topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `center`, `custom`. Anchors: (0,0), (1,0),
(0,1), (1,1), (0.5,0.5); `custom` uses the stored anchor.

## LogoPlacement (value, plain Swift)

| Field | Type | Range / default | Notes |
|---|---|---|---|
| corner | LogoCorner | default `bottomRight` | unknown name → default |
| anchorX, anchorY | Double | 0…1, default 1, 1 | used when `custom`; non-finite → 0.5 |
| size | Double | 0.05…0.5, default 0.15 | fraction of the output's shorter side, along the logo's longer side |
| margin | Double | 0…0.2, default 0.04 | fraction of the shorter side |
| opacity | Double | 0…1, default 1 | multiplies premultiplied colour |

Every value is clamped at init; −0 is stored as 0. JSON (UserDefaults and scenes):
`{"corner":"bottomRight","anchorX":1,"anchorY":1,"size":0.15,"margin":0.04,"opacity":1}`; a missing
or malformed field reads as its default.

## LogoRect (value)

`x, y, width, height` in output pixels (Double), top-left origin (research D5).

## Stored logo (app)

| Item | Where |
|---|---|
| identifier | UserDefaults `settings.logo.id` (canonical UUID string) |
| placement | UserDefaults `settings.logo.placement` (JSON Data) |
| picture | FILE-008 reference in Application Support/Photos, PNG ≤ 1024 px |

States: none → importing → stored (or notice) → removed. A missing file clears the identifier on read.

## Scene logo asset

`assets["logo"] = {"type":"logo","storeID":"<UUID>","placement":{…}}` — `SceneAssetKind.logo(storeID:)`;
placement via `SceneAsset.logoPlacement`. One per scene (the first logo asset by key order is used).

## Scene archive record

`{"key":"logo","type":"logo","path":"assets/logo.png"}`; PNG only; at most one.

## Logo layer state

`ImageLayerState` (reused): empty, loading, ready(width, height), failed(error). Counters: `framesShown`,
`renderCount` (CMP-013 reuse visible).
