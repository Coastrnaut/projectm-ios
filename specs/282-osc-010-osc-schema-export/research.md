# Research: OSC-010 OSC Schema Export

- **OSC-010-D1 Format.** Decision: one Markdown file with a fixed-column pipe table. Rationale: readable in any
  text editor and Files' preview, parseable by splitting on `|`; one share item. Alternatives: JSON alongside
  (two items, more UI; deferred), CSV (less readable header), plain text (no table structure).
- **OSC-010-D2 Source of truth.** Decision: the live `OSCRoutesCoordinator.table`, `disabled` and `routable`
  descriptors plus `OSCReceiverCatalog.testValueDescriptor`. Rationale: identical to what the dispatcher gets via
  `OSCParameterRoutes.active`, so the export cannot drift from the registry. Alternative: re-deriving the table
  from UserDefaults (duplicate logic, could read network keys).
- **OSC-010-D3 Date.** Decision: an injected instant (seconds since 1970), formatted in the package as UTC ISO 8601
  with a small days-to-civil conversion (no Foundation, Linux-safe). Rationale: deterministic, time-zone free.
  Alternative: local wall-clock time (varies by device setting), omitting the date (less useful).
- **OSC-010-D4 Hand-off.** Decision: REC-012 `ShareFileStore` + `ActivitySharePresenter` with a new kind, and the
  `-uitestShareSimulation` stand-in, as PERF-012 does. Alternative: `fileExporter` (another UI path and no shared
  cleanup), `ShareLink` (file must exist before the tap; no completion for cleanup).
- **OSC-010-D5 Privacy by construction.** Decision: the builder's signature takes no settings store, so it cannot
  read `settings.osc.port`, `settings.osc.approvedPeers` or `settings.osc.send.*`; the leak test seeds them anyway
  and scans the output for them and for IPv4/IPv6 patterns.
- **OSC-010-D6 Numbers.** Decision: shortest round-trip `Double.description`, whole numbers printed without
  `.0`; locale-independent.
