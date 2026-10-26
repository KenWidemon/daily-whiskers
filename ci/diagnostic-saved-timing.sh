#!/bin/bash
# Temporary, synthetic-only diagnostic; never a promotion/release gate.
set -euo pipefail
mkdir -p build
xcrun simctl list devices available --json > build/diagnostic-simulators.json
sim_state=$(python3 -c 'import json,os; d=json.load(open("build/diagnostic-simulators.json")); print(next(x["state"] for devices in d["devices"].values() for x in devices if x["udid"]==os.environ["SIMULATOR_ID"]))')
if [ "$sim_state" != Booted ]; then xcrun simctl boot "$SIMULATOR_ID"; fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl spawn "$SIMULATOR_ID" log stream --style ndjson --level info \
  --predicate 'subsystem == "com.dailywhiskers.saved-timing"' \
  > build/saved-timing.jsonl 2> build/saved-timing-stream.log &
stream_pid=$!
trap 'kill "$stream_pid" 2>/dev/null || true; wait "$stream_pid" 2>/dev/null || true' EXIT
sleep 1
kill -0 "$stream_pid" || { echo 'Diagnostic log stream did not start'; exit 1; }
set +e
xcodebuild test -project DailyWhiskers.xcodeproj \
  -clonedSourcePackagesDirPath "$GITHUB_WORKSPACE/build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
  -scheme DailyWhiskersInteraction -configuration Debug \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING SAVED_TIMING_DIAGNOSTIC' \
  -only-testing:DailyWhiskersUITests/SavedCardsTests/testOrdinaryPortraitCardFitsWithoutScrolling \
  -only-testing:DailyWhiskersUITests/SavedCardsTests/testSaveRelaunchReopenShareRemoveAndConfirmedClear \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID,arch=arm64" \
  -derivedDataPath build/SmokeDerivedData -resultBundlePath build/SavedTiming.xcresult \
  -parallel-testing-enabled NO 2>&1 | tee build/diagnostic-ui.log
test_status=${PIPESTATUS[0]}
set -e
printf '%s\n' "$test_status" > build/diagnostic-exit-code.txt
xcrun xcresulttool get test-results summary --path build/SavedTiming.xcresult > build/diagnostic-results.json
cmp DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved "$RUNNER_TEMP/Package.resolved.expected"
test -s build/saved-timing.jsonl || { echo 'No native timing events captured'; exit 1; }
exit "$test_status"
