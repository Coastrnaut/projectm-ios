# Entitlements and Info.plist review (task T111; R-16)

Reviewed 2026-11-10 against research R-16 ("no App Groups, no background mode except
`screen-capture`, no network, no push, no iCloud, no entitlement; Info.plist contains only
`NSMicrophoneUsageDescription` and `NSScreenCaptureUsageDescription` as privacy keys").

## Entitlements

Signed Release device build of ProjectMiOS (`codesign -d --entitlements -`), Apple Development
signing:

| Entitlement | Value | Assessment |
|-------------|-------|------------|
| `application-identifier` | `<team>.org.projectmios.ProjectMiOS` | Added by signing; required |
| `com.apple.developer.team-identifier` | `<team>` | Added by signing; required |
| `get-task-allow` | true | Development signing only; App Store distribution signing removes it. Recheck on the archive (T112) |

The project declares no entitlements file and no capability: no App Groups, iCloud, push, network
extensions, keychain sharing, or the Screen Recording entitlement (removed 2026-11-09, ADR-0001
ruling 16). `scripts/check_compliance.py` rejects entitlement keys in `project.yml` on every push.

## Info.plist (`Apps/ProjectMiOS/Info.plist`)

| Key | Value | R-16 |
|-----|-------|------|
| `NSMicrophoneUsageDescription` | The FR-005 explainer text | Allowed |
| `NSScreenCaptureUsageDescription` | "Only the audio of the content you choose to share is used, and only on this device. It is not recorded or sent anywhere." | Allowed |
| `UIBackgroundModes` | `screen-capture` only | Allowed (ADR-0001 ruling 17) |
| `ITSAppUsesNonExemptEncryption` | NO (added 2026-11-10, owner) | Export compliance: no encryption beyond iOS; not a capability |
| `UILaunchScreen`, orientations, `UIApplicationSupportsIndirectInputEvents`, bundle keys | Standard | Not capabilities |

No `NSAppTransportSecurity`, `NSLocalNetworkUsageDescription`, `NSBonjourServices`, URL schemes,
document types, or other privacy usage keys.

## Conclusion

No capability beyond R-16. Open item for the release review (T112): confirm on the App Store
archive that distribution signing removed `get-task-allow` and added nothing else.
