# Contract: VIS-008 Particle Fountain

## C1 ParticleFountainSimulation (CPU, every platform)

- `enqueueOnset(atNanoseconds:strength:threshold:) -> Bool`: queued (FIFO, 32) unless full (counted in `droppedOnsets`).
- `advance(toNanoseconds:)`: the first call sets the anchor; then every step k with t_{k+1} ≤ target runs: spawn queued onsets with time ≤ t_k (burst R2, Reduce Motion R9; truncated at 512, counted in `droppedParticles`), integrate (R3), remove dead (R4). Time going backwards does nothing. At most 240 steps per call; the rest of a longer gap is skipped (anchor moved).
- `reset()`: clears particles and queue, restores the seed, forgets the anchor and counters.
- Read: `liveCount`, `spawnedCount`, `droppedParticles`, `droppedOnsets`, `simulatedNanoseconds`, `particle(i)`; `configuration` (get/set; changes apply to later bursts).

## C2 ParticleFountainLayout (CPU) and ParticleFountainGenerator (Metal)

- Layout: `layout(simulation:width:height:)` → one square per live particle (side max(size·R, 2 px), centred at (W/2 + x·R, H − 0.1·R − y·R), colour `palette.color(bar: sequence % 16, of: 16)` with alpha R7); `squareCount`, `quad(_:)`, `tessellate(into:capacity:gain:) -> Int`, `meanLevels(gain:transfer:into:)`; conforms to `FlashRegionLayout`. No allocation per frame.
- Generator: `SpectrumTextureGenerator`; `init(device:pixelFormat:configuration:) throws(VisualGeneratorError)`; `simulation`; `layout`; `limiter`; `lastGain`; `downstreamLuminance`; `barCount` (carried); `enqueueOnset(atNanoseconds:strength:threshold:)`; `restartLoop()` (limiter and simulation reset; FX-019-R11 keeps the envelope history). `encode`: advance to `context.timeNanoseconds` → layout → envelope gain → tessellate → `FlatShapePass.draw`; `bands` unused.

## C3 Bus mapping (`VisualBandFeed`)

- `ParticleFountainTrigger.onset(_ event: AnalysisEvent) -> (strength: Float, threshold: Float)?`: non-nil only for `.onset`.

## C4 App

- `VisualChoice.particleFountain` (`isNative`, not `usesBars`), title "Particle Fountain"; `ParticleGravity` titles Low, Medium, High; `NativeSpectrumStyle.particleFountain(gravity:)`.
- Settings row `particleGravityPicker`; host view label "Particle Fountain visualization", identifier `particleFountain`, value "<Gravity> gravity, <glow>".
- The host's bus subscription is held while beat rings or the fountain are shown; onsets are enqueued stamped with the frame's time; `reduceMotion` reaches the fountain's configuration.
