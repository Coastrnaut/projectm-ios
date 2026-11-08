# CaptureLab Distribution (FR-090)

CaptureLab is an **internal test tool** for Stage 1 capture feasibility. It is not a product.

- Bundle ID: `org.projectmios.CaptureLab` (separate from ProjectMiOS).
- Distribution: Xcode direct install to test devices, or TestFlight (internal or external testing).
- **Never** submitted for App Store review. Archives are uploaded to App Store Connect only for
  TestFlight builds.
- The ProjectMiOS release check (task T112) confirms that only ProjectMiOS is submitted.
- Signing is configured by a human (Constitution: Security). No signing material is committed.
