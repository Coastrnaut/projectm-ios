# ADR-0007: Preset Library Licensing and the Paid Unlock

- **Status**: Accepted 2026-11-10 (decided by Claude under the owner's standing approval; feature 002 spec Clarifications)
- **Date**: 2026-11-10
- **Spec**: feature 002 FR-101-FR-105, FR-121 · **Research**: R-29 · **Constitution**: IX

## Context

Feature 002 bundles the projectM team's four preset packs and texture pack (12,913 presets beyond
the 28 Included, ADR-0004) and unlocks them with a one-time, $1.99 non-consumable purchase.
Milkdrop presets were almost never released under a stated license. Two packs (cream-of-the-crop,
en-d) carry the projectM team's statement that the presets are assumed to be in the public domain
because they were freely released and widely redistributed for two decades, and that any author
who objects can have their presets removed. Three repositories (projectm-classic,
milkdrop-original, milkdrop-texture-pack) have no license file.

## Decision

1. **What is sold**: access to the app's full bundled library, not the presets themselves. The 28
   Included presets stay free.
2. **Basis**: every pack is bundled under the projectM team's own redistribution basis (assumed
   public domain; removal on the author's request). The three packs without a license file are
   treated the same way; this is a recorded risk, not a verified license.
3. **Takedowns**: `Apps/projectM-iOS/Resources/PresetBlocklist.json` lists content hashes removed at
   an author's request; every build honors it, in every pack. Requests are accepted through the
   repository's issues (support URL).
4. **Attribution**: Settings › Licenses shows every pack with its source, pinned commit, license
   statement (or the no-license note) and its authors (FR-121).
5. **Fallback**: if a pack's status changes (an upstream license, a broad objection), it can be
   dropped or blocklisted in a later release without changing the purchase or the app's code.

## Consequences

- Revenue depends on content whose authors kept copyright in principle; the risk is accepted and
  mitigated by the blocklist and attribution. A legal opinion is recommended before broad
  promotion of the paid unlock.
- ADR-0005 (LGPL engine, App Store) is unaffected: presets are data, not engine code.
- The store copy describes the purchase as unlocking the full preset library; it claims no
  ownership of the presets.
