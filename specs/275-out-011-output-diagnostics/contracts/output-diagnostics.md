# Contracts: OUT-011 Output Connection Diagnostics

## C1 OutputDiagnostics (PresentationLifecycle)

- `public struct OutputReadings: Equatable, Sendable` (fields in data-model.md), `sanitized()`.
- `public enum OutputDiagnostics: Equatable, Sendable { case disconnected; case connected(OutputReadings) }`
  - `rows: [OutputDiagnosticsRow]` (`id`, `title`, `value`), `text: String` (one "Title: value" line per row),
    `summary: String` (probe), `static let notAvailable = "Not available"`,
    `static let disconnectedText = "No external display connected"`.
  - Formats per spec Clarifications (speckit-clarify).

## C2 Coordinator (app)

- `ExternalDisplayCoordinator.outputDiagnostics: OutputDiagnostics` — computed on every read (OUT-011-R4); never stored.
- `VisualSlotView.standInReadings: OutputReadings?` — used instead of the screen (DEBUG fake, tests); cleared when the
  slot is discarded with its window.
- `OutputScreenReader.readings(screen:)` — the only UIKit reader.

## C3 Settings section

- `OutputDiagnosticsSection(external:)` after `ExternalDisplaySection`, header "Output Diagnostics".
- Each row: one accessibility element, identifier `outputDiagnostics.<id>`, label = title, value = value.
- Disconnected: one row, identifier `outputDiagnostics.status`, value "No external display connected".
- Connected: "Copy diagnostics" button (identifier `outputDiagnosticsCopy`), local-only pasteboard.

## C4 DEBUG

- Fake display buttons `uitestConnectExternal` (1920 × 1080) and `uitestConnectExternalSmall` (1280 × 720); both set
  stand-in readings. Hidden probe `externalDiagnostics` = `OutputDiagnostics.summary`.
