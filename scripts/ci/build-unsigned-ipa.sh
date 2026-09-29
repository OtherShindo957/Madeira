#!/bin/bash
# Package the source tree after bootstrap-native.sh completes.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This build step requires macOS and Xcode (use the GitHub Actions runner).' >&2
  exit 1
fi
python3 scripts/ci/check-ipa-inputs.py
bash tools/check-prefix-template.sh
command -v xcodebuild >/dev/null
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
out="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madeira-ipa.XXXXXX")"
artifact_dir="$PWD/artifacts"
mkdir -p "$artifact_dir"
# A target build avoids depending on an uncommitted/shared scheme.
xcodebuild -project app/Madeira.xcodeproj -target Madeira \
  -configuration Release -sdk iphoneos \
  "CONFIGURATION_BUILD_DIR=$out/products" "OBJROOT=$out/obj" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO IPHONEOS_DEPLOYMENT_TARGET=18.0 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  build 2>&1 | tee artifacts/xcodebuild.log
app="$out/products/Madeira.app"
test -s "$app/Info.plist"
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
test -s "$app/$executable"
xcrun lipo -verify_arch arm64 "$app/$executable"
mkdir "$out/Payload"
ditto "$app" "$out/Payload/Madeira.app"
(cd "$out" && /usr/bin/zip -qry "$artifact_dir/Madeira-unsigned.ipa" Payload)
unzip -t artifacts/Madeira-unsigned.ipa
shasum -a 256 artifacts/Madeira-unsigned.ipa > artifacts/Madeira-unsigned.ipa.sha256
cp app/Madeira/Madeira.entitlements artifacts/Madeira.entitlements
