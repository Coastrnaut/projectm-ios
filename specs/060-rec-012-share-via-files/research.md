# Research: REC-012 Share via Files

## REC-012-D1: Share sheet API

- **Decision**: `UIActivityViewController` with `completionWithItemsHandler`, presented from a
  zero-size `UIViewControllerRepresentable` placed behind the Share… button (the iPad popover anchors
  there), as PRE-014's `ShareSheetPresenter` does.
- **Rationale**: the handler reports `completed` and `activityError`, which the acceptance needs to
  delete the copy at the right moment and to keep the original. One handler call per presentation.
- **Alternatives**: SwiftUI `ShareLink` (no completion, so the copy could only be swept at launch);
  reusing PRE-014's presenter unchanged (it drops `completed` and the excluded types; changing it would
  touch PRE-014's file).

## REC-012-D2: Copy or original

- **Decision**: a copy per Share… tap at `<tmp>/Sharing/<UUID>/<name>`; stills written from memory,
  recordings with `FileManager.copyItem` (an APFS clone, no extra space in practice).
- **Rationale**: the original is never handed out, so a receiving activity cannot move or change it;
  the per-share folder keeps the descriptive name unique and makes deletion one call.
- **Alternatives**: share the original recording (a later Save… would race the share); hard links
  (same inode: an activity that edits in place would change the original).

## REC-012-D3: Cleanup

- **Decision**: delete the copy's folder on every outcome (completed, cancelled, failed) on the main
  actor; at coordinator init (app launch, `AppCoordinator` stored property) delete every item in
  `<tmp>/Sharing` from a directory listing.
- **Rationale**: the handler runs after the activity has finished with the file (AirDrop sent,
  Messages attached a copy, Files copied). A listing reads no file dates, so no required-reason API.
- **Alternatives**: delete after a delay (no gain, a leak on termination); rely on the system's tmp
  purge (unbounded).

## REC-012-D4: Excluded activities

- **Decision**: `[.saveToCameraRoll, .assignToContact]`.
- **Rationale**: the app has no `NSPhotoLibraryAddUsageDescription`; Save to Photos is REC-011's,
  with its permission rules. Assign to Contact writes the frame into Contacts. Everything else (AirDrop,
  Messages, Mail, Save to Files, other apps) is the user's choice; any network use is by that activity.
- **Alternatives**: allow Photos (needs a usage string and REC-011's rules).

## REC-012-D5: Where the result lives before sharing

- **Decision**: in the coordinator that made it: `FrameCaptureCoordinator.offered` (`CapturedFrame` +
  the capture date for the name) and `VideoRecordingCoordinator.offered` (the temporary file URL; its
  name already carries the date). Neither opens a sheet by itself; Save… opens it.
- **Rationale**: smallest change; REC-003's launch cleanup already covers a leftover recording.
- **Alternatives**: one generic results store (more moving parts for two kinds).

## REC-012-D6: Testing the sheet

- **Decision**: DEBUG `-uitestShareSimulation`: Share… makes the real copy, then shows "Simulate share
  completed" / "Simulate share cancelled" instead of presenting the sheet; a probe
  `captureShareProbe` reads `copies=<n> frame=<yes|no> recording=<yes|no> last=<outcome|none>`.
  `#if DEBUG` only.
- **Rationale**: the system sheet runs out of process and cannot be driven reliably by XCUITest; the
  app-side lifecycle (copy, outcome, cleanup, original kept) is fully exercised. The real sheet is the
  owner's `{device}` check.
