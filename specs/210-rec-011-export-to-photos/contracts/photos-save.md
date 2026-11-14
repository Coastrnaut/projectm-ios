# Contract: Save to Photos (REC-011)

## C1 Buttons

| Where | Label (visible) | Accessibility label | Identifier |
|---|---|---|---|
| "Frame ready" panel | Save to Photos | Save the frame to Photos | `frameResultPhotos` |
| "Recording ready" panel | Save to Photos | Save the recording to Photos | `recordingResultPhotos` |
| Recordings row (readable files only) | Save to Photos | Save to Photos (also a row accessibility action) | `recordingLibraryPhotos` |

While a save runs: every Save to Photos button is disabled; for the item being saved Keep, Discard, Rename and Delete are disabled too.

## C2 Flow

1. Tap → `status()`; `notDetermined` → `request()` once → its answer.
2. granted (authorized or limited) → one `save` call → `saved` or `failed`.
3. denied → `denied`; restricted → `restricted`; no save call.
4. No outcome moves, renames, deletes or rewrites the original; offered items stay offered.

No call to `status()` or `request()` happens outside step 1 (launch, capture, recording finish, Keep, opening Recordings).

## C3 Texts

| Outcome | Notice | Open Settings |
|---|---|---|
| saved | Saved to Photos. | no |
| denied | Photos access is off. To save to Photos, allow adding photos for projectM in Settings. The file is still in the app. | yes |
| restricted | Saving to Photos is restricted on this device. The file is still in the app. | yes |
| failed | The file couldn't be saved to Photos. It is still in the app. | no |

The notice (`photosSaveNotice`, text `photosSaveNoticeText`, buttons `photosSaveNoticeSettings`, `photosSaveNoticeDismiss`) shows under the result panels and as the Recordings screen's notice row; each outcome posts ACC-011 row **X8a** (capture lane, cause user, persistent).

## C4 Permission

Info.plist `NSPhotoLibraryAddUsageDescription`: "Save to Photos adds the frame or recording you choose to your photo library. projectM can only add items; it never sees or reads your library."
Catalog entry "Photos (add only)". `NSPhotoLibraryUsageDescription` is never declared.

## C5 DEBUG stand-in

`-uitestPhotosAccess granted|denied|restricted|failing` replaces access and saver with in-memory fakes (no system prompt, nothing written to Photos). DEBUG builds only.
