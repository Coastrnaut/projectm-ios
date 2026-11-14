# Contract: Parameter Shelf (UI and storage)

## P1 Entry points (UIX-004-R1)

- Context menu of each UIX-003 Settings control: "Inspect", then "Pin to Shelf" (identifier
  `shelfPin.<id>`) or "Remove from Shelf" (`shelfUnpin.<id>`). At the limit, "Pin to Shelf" is disabled
  and titled "Shelf Full (8)".
- VoiceOver actions on the same control: "Pin to Shelf" / "Remove from Shelf".
- Inspector sheet, navigation bar (leading, so it stays in reach at every text size): button `parameterInspector.pin`
  ("Pin to Shelf" / "Remove from Shelf"), only for a parameter with a control.

## P2 Overlay strip (UIX-004-R3, R4, R9)

- Container identifier `parameterShelf`, inside `controls`; present only while the controls are shown and
  the shelf has pins or a note.
- One control per pin, identifier `shelf.<parameter id>`: slider (`.accessibleParameter`, label = display
  name), toggle or menu picker.
- Note: static text `shelf.missingNote` with the exact count, button `shelf.removeMissing` ("Remove").

## P3 Settings section (UIX-004-R6)

- Section "Parameter Shelf" (id `parameterShelf`): rows `shelfRow.<id>` with VoiceOver actions "Move up",
  "Move down", "Remove from Shelf"; Edit button `shelf.edit`; the same note and Remove
  (`shelfSettings.removeMissing`); footer with the limit.

## P4 Storage (UIX-004-R5, R7, R10)

- Key `settings.parameterShelf.pins`, `[String]`, see data-model.md.

## P5 DEBUG launch arguments

- `-uitestInspectParameter <id>` (UIX-003) opens the inspector, from which the UI test pins.
