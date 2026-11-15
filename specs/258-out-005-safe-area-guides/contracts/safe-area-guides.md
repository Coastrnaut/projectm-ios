# Contract: OUT-005 Safe-Area Guides

## C1 Geometry (PresentationLifecycle, pure Swift)

- `SafeAreaGuideChoice(actionPercent:titlePercent:showsCentreCross:)` clamps both percentages.
- `SafeAreaGuideGeometry.make(viewWidth:viewHeight:outputAspect:choice:) -> SafeAreaGuideGeometry?`: nil for a non-finite or non-positive view size; `outputAspect` nil (or unusable) means the whole view; else the largest rect of that aspect fitted and centred. Action and title rects are `output` scaled by their fractions about its centre; title uses min(title, action).
- `SafeAreaGuideGeometry.externalAspect(width:height:pixelAspect:) -> Double?`: width × pixelAspect ÷ height, nil when unusable.

## C2 Overlay (app)

- `SafeAreaGuidesLayer` draws the three outlines (and the cross) in the visualizer backdrop above the visual with `.splitOutputScaled()`, `.allowsHitTesting(false)`, `.accessibilityHidden(true)`; nothing while off.
- It is never added to a `VisualSlotView`, the visual's view, a compositor or the external window.
- DEBUG with `-uitestDiagnostics`: `safeAreaGuidesProbe` (value "action=93 title=90 cross=no frame=WxH").

## C3 Setting

- `SafeAreaGuideSetting(defaults:)`: `isEnabled`, `actionPercent`, `titlePercent`, `showsCentreCross`; keys in data-model.md; `allKeys`; `choice`.

## C4 Settings UI

- Settings › Performance, section "Safe-area guides": `safeAreaGuidesToggle` ("Show guides"), `safeAreaActionPercent` and `safeAreaTitlePercent` sliders (ACC-005 `.accessibleParameter`, whole percent) and `safeAreaCentreCrossToggle` ("Centre cross"), shown while on; a footer saying the guides are never on an external display, in recordings or saved frames. Section id `safeAreaGuides` for `-uitestSettingsSection`.

## C5 Coordinator

- `ExternalDisplayCoordinator.externalScreenAspect: Double?`: the external slot holding the visual: bounds width × resolved pixel aspect ÷ height; nil when the visual is not external.
