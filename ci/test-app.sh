#!/bin/bash
set -euo pipefail
mkdir -p build
lock=DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
package_path="$GITHUB_WORKSPACE/build/SourcePackages"
common=( -project DailyWhiskers.xcodeproj -scheme DailyWhiskers -configuration Debug
  -clonedSourcePackagesDirPath "$package_path" -onlyUsePackageVersionsFromResolvedFile
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO )

start=$(date +%s)
xcodebuild -resolvePackageDependencies "${common[@]}" 2>&1 | tee build/resolve.log
resolved=$(date +%s)
cmp "$lock" "$RUNNER_TEMP/Package.resolved.expected"
xcodebuild test "${common[@]}" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID,arch=arm64" \
  -derivedDataPath build/DerivedData -resultBundlePath build/TestResults.xcresult \
  -parallel-testing-enabled NO 2>&1 | tee build/xcodebuild.log
finished=$(date +%s)
cmp "$lock" "$RUNNER_TEMP/Package.resolved.expected"
{
  printf '| Measurement | Seconds |\n| --- | --- |\n'
  printf '| Dependency resolution | %s |\n' "$((resolved-start))"
  printf '| Build and unit tests | %s |\n' "$((finished-resolved))"
  printf '| Combined | %s |\n' "$((finished-start))"
} | tee build/timings.md >> "$GITHUB_STEP_SUMMARY"
