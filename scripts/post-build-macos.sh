#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

bundle_id="com.krustykrab.petnote"
ios_simulator_app="build/ios/iphonesimulator/Runner.app"
ios_device_app="build/ios/iphoneos/Runner.app"
ios_unsigned_ipa="build/ios/Runner-unsigned.ipa"
android_apk="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"

log_step() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command flutter
require_command xcrun
require_command ditto
require_command cp

log_step "Build iOS simulator debug app"
flutter build ios --simulator --debug

log_step "Install app to booted simulator"
xcrun simctl install booted "$ios_simulator_app"

simulator_app_path=""
if simulator_app_path="$(xcrun simctl get_app_container booted "$bundle_id" app 2>/dev/null)"; then
  printf 'Installed simulator app: %s\n' "$simulator_app_path"
else
  echo "Warning: unable to resolve simulator app container path." >&2
fi

log_step "Build iOS release app without codesign"
flutter build ios --release --no-codesign

log_step "Package unsigned IPA"
if [[ ! -d "$ios_device_app" ]]; then
  echo "Missing built iOS release app at $ios_device_app" >&2
  exit 1
fi

tmpdir="$(mktemp -d /tmp/harmony-ipa.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/Payload"
rm -f "$ios_unsigned_ipa"
cp -R "$ios_device_app" "$tmpdir/Payload/Runner.app"
ditto -c -k --sequesterRsrc --keepParent "$tmpdir/Payload" "$ios_unsigned_ipa"

log_step "Build Android arm64-v8a release APK"
flutter build apk --release --target-platform android-arm64 --split-per-abi

printf '\nArtifacts:\n'
printf 'Simulator app: %s\n' "$ios_simulator_app"
if [[ -n "$simulator_app_path" ]]; then
  printf 'Installed path: %s\n' "$simulator_app_path"
fi
printf 'Unsigned IPA: %s\n' "$ios_unsigned_ipa"
printf 'Android APK: %s\n' "$android_apk"
