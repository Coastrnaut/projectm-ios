# Contract: OSC schema export (OSC-010)

## C1 Builder (PerformanceControl, pure)

- `OSCSchemaExport.rows(table:disabled:descriptors:displayName:) -> [OSCSchemaRow]`: one row per table route, table order.
- `OSCSchemaExport.document(rows:appVersion:exportedAt:) -> String`: Markdown, LF line endings, ends with a newline.
  Same inputs → same bytes.
- `OSCSchemaExport.fileName(exportedAt:) -> String`, `OSCSchemaExport.utcStamp(_:)`.
- Table header, exactly: `| Address | Parameter ID | Name | Arguments | Input | Value range | Unit | Origin | Enabled |`.
- Cells escape `|` as `\|`; newlines become spaces.
- Never present: IP addresses, ports, peer names, allow-list entries, send destinations, device or user names,
  received values.

## C2 App

- Settings › OSC › OSC Routes, last section: button "Export routes…" (`oscSchemaExport`), footer explaining the file.
- Tap: builds the document now, writes `<tmp>/Sharing/<UUID>/<file name>`, presents the share sheet (kind
  `.oscSchema`); a second tap while offered does nothing. Any outcome deletes the copy; completed shows "Shared.".
- Failure: `ShareFileStore.failureNotice`, no sheet.
- DEBUG `-uitestShareSimulation`: buttons `simulateShareCompleted` / `simulateShareCancelled` and a probe
  `oscSchemaExport.probe` whose value is the generated text.
