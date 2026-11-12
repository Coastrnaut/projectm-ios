# Contract: presentation-bound resources (PERF-011)

Package `PresentationLifecycle`. Extends, and does not replace, the renderer contract in
`specs/001-ios-projectm-visualizer/contracts/projectm-bridge.md`.

## For a resource (renderer loop, warm-up, later a camera or video layer)

1. Conform a class to `PresentationBoundResource` on the main actor.
2. `suspendForPresentationLoss()` must leave no work running when it returns and should release
   memory that is only useful while presenting. `resumeForPresentation()` must restore the state
   the user left, not a default state (a user pause stays a pause).
3. Both must be idempotent and must not touch an object the resource has released.
4. Requests that arrive while suspended must not start work; remember them if they still matter
   on resume.
5. The name contains no user content.
6. A capture source is not a presentation-bound resource. Audio sources follow
   `CaptureManager.handle(_:)` (FR-050); do not register them.

## For the owner of the registry (the app)

1. One registry per app. Register a resource when it is created; registration while the app
   cannot present suspends the resource immediately.
2. Feed the four `PresentationSignal`s through `PresentationAvailability` and pass `canPresent` to
   `setCanPresent(_:)`. Do not feed the inactive scene phase.
3. Guarantees: suspend in reverse registration order, resume in registration order, at most one
   call per resource per transition, no call after `unregister` or deallocation, no strong
   reference to a resource.
4. `onTransition` is called once per real change, after the sweep.

## Renderer contract addition

`VisualizerRenderer.presentationResources` lists what the renderer registers, in registration
order (default: none). While suspended a renderer draws no frame and starts no frame loop,
whatever `pause()`/`resume()` calls it receives; `setPreset` still loads into the engine.
