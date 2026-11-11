#!/bin/bash
set -euo pipefail
mkdir -p build
lock=DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
package_path="$GITHUB_WORKSPACE/build/SourcePackages"
common=( -project DailyWhiskers.xcodeproj
  -clonedSourcePackagesDirPath "$package_path" -onlyUsePackageVersionsFromResolvedFile
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO )
case "${1:?Specify resolve, unit, ui or release}" in
  resolve)
    xcodebuild -resolvePackageDependencies "${common[@]}" -scheme DailyWhiskers
    ;;
  unit)
    xcodebuild test "${common[@]}" -scheme DailyWhiskers -configuration Debug \
      -destination "platform=iOS Simulator,id=$SIMULATOR_ID,arch=arm64" \
      -derivedDataPath build/DerivedData -resultBundlePath build/TestResults.xcresult \
      -parallel-testing-enabled NO
    ;;
  ui)
    # Capture the selector command's failure before invoking Xcode (no process
    # substitution, which would hide an inventory failure from set -e).
    python3 ci/ui_shards.py selectors --shard "${CI_PART:?Select the required UI shard}" > build/ui-selectors.txt
    selectors=()
    while IFS= read -r selector; do selectors+=("$selector"); done < build/ui-selectors.txt
    xcodebuild test "${common[@]}" -scheme DailyWhiskersInteraction -configuration Debug \
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CI_SMOKE_TESTING' \
      "${selectors[@]}" \
      -destination "platform=iOS Simulator,id=$SIMULATOR_ID,arch=arm64" \
      -derivedDataPath build/SmokeDerivedData -resultBundlePath "build/SmokeResults-$CI_PART.xcresult" \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 720 \
      -maximum-test-execution-time-allowance 720 \
      -parallel-testing-enabled NO
    ;;
  release)
    # Compile/package for a generic simulator; no signing, archive, upload or CI seam.
    xcodebuild build "${common[@]}" -scheme DailyWhiskers -configuration Release \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ReleaseDerivedData
    python3 ci/check-release.py build/ReleaseDerivedData/Build/Products/Release-iphonesimulator/DailyWhiskers.app/DailyWhiskers
    ;;
  *) echo 'Unknown app validation stage' >&2; exit 2 ;;
esac
cmp "$lock" "$RUNNER_TEMP/Package.resolved.expected" || { echo "::error::Dependency lock changed during validation"; exit 1; }
