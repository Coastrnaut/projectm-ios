# Data model: REC-011 Export to Photos

- **PhotosAccess** (enum): `notDetermined`, `granted`, `denied`, `restricted` (research D3). Maps to FILE-013 `PermissionState`.
- **PhotosSaveItem** (enum): `frame(data: Data, format: FrameCaptureFormat, name: String)`, `recording(URL)`. The key used to disable an item's buttons is `.frame` or the recording's standardized path.
- **PhotosSaveOutcome** (enum): `saved`, `denied`, `restricted`, `failed`; each has its notice text and whether it offers Open Settings.
- **PhotosSaveCoordinator** (main actor, observable): `saving: PhotosSaveItem.Key?`, `notice: String?`, `noticeOffersSettings: Bool`, `lastOutcome: PhotosSaveOutcome?`; `save(_:)`, `clearNotice()`, `isSaving(_:)`. No persisted state.
