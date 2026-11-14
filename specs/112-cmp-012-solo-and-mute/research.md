# Research: CMP-012 Solo and Mute

## CMP-012-D1: Where the overlay lives

- **Decision**: a separate value, `LayerSoloMute`, beside the `LayerStack`; the compositor holds one
  and is given it with `setSoloMute(_:)`.
- **Rationale**: every saving path (SCN-001 `SceneLiveState` capture, SCN-002 autosave from
  `SceneInputs`, SCN-010 history of document bytes, show cues and archives of documents) starts from
  the stack or the app's inputs. Keeping the overlay out of both makes "never saved" structural
  rather than a rule each path must remember. The stack's equality (which `apply` uses to skip
  work) is untouched.
- **Alternatives**: `solo`/`mute` fields on `LayerStackEntry` (the CMP-002 header anticipated
  this): rejected, every capture would need to drop them and stack equality would change; a saved
  per-layer flag: destructive.

## CMP-012-D2: The rule

- **Decision**: `lets(entry) = !mutedLayer(entry) && !mutedGroup(entry.group) && (!soloActive ||
  soloedLayer(entry) || soloedGroup(entry.group))`, where `soloActive` = any soloed layer or group
  that exists in the given stack. Drawn = existing conditions (picture, opacity > 0, group on with
  opacity > 0) && `lets`.
- **Precedence**: mute wins; a muted solo still counts toward `soloActive`.
- **Stale IDs**: entries naming absent layers or groups are ignored by the rule; `pruned(to:)`
  drops them for hosts that want a tidy value. The compositor does not prune by itself (a layer
  removed and re-added under a new ID is a new layer anyway, since IDs are never reused within a
  stack).
- **Scene loads**: a restored scene reuses its saved instance IDs, so a host that loads a
  different scene into a compositor calls `setSoloMute(LayerSoloMute())` (contract).

## CMP-012-D3: Groups

- **Decision**: computed per layer with its group: group solo lets every member through, child solo
  lets that child through, group mute blocks every member. The group itself is drawn when at least
  one member is drawn; its opacity and transform still apply. CMP-011's isolation test already loops
  over `isVisible` layers only, so a solo that leaves one normal child at group opacity 1 flattens,
  and a hidden screen-mode child no longer forces isolation.
- **Disabled group**: stays hidden whatever is soloed (solo never overrides a saved flag).

## CMP-012-D4: Keep sources running

- **Decision**: hidden layers keep rendering; only the composite draw is skipped. Same as opacity 0
  (CMP-003) and a disabled group (CMP-011-D7).
- **Cost**: a hidden camera or video layer keeps decoding and rendering its picture (its usual
  per-frame cost); the composite saves one draw per hidden layer. Measured on the Mac by the opt-in
  bench (CMP-012-S6), not device evidence.
- **Alternative**: pause hidden sources: rejected (un-mute would show a stale or late frame, and a
  camera restart takes hundreds of milliseconds).

## CMP-012-D5: Resolution time

- **Decision**: the overlay is resolved into one Bool per layer record at `apply` and at
  `setSoloMute`, not per frame. Changes show from the next frame, without a fade.
- **Rationale**: no per-frame set lookups or allocation; bit-identical restore is independent of
  timing.

## CMP-012-D6: Undo, autosave, UI

- **Undo**: not undoable; `SceneHistory.record` suppresses a state whose bytes equal the current
  one, and the overlay never changes the bytes.
- **Autosave**: captures `SceneInputs`; the overlay is not an input.
- **UI**: none (no layer-editing screen; CMP-015 will add the buttons); no DEBUG probe or launch
  argument, because there is no user-visible surface for a UI test to drive.
