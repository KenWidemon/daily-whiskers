#!/bin/bash
set -euo pipefail

# Keep these exact inputs aligned with ios.yml and the development README.
test "$(uname -m)" = arm64
uname -m
xcodebuild -version | tee "$RUNNER_TEMP/xcode-version.txt"
grep -qx 'Xcode 26.6' "$RUNNER_TEMP/xcode-version.txt"
grep -qx 'Build version 17F113' "$RUNNER_TEMP/xcode-version.txt"
xcrun swift --version
xcodebuild -showsdks
xcrun --sdk iphonesimulator --show-sdk-version | grep -qx 26.5
printf 'Runner image: %s %s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}"

archive="$RUNNER_TEMP/xcodegen-2.46.0.zip"
curl --fail --location --retry 3 --output "$archive" \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
printf '%s  %s\n' 4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806 "$archive" | shasum -a 256 -c -
unzip -q "$archive" -d "$RUNNER_TEMP/xcodegen-2.46.0"
xcodegen="$RUNNER_TEMP/xcodegen-2.46.0/xcodegen/bin/xcodegen"
"$xcodegen" --version | grep -Fx 'Version: 2.46.0'

lock=DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
test -s "$lock"
cp "$lock" "$RUNNER_TEMP/Package.resolved.expected"
cp ci/firebase-test-config.plist DailyWhiskers/Resources/GoogleService-Info.plist
"$xcodegen" generate
cmp "$lock" "$RUNNER_TEMP/Package.resolved.expected"

# Select both runtime and device explicitly; never fall back to the first match.
xcrun simctl list devices available --json > "$RUNNER_TEMP/simulators.json"
python3 - <<'PY'
import json, os, subprocess
from pathlib import Path
data = json.loads((Path(os.environ['RUNNER_TEMP']) / 'simulators.json').read_text())
# Runtime identifiers can include the patch component; verify the OS via runtimes below.
runtimes = subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '--json'], text=True)
matches = [r['identifier'] for r in json.loads(runtimes)['runtimes'] if r.get('isAvailable') and r.get('version') == '26.4.1' and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
devices = [d for r in matches for d in data['devices'].get(r, []) if d['name'] == 'iPhone 17 Pro' and d.get('isAvailable')]
if len(devices) != 1:
    raise SystemExit(f'Expected exactly one available iPhone 17 Pro / iOS 26.4.1, found {len(devices)}')
print(f"Simulator: iPhone 17 Pro / iOS 26.4.1 / {devices[0]['udid']}")
with open(os.environ['GITHUB_ENV'], 'a') as output:
    output.write(f"SIMULATOR_ID={devices[0]['udid']}\n")
PY
