# Contract: Parameter search (UIX-009)

## S1 `ParameterSearch.search(_ query: String, in descriptors: [ParameterDescriptor]) -> [ParameterSearchHit]`

- Pure and deterministic; no selection, visual or layer input.
- Empty or whitespace-only query → every descriptor, catalog order, tier `.namePrefix`.
- Otherwise every word must match (R2); ordering per research D3. `ids(_:in:)` returns the hits' IDs.

## S2 `ParameterSearch.fold(_:)` — case-, diacritic- and width-insensitive folding (D2).

## S3 `ParameterUnit.searchTerms` — folded unit terms (D4).

## S4 UI

| Element | Identifier | VoiceOver |
|---|---|---|
| Settings row | `parameterSearchLink` | "Search Parameters" |
| List | `parameterSearch` | navigation title "Search Parameters", search field prompt "Name, group or unit" |
| Result row | `parameterSearchResult.<id>` | label = name; value = "<group>, <value>[, on screen]"; button; activating opens the inspector |
| No results | `parameterSearchEmpty` | "No parameters match" + hint |
