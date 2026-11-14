# Contract: SCN-005 Scene Tags

## T1 — file key

`show.json` may contain `sceneTags`: an object whose keys are scene IDs the cues refer to and whose
values are arrays of 1-16 tag strings (each 1-40 characters, trimmed, one line), sorted by folded text
then text, no folded duplicates, ≤ 256 distinct folded tags in the show. The key is omitted when no
scene has tags; a show without tags encodes byte-identical to a pre-SCN-005 file. Format version 1.

## T2 — reading damaged data

Anything in `sceneTags` that breaks T1 is dropped (never refuses the show), counted in
`ShowDecodeWarning.droppedTags(n)`. A non-object `sceneTags` drops the key (n = 1).

## T3 — editing

- Add: trimmed, validated; folded-equal to a tag the scene has → `alreadyTagged`; folded-equal to a
  tag elsewhere in the show → stored with that spelling; refusals change nothing.
- Remove: by folded match.
- Never applies a scene, moves the position or changes cues. Saves the show; announces on the
  library lane: "Tagged <scene> <tag>." / "Removed tag <tag> from <scene>." / the refusal text.
- Duplicate Scene copies tags; a scene leaving the show loses them at the next save.

## T4 — switcher

- Chip row (`sceneSwitcherTags`) when the vocabulary is non-empty; chip `sceneSwitcherTag.<tag>`,
  label the tag, value "<n> scenes", Selected trait when selected.
- Results = entries whose scene carries every selected tag (folded), then UIX-002's query over label,
  scene name, folder path and tags.
- Row tag button `sceneSwitcherTagsButton.<number>` ("Tags for <label>") and VoiceOver action "Tags"
  open the Tags sheet; row subtitle and value append tags ("tags Intro, Loud").

## T5 — Tags sheet

`sceneTags` sheet: title "Tags", the scene's tags (`sceneTag.<tag>`, Remove `sceneTagRemove.<tag>` and
VoiceOver action "Remove"), field `sceneTagField` + Add `sceneTagAdd`, suggestions
`sceneTagSuggestion.<tag>`, Done `sceneTagsDone`.
