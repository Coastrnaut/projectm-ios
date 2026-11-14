# Contract: power profile (PERF-008)

## Rendering (public)
- `enum PowerProfile: String, CaseIterable, Sendable { standard, followLowPowerMode, batterySaver }`; `title`, `budget(lowPower:)`.
- `struct PowerBudget: Equatable, Sendable`; `.standard`, `.batterySaver`.
- `enum PowerProfileState`: `static var current: PowerProfile` (lock-protected; setting a new value posts
  `didChangeNotification` on the main thread); `static func budget(lowPower:)`.
- `QualityGovernor.settings(thermal:lowPower:adaptiveEffects:budget:)`; existing overloads = `.standard`.
- `QualityGovernor.changeNotifications: [Notification.Name]` (thermal, power state, profile).
- `QualityGovernor.current()` uses `PowerProfileState`.

## App
- `PowerProfileSetting` (@Observable): `profile` (didSet stores, applies, signposts); `key`.
- Settings rows: identifiers `powerProfile.<raw>`, selected row has `.isSelected`; section id `powerProfile`.
- Overlay line (only when the budget is not `.standard`): `power <title lowercased> <fps> fps <scale>x`, e.g. `power battery saver 30 fps 0.75x`.
- Recording limit text: "Battery saver limits the visual to 30 fps."
