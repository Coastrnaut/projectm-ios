# ADR-0059: Add-Only Photos Permission for an Explicit "Save to Photos"

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: REC-011 (`specs/210-rec-011-export-to-photos`; contract `contracts/photos-save.md`)
- **Constitution**: I (public APIs only), Privacy constraints ("permission requests MUST occur at the
  point of use with an accurate usage description"; a privacy policy that describes data handling)
- **Amends**: FILE-013's rule that no Photos library key exists (`check_permission_catalog.py`,
  `PermissionCatalogTests`) and REC-012-R7/S4's "the app MUST NOT request any Photos permission". The
  share sheet's own Save to Photos stays excluded (REC-012-R7's exclusion is unchanged).

## Context

REC-011 asks to "save completed image or video only after explicit user action", accepted when a
permission denial leaves the local original intact and shows an error. Writing into the photo library
needs Photos authorization; until now the app declared no Photos key and FILE-013's check rejected any.

## Decision

1. **Add only.** The app declares `NSPhotoLibraryAddUsageDescription` and requests
   `PHPhotoLibrary.requestAuthorization(for: .addOnly)`. `NSPhotoLibraryUsageDescription` (read access)
   stays forbidden by the catalog check; the app never reads, lists or changes library items.
2. **Only on the user's tap.** Status is read and access requested only inside a Save to Photos action on
   "Frame ready", "Recording ready" or a Recordings row. Never at launch, capture, recording finish, Keep or
   opening Recordings (unit test with counting fakes).
3. **Original untouched.** A still is added from its encoded bytes, a video from its file with
   `shouldMoveFile = false`. Denied, restricted and failed saves change nothing and show a notice saying the
   file is still in the app, with Open Settings for denied and restricted.
4. **One way in.** The share sheet keeps excluding Save to Photos, so every save has the app's outcome
   handling and announcement.
5. **Catalog and policy.** A fifth catalog entry, "Photos (add only)", with a matching privacy policy
   bullet; no privacy manifest change (no required-reason API, nothing collected).

## Consequences

- The app's permission count goes from four to five; App Review sees an add-only usage string.
- No explainer before iOS's prompt (the button itself states the action); no album (needs read access);
  no record of saved items.

## Alternatives rejected

- Allow the share sheet's Save to Photos: the app gets no outcome to report and cannot guarantee the
  error notice the roadmap acceptance asks for.
- Read/write access: more than needed (least privilege).
