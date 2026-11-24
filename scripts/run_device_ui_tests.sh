#!/bin/bash
# run_device.sh <d1|d2|d3> <log name> <filter>... : xcodebuild test-without-building on one device, each filter its own
# argument (bash arrays; zsh does not split an unquoted $VAR). Filters: "only:<id>" or "skip:<id>". With MAC_DRIVER=1 the
# Mac driver follows the log. PRODUCTS=<dir> runs another build (the B10 MIDI host: Build/device-acceptance-midi/Products).
set -u
cd /Users/coast/Documents/GIT/projectm-ios
dev=$1; name=$2; shift 2
case $dev in
  d1) udid=00008120-001E4C5C3A42201E ;;
  d2) udid=00008142-001640823C22401C ;;
  d3) udid=00008120-000165E830914032 ;;
esac
args=()
for f in "$@"; do
  case $f in
    only:*) args+=("-only-testing:${f#only:}") ;;
    skip:*) args+=("-skip-testing:${f#skip:}") ;;
  esac
done
log=.autonomous/logs/$name-$dev.log
rm -f "$log"; touch "$log"
# The fixtures live in the app's Documents, which a reinstall (the device matrix) empties: seed what is missing before
# every run (D2 and D3, 2026-11-23: every music test failed at launch after the matrix). FIXTURES=0 skips it.
if [ "${FIXTURES:-1}" = 1 ]; then
  python3 scripts/install_test_fixtures.py --device "$(echo "$dev" | tr a-z A-Z)" --media --if-missing \
    > ".autonomous/logs/fixtures-$name-$dev.log" 2>&1 || echo "== $dev $name: fixture seeding reported a problem (see fixtures-$name-$dev.log)"
fi
# The driver ends with the test run (its end marker); its own 30-minute default left every Mac request after the
# first half-hour of a full run unanswered (D3 full run 1, 2026-11-22: FILE-001-B's files.push), so it gets 12 h.
if [ "${MAC_DRIVER:-0}" = 1 ]; then
  python3 scripts/mac_device_driver.py follow --timeout 43200 --log "$log" --device "$(echo "$dev" | tr a-z A-Z)" > ".autonomous/logs/macdriver-$name-$dev.log" 2>&1 &
  driver=$!
fi
# OSC=1 (B09OSCDeviceTests): start scripts/osc_device_driver.py beside the run, aimed at the device's LAN address (never
# its USB link-local one, devices.resolve), and pass the Mac's LAN address. D2 2026-11-23: a run without the driver
# failed every Mac-to-device OSC test ("Test value, 0.00").
mac_ip=""
if [ "${OSC:-0}" = 1 ]; then
  read -r dev_ip mac_ip < <(python3 -c "import sys; sys.path.insert(0,'scripts/mac_driver'); import devices as d; ip=d.resolve(d.DEVICES['$(echo "$dev" | tr a-z A-Z)']['host']); print(ip, d.mac_address_toward(ip))")
  python3 scripts/osc_device_driver.py --log "$log" --host "$dev_ip" --listen-port 9100 --device "$(echo "$dev" | tr a-z A-Z)" \
    > ".autonomous/logs/oscdriver-$name-$dev.log" 2>&1 &
  osc_driver=$!
  export TEST_RUNNER_MAC_IP="$mac_ip"   # only with OSC=1: an empty value would read as a set address
fi
# TEST_RUNNER_* values reach the test runner only as environment variables of xcodebuild, not as build-setting
# arguments (full run 13, 2026-11-20: FILE-001 and PERF-006 skipped "needs the Mac" with the driver running).
TEST_RUNNER_MAC_DRIVER="${MAC_DRIVER:-0}" TEST_RUNNER_SIRI="${SIRI:-0}" TEST_RUNNER_OSC_DRIVER="${OSC:-0}" TEST_RUNNER_FILE001_FROM="${FILE001_FROM:-D1}" \
xcodebuild test-without-building -xctestrun "${PRODUCTS:-Build/device-acceptance-$dev/Products}/DeviceAcceptance_iphoneos27.2-arm64.xctestrun" \
  -destination "platform=iOS,id=$udid" -resultBundlePath "Build/device-acceptance-$dev/$name-$(date +%m%d%H%M%S).xcresult" \
  ${args[@]+"${args[@]}"} -test-timeouts-enabled YES -default-test-execution-time-allowance 600 \
  > "$log" 2>&1 &
xcb=$!
# Watchdog (2026-11-20): full run 12 waited two hours at "Waiting for the destination to become ready" after D2 left
# the network. A log that has not grown for 10 minutes while xcodebuild waits for its destination ends the run.
last_size=-1; still=0
while kill -0 "$xcb" 2>/dev/null; do
  sleep 30
  size=$(wc -c < "$log")
  if [ "$size" = "$last_size" ]; then still=$((still + 30)); else still=0; last_size=$size; fi
  if [ "$still" -ge 600 ] && tail -3 "$log" | grep -q "Waiting for the destination to become ready"; then
    echo "== $dev $name: DEVICE LOST: xcodebuild waited 10 minutes for $udid; stopping the run" | tee -a "$log"
    kill "$xcb" 2>/dev/null; sleep 5; kill -9 "$xcb" 2>/dev/null
    break
  fi
  # D1 rerun 5 (2026-11-23): the device's connection dropped while MED-014 set up its automation session ("The connection
  # was invalidated", Mercury error 1001); xcodebuild's diagnostics collection failed three minutes later and xcodebuild
  # then sat silent until it was interrupted by hand 13 minutes on. A connection error followed by 5 silent minutes, or
  # 15 silent minutes after anything (no test step is silent that long; a test's own limit is 600 s), ends the run.
  if { [ "$still" -ge 300 ] && tail -80 "$log" | grep -qE "connection was invalidated|Failure collecting diagnostics|Lost connection to"; } \
     || [ "$still" -ge 900 ]; then
    echo "== $dev $name: DEVICE LOST: the log has been silent for $((still / 60)) minutes after a lost connection or stall; stopping the run" | tee -a "$log"
    kill "$xcb" 2>/dev/null; sleep 5; kill -9 "$xcb" 2>/dev/null
    break
  fi
done
wait "$xcb" 2>/dev/null
[ -n "${driver:-}" ] && kill "$driver" 2>/dev/null
[ -n "${osc_driver:-}" ] && kill "$osc_driver" 2>/dev/null
# A REC-015/REC-009 disk ballast left by a stopped run fills the device (D3, 2026-11-24: 67 GB, and the next runs could not
# launch the test runner): clear it after every run (scripts/clear_disk_ballast.py; BALLAST=0 skips it).
if [ "${BALLAST:-1}" = 1 ]; then
  python3 scripts/clear_disk_ballast.py --device "$(echo "$dev" | tr a-z A-Z)" >> ".autonomous/logs/fixtures-$name-$dev.log" 2>&1 \
    || echo "== $dev $name: a disk ballast is still on the device (see fixtures-$name-$dev.log)"
fi
echo "== $dev $name: $(grep -cE 'Test Case.*passed' "$log") passed, $(grep -cE 'Test Case.*failed' "$log") failed, $(grep -cE 'Test Case.*skipped' "$log") skipped"
grep -E "Test Case.*failed" "$log" | sed 's/.*Tests\.//; s/\]. failed.*//' | sort -u
