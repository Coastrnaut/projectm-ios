# Quickstart: QA-011 Final physical device matrix

## A. Inventory and checklist (any OS)

```bash
python3 scripts/qa011_inventory.py            # regenerate device-inventory.json and owner-checklist.md
python3 scripts/qa011_inventory.py --check    # exit 1 when either committed file is stale
python3 scripts/test_scripts.py               # includes QA011InventoryTests, QA011MatrixTests
```

## B. Dry run (no device contact)

```bash
python3 scripts/run_device_tests.py matrix --device D1 --dry-run
python3 scripts/run_device_matrix.py --device D3 --dry-run
```

Expected: every command of every case assigned to that device, nothing written.

## C. Simulator rehearsal (not evidence)

```bash
xcrun simctl create "QA11 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
python3 scripts/run_device_matrix.py --simulator <udid> --work-dir <scratch> --derived-data <scratch>/dd
python3 scripts/run_device_matrix.py verify docs/test-reports/qa-011/runs/sim/<run-id>/record.json
xcrun simctl delete <udid>
```

## D. Final device stage (owner present; main session) `{device}`

Unlock the device, set Auto-Lock to Never, connect the cable, then:

```bash
python3 scripts/run_device_tests.py build                 # Release + PROJECTM_AUTOMATION, signed with the owner's team
python3 scripts/run_device_matrix.py --device D1           # then D2, D3
python3 scripts/run_device_matrix.py verify docs/test-reports/qa-011/runs/D1/<run-id>/record.json
```

Then the person-only sessions in `docs/test-reports/qa-011/owner-checklist.md`.
