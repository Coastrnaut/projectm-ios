# Data Model: OSC-003 OSC Parameter Routes

- **OSCRoute** (dispatcher entry): `address`, `parameter: ParameterID`, `scale: .raw | .normalized`.
- **OSCParameterRoute** (table row): `address` (identity), `parameter`, `origin: test | standard | builtInAlias | userAlias`.
- **OSCRouteAlias**: `address`, `parameter`; storage line `<address>=<parameter ID>`.
- **OSCReceiverCounters**: adds `unknownAddresses` (also counted in `ignored`).
- **ExternalLiveValues**: per source (`midi`, `osc`) value maps plus the owner (last changer) per parameter; `merged`.
- **Stored keys**: `settings.osc.disabledRoutes` ([String], absent → all on); `settings.osc.aliases` ([String], absent → none).
