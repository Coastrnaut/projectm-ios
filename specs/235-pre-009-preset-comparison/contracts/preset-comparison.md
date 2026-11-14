# Contract: preset comparison (PRE-009)

## C1 `PresetComparing` (Rendering; implemented by ANGLE's `PresetComparisonRunner`)

```swift
public protocol PresetComparing: AnyObject, Sendable {
    /// Starts a session with presets A and B. False when one is running or finishing, or the app cannot present.
    func start(_ a: Data, _ b: Data, configuration: PresetComparisonConfiguration,
               onEvent: @escaping @Sendable (PresetComparisonEvent) -> Void) -> Bool
    /// Queues one stamped tick for both engines (any thread).
    func submit(_ tick: PresetComparisonTick)
    /// Ends the session; waits briefly for the worker.
    func stop()
}
```

Events: `.loaded(side)`, `.failed(side, message)`, `.frame(PresetComparisonFrame)` (both pictures and the batch's
delivery), `.stopped(reason)`. A failed side keeps the other drawing (R11).

## C2 Lockstep (R5, R6)

For every batch the worker records (when a recorder is set) and delivers the identical
`PresetComparisonDelivery` to A and then B, feeds the identical samples in identical chunks, sets the identical
frame time, then draws both. A side that failed to load receives nothing and is not recorded.

## C3 Renderer (R10, R12)

`VisualizerRenderer.presetComparison` (default nil) and `sharedPCMReader` (default nil). `ANGLERenderer` returns
its runner and its attached reader; it stops the runner on PERF-011 suspension, memory pressure and deinit.

## C4 UI (R1-R4, R14)

Row menu `comparePreset` ("Compare…" / "Compare with <A>"), VoiceOver action "Compare"; bar `compareBar` with
`compareCancel`; sheet `presetCompare` with panes `comparePaneA`/`comparePaneB`, buttons `compareChooseA`,
`compareChooseB`, `compareClose`, and the note `compareTestSignal` when the test signal is in use.
