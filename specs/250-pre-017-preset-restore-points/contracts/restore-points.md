# Contract: PRE-017 restore points (PresetLibrary)

```swift
public struct UserPresetVersion: Codable, Sendable, Equatable, Identifiable { sha256, blobHash, byteCount, replacedAt, name; id = sha256 }
public struct UserPresetVersionLimits: Sendable, Equatable { perPreset, total, totalBytes; static let standard }
public enum UserPresetVersionsAvailability: Equatable, Sendable { case available, newerFormat }

extension UserPresetStore {
    public var versionsAvailability: UserPresetVersionsAvailability
    public func versions(of id: String) -> [UserPresetVersion]          // newest first
    func versionBytes(of id: String, sha256: String) -> [UInt8]?         // size and SHA-256 checked
}

extension UserPresetLibrary {
    public func versions(of id: String) -> UserPresetVersionList         // editable presets only; newest first
    public func versionText(of id: String, sha256: String) -> PresetEditorText?
    public func revert(_ id: String, to sha256: String, expectedSHA256: String) async -> PresetEditOutcome
}
```

`revert` outcomes are `PresetEditOutcome` (as `edit`); a missing or damaged version is
`.refused(.versionUnavailable)` ("This version could not be read."). Every other refusal is the edit's.
Files a revert may touch: `files/<old>`, `files/<new>`, `index.json`, `history.json`, `versions/*` (see spec R6).
