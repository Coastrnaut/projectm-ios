# Contract: OSC parameter routes (OSC-003)

## R1 Table (`PerformanceControl/OSC/OSCParameterRoutes.swift`)
- `OSCParameterRoutes.routable(in:applied:) -> [ParameterDescriptor]`
- `OSCParameterRoutes.table(routable:builtInAliases:userAliases:includeTestRoute:) -> [OSCParameterRoute]`
- `OSCParameterRoutes.active(_:disabled:) -> [OSCRoute]`
- `OSCParameterRoutes.value(normalized:for:) -> Double?` (clamp 0…1, MOD-003 linear, clamp to range)
- `OSCRouteAliasRules.validate(address:parameter:table:userAliases:routable:) -> Result<OSCRouteAlias, OSCRouteAliasError>`

## R2 Dispatcher (`OSCDispatcher`)
- `setRoutes(_:)` replaces the allowlist (thread-safe); drops live values of unreached parameters.
- `liveValues`, `clearLiveValues()`; `counters.unknownAddresses`.
- Unknown address → `.unknownAddress`; non-numeric or not exactly one argument → `.wrongArguments`; no state change in either case.

## R3 App
- `OSCRoutesCoordinator`: `rows`, `setEnabled(_:address:)`, `addAlias(address:parameter:)`, `deleteAlias(address:)`, `aliasError`; persists both keys; applies routes through `OSCReceiverCoordinator.setRoutes`.
- `OSCReceiverCoordinator`: `routes`, `liveValues`, `applyLiveValues`, `unknownAddressCount`.
- `AppCoordinator.pushLiveValues(_:_:)` merges MIDI and OSC into `NativeSpectrumHost.externalValues`.
- Accessibility identifiers: `oscRoutesLink`, `oscRoute<address with / and . as _>`, `oscRoutesIgnored`, `oscAliasAddress`, `oscAliasParameter`, `oscAliasAdd`, `oscAliasError`.
