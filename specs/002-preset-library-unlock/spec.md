# Feature Specification: Full Preset Library Unlock

**Feature Branch**: `002-preset-library-unlock` (work lands on `main`, as for feature 001)

**Created**: 2026-11-10

**Status**: Draft

**Input**: User description: "Specify the full preset library unlock for ProjectM-iOS (feature 002).
The 28 presets bundled in release 1.0 stay the free default library; a one-time, low-cost in-app
purchase (non-consumable, $1.99 price point) unlocks every preset published by the projectM team
(cream-of-the-crop, projectm-classic, milkdrop-original and en-d packs, 12,915 presets beyond the 28,
plus the milkdrop texture pack). Packs are pinned git submodules bundled in the app; nothing is
downloaded. Locked presets are visible but marked; large-library browsing, search, scoped
Next/Previous/Random, pack credits, and an explicit allowance for StoreKit purchase traffic only."
(full text: README section 18.5).

Requirement and criterion numbers start at 101 so they never collide with feature 001
(`specs/001-ios-projectm-visualizer/spec.md`), whose requirements stay in force unless a line below
amends one explicitly.

## Clarifications

### Session 2026-11-10

Answered by Claude under the owner's standing approval (all decisions delegated, no human interaction).

- Q: What does the purchase grant, and on what license basis are the four packs sold? → A: Access to the app's full bundled library, under the projectM team's own redistribution basis for these packs (assumed public domain, removed on the author's request), with an author-request blocklist honored in every release; the risk is recorded in an ADR at planning.
- Q: Should a search-result scope survive a relaunch? → A: No; storing search text would be listening/browsing history (feature 001 FR-065), so after a relaunch a search scope falls back to All.
- Q: What happens to the preset that is playing when a refund or revocation locks the packs? → A: It keeps playing until the user changes preset; the scope falls back to Included, so Next/Previous/Random continue in Included.
- Q: What count does a locked pack show before purchase? → A: Its total preset count, with a lock; after purchase, the playable count.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse and play a large library without paying (Priority: P1)

A user who has not paid opens the preset browser and sees a library home: "Included" (the 28 free
presets), one entry per published pack with its preset count and a lock, and "All presets A-Z".
They can open any pack, drill into its categories, search by preset or author name, and play any
Included preset. Next, Previous and Random keep working exactly as in release 1.0.

**Why this priority**: Every user, paying or not, uses the browser. Release 1.0 behavior must not
regress, and seeing the locked library is what makes the purchase discoverable.

**Independent Test**: With no purchase, open the browser, navigate Included and a locked pack,
search for an author, play an Included preset, and use Next/Previous/Random; nothing locked plays.

**Acceptance Scenarios**:

1. **Given** no purchase, **When** the user opens the preset browser, **Then** the library home
   lists Included (28), each pack with its count and a lock, and All presets A-Z.
2. **Given** no purchase and Included as the scope, **When** the user taps Next, Previous or
   Random repeatedly, **Then** only the 28 Included presets play, in the same order as release 1.0,
   and Random never repeats the current preset.
3. **Given** no purchase, **When** the user searches "Geiss", **Then** results from every pack
   appear, grouped by pack, locked ones marked.
4. **Given** a favorite saved in release 1.0, **When** the user updates the app, **Then** the
   favorite is still marked and plays.

---

### User Story 2 - Unlock the full library with one purchase (Priority: P1)

A user taps a locked preset (or the unlock banner on a locked pack) and sees a purchase sheet:
the price in their currency, what it includes (packs and counts), Buy, and Restore Purchases. After
buying, every pack unlocks at once, including offline, and the scope becomes the curated pack.

**Why this priority**: This is the feature's purpose; without it the extra presets are unreachable.

**Independent Test**: In a test purchase environment, buy, confirm every pack unlocks and plays,
relaunch offline and confirm it stays unlocked; on a fresh install, Restore Purchases unlocks.

**Acceptance Scenarios**:

1. **Given** no purchase, **When** the user taps a locked preset, **Then** the purchase sheet shows
   the localized price, the included packs with counts, Buy, and Restore Purchases.
2. **Given** the sheet, **When** the purchase succeeds, **Then** all packs unlock within 1 second,
   the tapped preset plays, and the scope becomes Cream of the Crop.
3. **Given** a completed purchase, **When** the app launches with no network, **Then** the library
   stays unlocked.
4. **Given** a purchase on the same Apple Account and a fresh install, **When** the user taps Restore
   Purchases, **Then** the library unlocks.
5. **Given** the purchase is cancelled, fails, or is pending (Ask to Buy), **When** the sheet
   closes, **Then** nothing unlocks and the user sees a non-modal message saying which.
6. **Given** a refunded or revoked purchase, **When** the app next checks, **Then** the packs lock
   again; favorites stay listed with a lock.

---

### User Story 3 - Find and play presets in a 12,943-preset library (Priority: P2)

A user who has unlocked the library browses by pack and category, searches names and authors,
plays a preset, and then uses Next/Previous/Random within what they were browsing (a pack, a
category, a subcategory, Favorites, a search result, or All).

**Why this priority**: Without scopes and search, a library this size is unusable; it builds on the
unlock.

**Independent Test**: With the library unlocked, open Fractal › Nested Spiral, play a preset, tap
Next and Random several times, and confirm they stay inside that subcategory; repeat with a search
result and with Favorites.

**Acceptance Scenarios**:

1. **Given** the unlocked library, **When** the user opens Cream of the Crop, **Then** it lists its
   categories with counts, and each category lists its subcategories with counts.
2. **Given** the user plays a preset from a subcategory, **When** they tap Next at its last preset,
   **Then** playback wraps to the first preset of that subcategory.
3. **Given** a scope, **When** the user taps Random, **Then** a different preset from the same scope
   plays.
4. **Given** a search, **When** more than 200 presets match, **Then** the first 200 show grouped by
   pack with a prompt to refine the search.
5. **Given** a scope is chosen, **When** the controls are shown, **Then** the scope name and its
   preset count appear under the preset name.

---

### User Story 4 - Credits and licenses for every pack (Priority: P3)

A user opens Settings › Licenses and sees one entry per pack with its source repository, pinned
version, license statement, and its list of preset authors.

**Why this priority**: Required for honest attribution (feature 001 FR-047, FR-067) but does not
block using the library.

**Independent Test**: Open Licenses and check each pack's entry shows source, version, license
statement and authors.

**Acceptance Scenarios**:

1. **Given** Settings › Licenses, **When** the user opens a pack, **Then** it shows the pack's source,
   version, license statement and its preset authors.

### Edge Cases

- A preset fails to load (engine error or missing texture): it is skipped with feature 001's
  "Preset could not be loaded" message and excluded from the scope for the rest of the session.
- Presets known to fail or removed at an author's request before release never appear.
- The same preset exists in several packs: it appears once, in the highest-priority pack; a preset
  identical to one of the 28 Included keeps the Included identity.
- A scope with one playable preset: Next/Previous replay it; Random keeps it (nothing else to pick).
- A scope with no playable presets (a locked pack before purchase): Next/Previous/Random do nothing
  and the purchase sheet is offered.
- The purchase is pending approval (Ask to Buy): nothing unlocks until approval arrives; approval
  while the app runs unlocks immediately.
- The store is unavailable or the price cannot be loaded: the sheet says so and offers Restore and
  Close; nothing crashes.
- The app is updated with a new pinned pack version: favorites of presets that no longer exist are
  dropped silently at launch; the rest keep working.

## Requirements *(mandatory)*

### Functional Requirements

**Library contents**

- **FR-101**: The app MUST bundle the 28 presets of release 1.0 as the free "Included" library and
  the four projectM preset packs (cream-of-the-crop, projectm-classic, milkdrop-original, en-d) plus
  the milkdrop texture pack, each taken from a pinned version of the projectM team's repository.
  No preset file is copied into this project's own source; the app downloads no presets or code.
- **FR-102**: Each preset MUST appear once: identical presets are merged, keeping the Included
  identity first, then cream-of-the-crop, projectm-classic, milkdrop-original, en-d. Only
  Milkdrop-format presets (`.milk`) are included.
- **FR-103**: Presets that fail to load in a pre-release sweep, and presets removed at an author's
  request, MUST NOT appear in the library.
- **FR-104**: Identifiers of the 28 Included presets MUST be unchanged, so favorites and the last
  preset from release 1.0 keep working.

**Purchase**

- **FR-105**: The app MUST offer one non-consumable purchase that unlocks all four packs; without it,
  only Included presets play.
- **FR-106**: Locked presets MUST be visible and marked. Selecting one, or the unlock banner of a
  locked pack, MUST open a purchase sheet showing the localized price, the included packs with
  counts, Buy, Restore Purchases and Close.
- **FR-107**: After a successful purchase or restore, the library MUST unlock within 1 second
  without a relaunch, and stay unlocked across launches, offline included.
- **FR-108**: Cancelled, failed and pending purchases MUST unlock nothing and show a non-modal
  message naming the outcome; a pending purchase approved later MUST unlock when the app learns of
  it.
- **FR-109**: A refunded or revoked purchase MUST lock the packs again at the next entitlement
  check; favorites remain listed with a lock. A locked preset that is playing keeps playing until
  the user changes preset, and the scope falls back to Included.
- **FR-110**: The app MUST determine the unlock from the platform's purchase records at launch and
  while running; it MUST NOT store its own "unlocked" flag.

**Browsing**

- **FR-111**: The preset browser MUST open on a library home listing Included, each pack with its
  preset count (the total with a lock before purchase, the playable count after), and All presets
  A-Z.
- **FR-112**: Packs MUST be browsable by their own structure: cream-of-the-crop by category then
  subcategory, projectm-classic by original collection, en-d by episode, milkdrop-original as one
  list; every folder shows its count.
- **FR-113**: Search MUST match preset names and author names, case- and diacritic-insensitively,
  across the whole library, show results grouped by pack, mark locked results, and show at most
  200 results with a prompt to refine beyond that.
- **FR-114**: Favorites MUST work across all packs with the existing favorites list; the
  Favorites view lists them alphabetically with their pack.
- **FR-115**: Every list MUST be alphabetical by display name within its folder (feature 001
  FR-088).

**Scopes and playback**

- **FR-116**: A scope is Included, a pack, a category, a subcategory, a collection or episode,
  Favorites, the current search result, or All. Choosing a preset from a list MUST set the scope to
  that list.
- **FR-117**: Next and Previous MUST step alphabetically within the scope and wrap at both ends;
  Random MUST pick uniformly within the scope and never repeat the current preset when the scope
  has more than one playable preset (feature 001 FR-088).
- **FR-118**: Scopes MUST contain only playable presets: unlocked, not excluded, and not failed in
  this session.
- **FR-119**: The default scope MUST be Included before purchase, and Cream of the Crop right after
  a purchase or restore; the user's chosen scope MUST persist across launches, except a search
  scope, which falls back to All (no search text is stored).
- **FR-120**: The controls overlay MUST show the current scope's name and playable count under the
  preset name.

**Credits, privacy, accessibility**

- **FR-121**: Settings › Licenses MUST list each pack with its source, pinned version, license
  statement and preset authors (feature 001 FR-067).
- **FR-122**: Amends feature 001 FR-068: the only network traffic allowed is the platform's own
  purchase and restore traffic for this product; the app adds no analytics, accounts, tracking or
  servers. The privacy policy and App Privacy answers MUST say so.
- **FR-123**: Amends feature 001 FR-065: persistence is limited to feature 001's list plus the
  chosen scope (a user setting). No listening history, recently played list, or purchase data is
  stored by the app.
- **FR-124**: Every new control, row, lock and the scope indicator MUST have accessible labels
  (for example "Nested Spiral 3, by Martin, locked"), and scope changes MUST be announced
  (feature 001 FR-070).

### Key Entities

- **Preset**: a playable visual; display name, author, pack, folder path (category/subcategory or
  collection), content identity, free or locked.
- **Preset Pack**: one published collection; name, source, pinned version, license statement,
  author list, preset count.
- **Library Index**: every preset after merging and exclusions, with pack and folder; built before
  release, read at launch.
- **Scope**: the set Next/Previous/Random walk; kind (Included, pack, folder, Favorites, search,
  All), name, playable presets.
- **Entitlement**: whether the full-library purchase is owned, as reported by the platform.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-101**: The library opens with all 12,943 presets available to browse within 0.15 seconds of
  app launch completing, on the reference device and D3.
- **SC-102**: Search results update within 0.05 seconds of each keystroke on the reference device
  and D3.
- **SC-103**: Scrolling any preset list stays at the display's frame rate (no visible stutter) on
  D1-D3.
- **SC-104**: Preset switches from any pack meet feature 001 SC-007 (95% of first frames within
  1 second) on the reference device.
- **SC-105**: After a successful purchase or restore, every pack is playable within 1 second, and
  stays playable after relaunching with no network.
- **SC-106**: In 1,000 Random picks within a scope of N ≥ 2 presets, the current preset never
  repeats and no locked or excluded preset is ever picked.
- **SC-107**: Without a purchase, Next/Previous/Random and the 28 Included presets behave exactly as
  in release 1.0 (same order, same favorites).
- **SC-108**: The app's installed size grows by no more than 40 MB over release 1.0.

## Assumptions

- **License basis (Clarifications, 2026-11-10; recorded in a new ADR at planning):** the purchase sells access to the app's full library, bundled under the
  projectM team's own redistribution basis for these packs ("assumed public domain; removed on the
  author's request"), with an author-request blocklist honored in every release. Packs without a
  license file are treated under the same basis, the risk is recorded, and any pack can be dropped
  in a later release without affecting the purchase.
- Price point $1.99 (the App Store tier nearest to "$2"); the product is created in App Store
  Connect by the owner (signing and store accounts stay manual).
- No preview of locked presets in this feature.
- The milkdrop texture pack is bundled whole; it is not a preset pack and is not locked.
- projectm-classic's four `.prjm` files (an older projectM format) are excluded (FR-102).
- Device measurements follow feature 001's rules: simulator results are never device evidence.
- Feature 001's requirements, constitution and ADRs stay in force except where FR-122 and FR-123
  amend them.
