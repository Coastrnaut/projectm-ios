# ADR-0055: A Local, Opt-Out Recently Played List of Preset IDs

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: PRE-006 (`specs/159-pre-006-recent-history`)
- **Constitution**: Privacy constraints (no audio stored; data stays on the device), I (public APIs),
  X (evidence)
- **Amends**: feature 001 FR-065 and feature 002 FR-123 ("No listening history, recently played list,
  or purchase data is stored by the app"), for exactly two UserDefaults keys

## Context

The roadmap row PRE-006 asks to "track recent preset IDs locally with opt-out and clear control", with
the acceptance "Clear deletes history and does not alter favorites". FR-065 and FR-123 forbid a
recently played list, and the privacy policy says no listening history is stored, so the row cannot be
built without amending them.

## Decision

1. **What is stored**: `recentPresets`, at most 50 preset IDs, most recent first, de-duplicated. No
   times, durations, counts, audio, audio source or app names. A preset counts once it stayed on
   screen for 3 s after a successful load.
2. **Opt-out**: `settings.recentPresets.enabled` ("Remember Recently Played", Settings), on by default
   as the roadmap's "opt-out" says. Turning it off stops recording and clears the list at once; an off
   switch found at launch clears any list.
3. **Clear History**: confirmed in a destructive alert; removes `recentPresets` only. Favorites, the last
   preset, the scope, tags and collections are untouched (tested byte for byte).
4. **Never leaves the device**: the list is a FILE-005 excluded key (never in a backup, never restored);
   the switch is backed up like other preferences. FILE-011 erases the list with favorites; the category
   is renamed "Collections, tags, favorites and history".
5. **Still forbidden**: storing audio, listening (audio) history, source-app history or purchase data.
   FR-065/FR-123's audio and source clauses stand unchanged.

## Consequences

- The privacy policy's "What is stored on your device" lists the history and the switch; the FR-063
  coverage table gains a PRE-006 row. App Privacy stays "Data Not Collected": nothing is sent anywhere.
- The device privacy check (`scripts/run_device_tests.py` `ALLOWED_KEYS`) allows both keys.

## Alternatives considered

- **Opt-in (off by default)**: more conservative, but contradicts the roadmap's "opt-out" and leaves the
  feature unused; the data is minimal, local and one switch away from gone.
- **A file beside `tags.json`**: would ride along in FILE-005's collections folder copy; rejected.
- **Timestamps for grouping by day**: more personal data with no acceptance need; rejected.
