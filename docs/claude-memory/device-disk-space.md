---
name: device-disk-space
description: "tests that fill a device's disk must be cleaned up from the Mac; check free space first when a device refuses launches"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-24T18:48:29.709Z
---

On 2026-11-24 D3 (128 GB) ran out of space: a REC-015/REC-009 run left a 67 GB `Library/Caches/QA011-DiskBallast.bin`
in the app container. The app deletes it only at its next DEBUG launch; the run had been stopped, and with the disk
full no launch could follow. Every run was then refused ("Developer App Certificate is not trusted", devicectl launch
hung), and I spent hours asking the owner to re-trust the certificate instead of checking storage. The owner said
"learn the lesson about how d3 used up all its diskspace so this doesnt happen again, remember that lesson".

**Why:** a device-side cleanup that depends on the next launch fails exactly when the disk is full; a misleading
error (trust, launch timeout) hid the cause.

**How to apply:**
- Anything a test writes to a device in bulk (ballast, recordings, exports) must be cleared from the Mac after the
  run, not only by the app: `run_device_ui_tests.sh` runs `scripts/clear_disk_ballast.py` after every run; keep it,
  and add the same for any new bulk-writing test.
- When a device refuses launches for no clear reason (trust, launch timeouts, hangs), first list the app container's
  sizes (`devicectl device info files --domain-type appDataContainer …`, sum `metadata.size`) before asking the owner
  to act. Uninstalling the app frees its whole container.
- When stopping a run mid-test, run `clear_disk_ballast.py --device DX` for that device.
- Related: [[device-runs-never-idle-unexplained]], [[maintain-autotester-doc]].
