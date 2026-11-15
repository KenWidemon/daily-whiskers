#!/bin/bash
set -euo pipefail
selector='-only-testing:DailyWhiskersUITests/SavedCardsTests/testLargestTextPairedGeometryAndOptions'
printf '%s\n' "$selector" > build/toolbar-selector.txt
xcodebuild test -project DailyWhiskers.xcodeproj -scheme DailyWhiskersInteraction \
  -configuration Debug -clonedSourcePackagesDirPath "$PWD/build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING' \
  "$selector" -destination "platform=iOS Simulator,id=$SIMULATOR_ID,arch=arm64" \
  -derivedDataPath build/SmokeDerivedData -resultBundlePath build/ToolbarPair.xcresult \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 720 \
  -maximum-test-execution-time-allowance 720 -parallel-testing-enabled NO
cmp DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved "$RUNNER_TEMP/Package.resolved.expected"
