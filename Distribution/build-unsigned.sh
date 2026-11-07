#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
artifact_dir="$project_root/Distribution/output"
if [ "$#" -gt 0 ]; then artifact_dir="$1"; fi
mkdir -p "$artifact_dir"
artifact_dir="$(cd "$artifact_dir" && pwd)"
xcodebuild -project "$project_root/Lumi.xcodeproj" -scheme Lumi \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$artifact_dir/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
  > "$artifact_dir/build.log" 2>&1
app_bundle="$artifact_dir/DerivedData/Build/Products/Release-iphoneos/Lumi.app"
test -d "$app_bundle"
executable=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app_bundle/Info.plist")
test -x "$app_bundle/$executable"
lipo "$app_bundle/$executable" -verify_arch arm64
extension_bundle="$app_bundle/PlugIns/LumiWidgets.appex"
test -d "$extension_bundle"
lipo "$extension_bundle/LumiWidgets" -verify_arch arm64
package_dir=$(mktemp -d "$artifact_dir/package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Payload"
ditto "$app_bundle" "$package_dir/Payload/Lumi.app"
ditto -c -k --keepParent "$package_dir/Payload" "$artifact_dir/Lumi-unsigned.ipa"
unzip -t "$artifact_dir/Lumi-unsigned.ipa" > "$artifact_dir/ipa-validation.txt"
(cd "$artifact_dir" && shasum -a 256 Lumi-unsigned.ipa) > "$artifact_dir/Lumi-unsigned.ipa.sha256"
printf 'Unsigned IPA: %s\n' "$artifact_dir/Lumi-unsigned.ipa"
