# ADR-0020: Imported Photo Layer

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: MED-001 (`specs/044-med-001-import-photo-layer`)
- **Constitution**: I, VI, X; Security (imported files are untrusted); Privacy

## Context

The roadmap's MED rows bring the user's own media into the visual: MED-001 a still photo, then
video (MED-002), slideshows (MED-006), Ken Burns (MED-007), animated images (MED-008), logos
(MED-010), relinking (MED-013) and a hardened decoder (MED-014). The app stored no images and had
no photo picker. CMP-001 (ADR-0013) and CMP-002 define layers and stacks; the Camera visual
(ADR-0017) is the existing picture-producing layer.

## Decisions

1. **The photo is a layer.** `ImageLayerSource` (target `ImageLayer` in `Packages/Compositor`)
   implements the CMP-001 contract: decode once on a background queue into a mipmapped
   `.rgba8Unorm_srgb` texture with straight alpha, draw with aspect fill (fit is available), output
   linear premultiplied, transparent fallback while loading or after a failure. `LayerKind.photo`
   allows one per stack.
2. **One decoder boundary.** `ImageDecoding` (default `ImageIODecoder`) does every check — size,
   type, completeness as ImageIO reports it, pixel count, bounded upright decode — with typed
   `ImageImportError`s. Both the importer and the layer decode through it, so MED-014 hardens one
   place (known gap: ImageIO decodes a PNG cut short without error).
3. **Pickers without permissions.** SwiftUI `PhotosPicker` without a photo library (out of process,
   no `NSPhotoLibraryUsageDescription`, limited and full access behave the same) and `fileImporter`
   for images. The picked file is read once (security scope, coordinated, bounded) and not kept.
4. **Pixels-only copies.** The stored copy is re-encoded from the decoded pixels: PNG when the
   picture has transparency, JPEG 0.9 otherwise; upright, at most 4096 px on its longest side, with
   no source metadata (the system encoder adds only the copy's pixel size and color space).
5. **Limits**: 40 MB per picked file, 100 million pixels per picture, 4096 px stored.
6. **Storage**: one photo, `Application Support/Photos/<UUID>.{png,jpg}`, identifier in the setting
   `settings.photo.id`; resolved only inside that folder; included in the user's own device backups
   like imported audio; Remove Photo deletes it. No required-reason API (no file dates, no volume
   capacity).
7. **The app shows it as one fixed stack**: Settings › Visual › "Photo" = photo layer with the
   circular spectrum on top, in its own compositor host with the Camera visual's loop rules. Unlike
   Camera, the choice persists across launches (no sensor). User-built stacks belong to the layer
   inspector and scene rows.

## Consequences

- App Privacy stays "Data Not Collected"; the privacy policy describes imported photos.
- `PhotoVisualHost` repeats `CameraVisualHost`'s loop; a shared host is left to the scene rows.
- Device behaviour (the real pickers, HEIC, large panoramas, iCloud Drive) is verified by the owner
  on D1 and D3 (MED-001-T22 to T24).
