#!/bin/bash
# run_device.sh <d1|d2|d3> <log name> <filter>... : xcodebuild test-without-building on one device, each filter its own
# argument (bash arrays; zsh does not split an unquoted $VAR). Filters: "only:<id>" or "skip:<id>". With MAC_DRIVER=1 the
# Mac driver follows the log.
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
if [ "${MAC_DRIVER:-0}" = 1 ]; then
  python3 scripts/mac_device_driver.py follow --log "$log" --device "$(echo "$dev" | tr a-z A-Z)" > ".autonomous/logs/macdriver-$name-$dev.log" 2>&1 &
  driver=$!
fi
xcodebuild test-without-building -xctestrun "Build/device-acceptance-$dev/Products/DeviceAcceptance_iphoneos27.2-arm64.xctestrun" \
  -destination "platform=iOS,id=$udid" -resultBundlePath "Build/device-acceptance-$dev/$name-$(date +%m%d%H%M%S).xcresult" \
  ${args[@]+"${args[@]}"} -test-timeouts-enabled YES -default-test-execution-time-allowance 600 \
  TEST_RUNNER_MAC_DRIVER="${MAC_DRIVER:-0}" > "$log" 2>&1
[ -n "${driver:-}" ] && kill "$driver" 2>/dev/null
echo "== $dev $name: $(grep -cE 'Test Case.*passed' "$log") passed, $(grep -cE 'Test Case.*failed' "$log") failed, $(grep -cE 'Test Case.*skipped' "$log") skipped"
grep -E "Test Case.*failed" "$log" | sed 's/.*Tests\.//; s/\]. failed.*//' | sort -u
