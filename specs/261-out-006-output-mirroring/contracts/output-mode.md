# Contract: OUT-006 Output Mode

- **C1 PresentationLifecycle** — `ExternalOutputMode` (`sameScene`, `clean`; `init(stored:)`), `OutputLayerClass`, `OutputLayerRouting.includes(_:external:mode:)` and `routesSceneOverlays(target:mode:)`. Pure Swift, no UIKit.
- **C2 ExternalDisplayCoordinator** — `outputMode` (set live; re-evaluates inside the call; never moves the visual), `routesSceneOverlays` (read-only), `onSceneOverlaysChange: ((Bool) -> Void)?` (called inside the change, only on change), `outputModeSummary` "mode=<sameScene|clean> target=<device|external> overlays=<shown|hidden> externalViews=<n>". AppCoordinator wires the callback to `logo.outputSuppressed` and applies the stored mode at launch.
- **C3 LogoCoordinator** — `outputSuppressed: Bool`; `effectivePlacement` (= placement, or placement with opacity 0 while suppressed) is what every attached and newly attached layer gets. `placement` and the stored value never change.
- **C4 Settings** — `ExternalOutputSetting.outputMode` stored under `outputModeKey`, part of `keys`; Settings › External Display "Output" picker (`externalOutputModePicker`): "Same scene", "Clean output"; footer explains both.
- **C5 DEBUG probe** — with `-uitestExternalDisplay`, a hidden `externalOutputMode` element whose value is `outputModeSummary`.
