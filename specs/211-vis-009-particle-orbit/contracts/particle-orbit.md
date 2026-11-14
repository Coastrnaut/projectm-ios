# Contract: VIS-009 Particle Orbit

## C1 ParticleOrbitSimulation (CPU, every platform)

- `setTarget(base:bass:)`: target = `ParticleOrbitConfiguration.targetRadius(base:bass:depth:)` (R3); held until the next call.
- `enqueueBeat(atNanoseconds:) -> Bool`: FIFO of 16; full → false, counted in `droppedBeats`.
- `advance(toNanoseconds:)`: the first call after a reset sets the anchor; then every step k with t_{k+1} ≤ target runs: apply beats with time ≤ t_k (pulse = 1), slew the radius, decay the pulse, advance phases. ≤ 240 steps, a longer gap re-anchors; earlier times do nothing.
- `reset()`: reseeds the slots, radius = target = base, pulse 0, empty queue, no anchor, counters 0.
- Read: `radius`, `targetRadius`, `pulse`, `count`, `phase(_:)`, `offset(_:)`, `particleSteps`, `stepsRun`, `configuration` (get/set; count changes keep every slot's draws).

## C2 ParticleOrbitLayout (CPU) and ParticleOrbitGenerator (Metal)

- Layout: `layout(simulation:width:height:)` → square 0 = centre (side 0.12·R·(1 + A·pulse), alpha 0.7), squares 1…count = particles at (W/2 + R·r·o_k·cos φ_k, H/2 − R·r·o_k·sin φ_k), side max(size·R, 2 px), colour `palette.color(bar: k % 16, of: 16)` alpha 0.75; `squareCount`, `drawnRadius`, `quad(_:)`, `tessellate(into:capacity:gain:) -> Int`, `meanLevels(...)`, `FlashRegionLayout`.
- Generator: `SpectrumTextureGenerator`; `init(device:pixelFormat:configuration:) throws(VisualGeneratorError)`; `simulation`, `layout`, `limiter`, `lastGain`, `downstreamLuminance`, `barCount`; `drive(base:bass:)`; `enqueueBeat(atNanoseconds:)`; `restartLoop()`.

## C3 Mapped bass (`VisualParameters`)

- `VisualParameterIDs.particleOrbitRadius` = `visual.particleOrbit.radius` (0.2…0.8, default 0.5, step 0.01, continuous default policy).
- `ParticleOrbitRadiusDrive.resolve(manual:kick:modulator:) -> (base: Double, bass: Double)`: unbound or nil modulator → (manual, kick); bound → (modulator value, 0).

## C4 App

- `VisualChoice.particleOrbit` (native, no Bars), title "Particle Orbit"; `ParticleOrbitRadius` titles Small, Medium, Large; `NativeSpectrumStyle.particleOrbit(radius:)`.
- Settings row `particleOrbitRadiusPicker`; host view label "Particle Orbit visualization", identifier `particleOrbit`, value "<Radius> radius, <glow>".
- The host's bus subscription is held while the orbit is shown; accepted beats (`BeatRingTrigger`) are enqueued at the frame's time; each frame, after modulation, `drive` gets `ParticleOrbitRadiusDrive.resolve(manual: setting, kick: kickEnvelope, modulator:)`; `reduceMotion` reaches the configuration.
