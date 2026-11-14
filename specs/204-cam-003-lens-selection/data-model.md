# Data Model: CAM-003

- **CameraLens** (`String` raw value): `ultraWide`, `wide`, `telephoto`; display order is that order;
  titles "Ultra Wide", "Wide", "Telephoto". Unknown raw value → `wide`.
- **CameraLensInventory**: `backLenses: [CameraLens]`, distinct, in display order.
  `resolve(_ stored:)` → stored if listed, else `wide`.
- **CameraInputSwitchOutcome**: `switched`, `keptPrevious` (new input could not be created or added),
  `fellBackToWide`, `noInput` (nothing could be added; the feed reports unavailable).
- **Setting** `settings.camera.lens`: the stored raw value; backed up (FILE-005), erased with Settings.
  After a user's choice ends on another running lens (the chosen one could not be opened), the stored
  value follows the running lens (R6); a lens merely missing on the device keeps its stored value (R5).
