---
name: prompts-are-human-tests
description: "Any device test that can raise a system prompt (permission, picker, alert) belongs together in the human testing part, never in the automated runs"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-16T16:47:52.330Z
---

On 2026-11-16 the camera device tests stopped on D1 at an iOS camera permission prompt in the middle of the automated
run. The owner said: "remember to put all tests that will prompt for something together as part of the human testing,
not the automated testing, remember this and commit it to autotester.md".

**Why:** a prompt stops an unattended run and blocks every later test until a person answers it; the owner must not
be surprised mid-run.

**How to apply:**
- Any test that can make iOS (or the app) show a prompt that needs a person (camera, microphone, Local Network,
  photo library, notifications, pickers, purchase sheets, Siri, share sheets) goes into one human-testing group, run
  together with the owner present and told in advance. Today that group is `PermissionPrimerDeviceTests` (it waits
  for the answer and never taps).
- Automated batches assume the prompts were already answered; before including a test that could prompt, check the
  permission is granted (or run the human group first) and never let a prompt appear mid-batch.
- Keep `docs/autotester.md` ("Human testing group") and CLAUDE.md owner rule 14 current.

Related: [[maintain-autotester-doc]], [[unattended-autonomous-device-stage]].

**Amended 2026-11-18:** the owner asked to "automate everything all tests, reanalyze each test that you think requires a
human and find a way to automate it". Prompting tests now answer their prompts themselves in a separate prompt-flow
batch run alone and on schedule (never mid-batch); only hardware or body steps stay with the owner.
