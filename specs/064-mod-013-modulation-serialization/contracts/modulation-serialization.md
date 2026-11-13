# Contract: Modulation Serialization (MOD-013)

## M1 Migration table (ParameterGraph)

```swift
public struct ModulationIDMigrations: Sendable, Hashable {
    public static let formatVersion: Int            // 1
    public static let none: ModulationIDMigrations
    public let rules: [Rule]
    public var version: Int
    public init(_ rules: [Rule]) throws(ModulationIDMigrationError)
    public func resolve(_ id: String) -> ModulationIDResolution
}
```

M1.1 Refused on init, every issue collected: `malformedID`, `invalidVersion` (since < 1),
`versionOrder` (since decreases), `duplicateRule`, `selfRename`, `crossKind`, `cycle` (message names
the loop `a → b → a`).
M1.2 `resolve` follows renames to the end; `resolve` of the end is `.unchanged`; a rename chain ending
at a retire rule is `.retired`.

## M2 Registry (ParameterGraph)

`ParameterRegistry(descriptors:retiredIDs:migrations:)` additionally refuses (ParameterRegistryError):
`migrationFromRegistered` (a rule's `from` is registered, or an audio rule's `from` is a known
feature), `migrationFromNotRetired` (a parameter rule's `from` is not retired),
`migrationTargetUnknown` (a rename chain ends at an ID that is neither registered nor retired, or an
unknown audio feature). `resolveParameter` applies the retired set after the rules.

## M3 Restore (SceneFormat)

`SceneDocument.restoreModulation(registry:) -> SceneModulationRestore` never throws. Every binding
(`$.bindings[i]`) and connection (`$.modulation.connections[j]`) appears exactly once in
`report.entries`, in document order (bindings first), with the outcome of research MOD-013-D2.
Generator-declaration problems give `invalidModulation` errors at `$.modulation.generators[k]` (or
`$.modulation` for size limits) and then no connection is applied (all are reported rejected).

## M4 Issues (SceneFormat, contract C5 amended)

New codes: `migratedReference`, `retiredReference`, `orphanedBinding`, `orphanedConnection` and
`rejectedConnection` (warnings). `invalidBinding`, `duplicateBindingTarget` and `invalidExpression`
become warnings. `invalidModulation` stays an error. `validate` emits the restore's issues in its
modulation step (bindings, then generators, then connections).

## M5 Live state

`liveState` returns applied bindings (migrated), their expressions by migrated target,
`modulation` = declared generators + applied connections, `preserved`, and `modulationReport`.
`SceneLiveState.apply(to: AudioFeatureModulator)` replaces the modulator's bindings with the applied
ones in order. `SceneLiveState.validatedGraph(registry:)` returns the MOD-014 validated graph of
binding edges plus `modulation`.

## M6 Capture

`SceneDocument(capturing:)` writes applied bindings (with expressions) in live order then preserved
bindings; generators; applied connections then preserved connections. For any document D:
let C1 = capture(restore(D)); then capture(restore(decode(encode(C1)))) == C1.
