# Contract: flash risk classifier

Definition: research ACC-002-D2; decision record ADR-0014.

## Python (`scripts/preset_flash_risk.py`)

```python
RULES = ("toggle-driven", "toggle-flip", "luma-flicker")
def classify(text: str) -> list[str]   # rule ids in RULES order; [] = not flagged
def may_flash(text: str) -> bool
```

`scripts/build_preset_index.py` calls `classify` on every indexed preset's bytes (decoded as UTF-8
with replacement) and writes `"flash": [...]` on records with a non-empty result. The stamp
includes `preset_flash_risk.py`, so changing a rule rebuilds the index.

## Swift (`PresetLibrary.PresetFlashRisk`)

```swift
public enum PresetFlashRisk {
    public enum Rule: String, CaseIterable, Sendable { case toggleDriven = "toggle-driven", toggleFlip = "toggle-flip", lumaFlicker = "luma-flicker" }
    public static func rules(in text: String) -> [Rule]   // in Rule.allCases order
    public static func mayFlash(_ text: String) -> Bool
}
extension IndexedPreset {
    public let flash: [String]?          // index field; nil = not flagged
    public var mayFlash: Bool            // flash is non-empty
}
extension UserPresetLibrary {
    public func flashRisk() -> [String: [String]]   // playable user preset id → rule ids (flagged only), cached per content hash
}
extension UserPreset {
    public func indexed(flash: [String]?) -> IndexedPreset
}
```

Foundation only (`NSRegularExpression`), Linux-safe.

## Parity

`Packages/PresetLibrary/Tests/PresetLibraryTests/FlashFixtures/expected.json` maps each fixture
file name to its expected rule ids. `scripts/test_scripts.py` and `PresetFlashRiskTests` both
assert every entry, so a rule change in one implementation without the other fails a test.
