# CaptureLab Distribution (FR-090)

CaptureLab is an **internal test tool** for Stage 1 capture feasibility. It is not a product.

- Bundle ID: `org.projectmios.CaptureLab` (separate from projectM-iOS).
- Distribution: Xcode direct install to test devices, or TestFlight (internal or external testing).
- **Never** submitted for App Store review. Archives are uploaded to App Store Connect only for
  TestFlight builds.
- The projectM-iOS release check (task T112) confirms that only projectM-iOS is submitted.
- Signing is configured by a human (Constitution: Security). No signing material is committed.
- Entitlements: none. The Screen Recording entitlement (ADR-0001 Decision 6) was removed on
  2026-11-09 because it is offered only to organization accounts (ruling 16).

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
