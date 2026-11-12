# Research: AUD-006 Seekable transport

Decisions are numbered `AUD-006-D1…`. Measurements were made on the build Mac (Mac Studio, Xcode
27.2) on 2026-11-12 with a throwaway command-line probe (`AVAudioEngine` in offline manual
rendering, 44.1 kHz stereo, 1,024-frame render calls; not committed). They describe the Mac's
AVFAudio in offline mode; real-time behavior on devices is not established by them.

## AUD-006-D1: Where stale audio lives at a seek

**Finding**: audio is in transit in five places: segments queued in `AVAudioPlayerNode`; rendered
audio accumulated inside the engine's tap; the `PCMSink` ring; the `Normalizer`'s converter; the
normalized ring. The tap is the surprising one: although the tap is installed with
`bufferSize: 1024`, it delivered blocks of 4,410 frames (100 ms) on its own thread, some time
after the render call. After 10,240 rendered frames only 8,820 had been delivered.

**Probe**: without replacing the tap, `player.stop()` + schedule from a new frame + `play()`
delivered 5,516 frames of the old position after the seek (the tap's partial block and the block
after it), then the new position. With the tap removed and installed again between `stop()` and
the new schedule, the first delivered frame was exactly the target frame and no old frame arrived.

**Decision**: a seek is a hard cut through all five stages (plan, Design 2). The tap is replaced
at every cut.

**Alternatives considered**: (a) gate by the tap buffer's sample time: needs the engine's render
time at the cut, a safety margin in real time, and breaks when the timeline restarts after an
engine pause; (b) cross-fade or let old audio drain: violates AUD-006-R10; (c) tag samples with a
generation inside the ring: changes the ring's format for every source.

## AUD-006-D2: A fixture that states its own position

**Decision**: a Float32 CAF written by test code in which frame `n` (0-based) carries `m = n + 1`:
left = `(m / 4096) / 4096`, right = `(m % 4096) / 4096` (integer division). Both are exact binary
fractions below 1, so a 16.7-million-frame track is representable; silence decodes to `m = 0`.

**Finding**: through player → main mixer → tap at the file's sample rate, the values arrive bit
for bit (8,820 of 8,820 frames decoded in sequence). With a sample-rate conversion (48 kHz mono
into a 44.1 kHz output) values are interpolated, so exact-frame tests use equal rates; other rates
are tested for order (monotonic position) and position only.

## AUD-006-D3: Cost of a cut

**Finding**: 100 consecutive cuts (stop, remove tap, install tap, schedule, play) took 33 ms in
total. A cut can run synchronously on the main actor.

**Decision**: seeks are synchronous main-actor calls; scrubbing is limited to 10 per second
(AUD-006-R12) to bound file seeks and tap churn on slower devices, not because of this cost.

## AUD-006-D4: Reading the position

**Finding**: `player.playerTime(forNodeTime: player.lastRenderTime)` returned exactly the number
of frames rendered since `play()` (10,240 after ten render calls; 0 right after `play()`), in the
player's own sample rate (48,000 for a 48 kHz file into a 44.1 kHz output). After `stop()` and
while the engine is paused `lastRenderTime` is nil. After `engine.pause()`/`start()` and
`player.play()` the count continued (3,072 → 5,120), but the engine dropped the tap's partial
block across the pause.

**Decision**: position = start frame of the current schedule + player time; nil means "nothing
rendered yet" (the start frame). Pause captures the position, stops the player and holds the
frame; resume is a cut from the held frame. The position never depends on timeline behavior across
an engine pause or an interruption.

## AUD-006-D5: Detecting the end of a track

**Finding**: of the three completion types, `.dataConsumed` and `.dataRendered` fired in offline
rendering; `.dataPlayedBack` never did (it needs output latency from a real device). All fire on
the player's own queue, and `player.stop()` fires the completions of cancelled segments.

**Decision**: `.dataRendered` signals the end of a non-looping track; `.dataConsumed` keeps
feeding the loop (unchanged from AUD-001-D8). Each completion carries the schedule generation it
was created with and only posts a main-actor task; a stale generation is ignored. Completions never
call the player (AUD-001's deadlock note).

## AUD-006-D6: Changing to a track with another format

**Finding**: with the engine running offline, `disconnectNodeOutput(player)` followed by
`connect(player, to: mainMixer, format: newFormat)` kept the engine running, and the next schedule
played. Audio started about 6,650 output frames (150 ms) after `play()`; the player time stayed
consistent with the audio delivered.

**Decision**: reconnect only when the format differs. A short silence between different tracks is
accepted (spec Edge Cases). Real-time reconnection is exercised by the simulator UI test with two
tracks of different formats; hardware is `{device}`.

## AUD-006-D7: What the endless loop becomes

**Decision**: playback continues around the play order. One item (the reference track, or a
library of one): the gapless loop is kept as is. Several items: the end of a track starts the
next, last wraps to first. Nothing ends by itself, so the visualizer is never left without audio.

**Rationale**: it is the behavior AUD-004 will name "repeat all", and for one track it is exactly
today's. **Alternatives**: keep repeating one track (Next would be the only way forward; surprising
for a transport); stop at the end of the list (leaves the visualizer idle; AUD-004 adds "off").

## AUD-006-D8: User pause versus lifecycle pause

**Finding**: `CaptureManager.handle(.foreground)` resumes any session that is Paused without a
reason. A user's pause would therefore start playing again after a visit to the home screen.

**Decision**: `CaptureManager.pause()` records `isPausedByUser`; foreground and unlock skip the
resume while it is set; `resume()` clears it. The classifier sees the same `suspended` and
`resumed` events as for a lifecycle pause, so the status is "Paused" and "Active audio" has to be
verified again after Play (AUD-006-R20). Stop playback is a user pause plus a seek to 0, which is
why its status is also "Paused".

**Alternatives**: a new `AudioState` case for user pause or transport stop (changes the export
schema and the ui-states contract for no user benefit); keeping the session "Active" while paused
(untruthful).

## AUD-006-D9: Where the transport state lives

**Decision**: `PlaybackTransport.state` is derived from `CaptureManager` (running → playing;
otherwise paused; stopped only while the user's Stop playback holds in the current session). The
only stored transport facts are the current item, the order and "stopped in session N".

**Rationale**: an interruption or a lost route pauses playback without the transport's doing; a
stored "playing" would then be false. Deriving keeps one source of truth (Constitution IV).

## AUD-006-D10: Test seam for the whole pipeline

**Decision**: `AVInAppPlaybackBackend` compiles wherever AVFAudio exists; its `AVAudioSession`
code stays `#if os(iOS)`. An internal initializer puts its graph in offline rendering, so host and
simulator tests drive the production backend, source, manager, analyzer and normalizer. The
real-time path differs only in who calls render.

## AUD-006-D11: Design for the features that build on this

- AUD-003 (queue): replaces `ListPlayOrder` behind `PlayOrder`; `PlaybackTransport.prepare` and
  `setOrder` accept any order, also during playback.
- AUD-004 (repeat), AUD-005 (shuffle): `PlayOrder.item(after:)` may return nil (end of playback)
  or a shuffled item; the transport already treats nil as "stay stopped at the end".
- AUD-010 (balance): a pan on the player node does not change the tap's source of truth; out of
  scope here.
- AUD-014 (interruption recovery): the user pause flag is the input it needs; today's handling is
  unchanged.
- AUD-015 (background policy): suspend and resume keep their entry points.
- PERF-013 (audio-render sync): the discard operation defines the discontinuity point it must
  account for.

## AUD-006-D12: Found while implementing

- A tap asked for a format other than the mixer bus has raises an Objective-C exception
  (`-10865`); the bus format can change when the engine starts or the player is reconnected, so
  the format is read at every tap installation.
- `playerTime(forNodeTime:)` raises an exception for a node time with neither a valid sample time
  nor a valid host time (right after a cut, before the next render); guarded.
- Cutting at the automatic change after a finished track dropped that track's last tap block
  (4,410 frames) from the analysis. A track that played to its end is therefore followed without
  a cut; only user jumps cut (spec AUD-006-R10).
- SwiftUI's `Slider` did not deliver its end-of-editing callback for a drag made by the simulator
  UI test; the times stayed at the dragged value until the controls were rebuilt. The scrubber is
  a drag gesture in `TransportBar` instead.

## Open, device phase

- Whether `player.stop()` takes effect before the render cycle in flight on hardware (the cut
  assumes the new tap never receives audio rendered before it was installed).
- Position after an interruption that stops the engine while playing.
- Reconnection in another format on hardware routes (Bluetooth, AirPlay).
