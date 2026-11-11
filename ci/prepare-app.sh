#!/bin/bash
set -euo pipefail

# Keep these exact inputs aligned with ios.yml and the development README.
mkdir -p build
test "$DEVELOPER_DIR" = /Applications/Xcode_27.2.app/Contents/Developer
test "$(uname -m)" = arm64
uname -m
{
  printf 'Developer directory: %s\n' "$DEVELOPER_DIR"
  printf 'Architecture: %s\n' "$(uname -m)"
  xcodebuild -version
  xcrun swift --version
  printf 'Simulator SDK: %s\n' "$(xcrun --sdk iphonesimulator --show-sdk-version)"
} > build/toolchain.txt
python3 ci/simulator.py verify-toolchain
xcodebuild -version | tee "$RUNNER_TEMP/xcode-version.txt"
grep -qx 'Xcode 27.2' "$RUNNER_TEMP/xcode-version.txt"
grep -qx 'Build version 27B52' "$RUNNER_TEMP/xcode-version.txt"
xcrun swift --version
xcodebuild -showsdks
xcrun --sdk iphonesimulator --show-sdk-version | grep -qx 27.2
printf 'Runner image: %s %s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}"

archive="$RUNNER_TEMP/xcodegen-2.46.0.zip"
curl --fail --location --retry 3 --output "$archive" \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
printf '%s  %s\n' 4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806 "$archive" | shasum -a 256 -c -
unzip -q "$archive" -d "$RUNNER_TEMP/xcodegen-2.46.0"
xcodegen="$RUNNER_TEMP/xcodegen-2.46.0/xcodegen/bin/xcodegen"
"$xcodegen" --version | grep -Fx 'Version: 2.46.0'

lock=DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
test -s "$lock" || { echo "::error::Committed Package.resolved is missing or empty"; exit 1; }
cp "$lock" "$RUNNER_TEMP/Package.resolved.expected"
cp ci/firebase-test-config.plist DailyWhiskers/Resources/GoogleService-Info.plist
"$xcodegen" generate
cmp "$lock" "$RUNNER_TEMP/Package.resolved.expected" || { echo "::error::XcodeGen changed Package.resolved"; exit 1; }

# Preview images do not promise a precreated 17 Pro. Exact compatibility must
# pass before creating an owned device; lifecycle evidence survives later failure.
python3 ci/simulator.py prepare
