# CaptureLab Distribution (FR-090)

CaptureLab is an **internal test tool** for Stage 1 capture feasibility. It is not a product.

- Bundle ID: `org.projectmios.CaptureLab` (separate from ProjectMiOS).
- Distribution: Xcode direct install to test devices, or TestFlight (internal or external testing).
- **Never** submitted for App Store review. Archives are uploaded to App Store Connect only for
  TestFlight builds.
- The ProjectMiOS release check (task T112) confirms that only ProjectMiOS is submitted.
- Signing is configured by a human (Constitution: Security). No signing material is committed.
- Entitlement: CaptureLab declares only the Screen Recording entitlement
  (`Apps/CaptureLab/CaptureLab.entitlements`, ADR-0001 Decision 6). The owner confirms in Xcode
  that the signing team's profile provisions it.

## Before any TestFlight upload (ADR-0002 owner review, 2026-11-08)

Testers on iPadOS 26 (D3) must be able to launch the build, so ScreenCaptureKit, which iOS 26
does not have, must be weak-linked in the exact build that is uploaded:

1. Archive CaptureLab with the Release configuration (the scheme's archive action).
2. Check the load command of the archived executable:
   `otool -l <archive>.xcarchive/Products/Applications/CaptureLab.app/CaptureLab | grep -B2 ScreenCaptureKit`.
   The `cmd` line printed must read `LC_LOAD_WEAK_DYLIB`. `LC_LOAD_DYLIB`, or no output at all,
   fails the check.
3. Install that build on D3 (iPadOS 26.5) and launch it: CaptureLab opens, and System/App Capture
   shows "Requires a newer iOS version".
4. Record the result (date, build number, `otool` output, D3 launch) in the TestFlight notes.
