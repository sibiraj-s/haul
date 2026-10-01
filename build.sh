#!/usr/bin/env bash
# Builds a Release of Haul (Apple Silicon) and packages it as build/Haul-<version>.dmg.
#
#   ./build.sh            version from the latest v* tag (fails if there is none)
#   ./build.sh 1.2.0      explicit version
#
# The app is signed ad hoc; Gatekeeper will ask users to approve it on first launch.
set -euo pipefail
cd "$(dirname "$0")"

version="${1:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)}"
if [[ -z "$version" ]]; then
    echo "error: no v* tag found; tag a release (git tag v1.0.0) or pass a version: ./build.sh 1.0.0" >&2
    exit 1
fi
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "error: version must look like 1.2.3 (got '$version')" >&2
    exit 1
fi

out=build
app="$out/DerivedData/Build/Products/Release/Haul.app"
stage="$out/dmg"
dmg="$out/Haul-$version.dmg"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Built copies register with LaunchServices under the app's bundle ID; leftover ones can
# make the Dock show the wrong (blank) icon for the installed Haul.
unregister() {
    for copy in "$app" "$stage/Haul.app"; do
        [[ -e "$copy" ]] && "$lsregister" -u "$PWD/$copy" 2>/dev/null || true
    done
}
trap unregister EXIT

echo "==> Building Haul $version"
rm -rf "$stage" "$dmg"
xcodebuild -project haul.xcodeproj -scheme Haul -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$out/DerivedData" \
    ARCHS=arm64 \
    CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    MARKETING_VERSION="$version" \
    -quiet build

echo "==> Verifying"
plist="$PWD/$app/Contents/Info.plist"
[[ "$(defaults read "$plist" CFBundleShortVersionString)" == "$version" ]] || { echo "error: version mismatch" >&2; exit 1; }
[[ "$(lipo -archs "$app/Contents/MacOS/Haul")" == "arm64" ]] || { echo "error: expected an arm64-only binary" >&2; exit 1; }
codesign --verify --deep --strict "$app"
if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q get-task-allow; then
    echo "error: debug entitlement (get-task-allow) in the release build" >&2
    exit 1
fi

echo "==> Packaging $dmg"
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Haul -srcfolder "$stage" -format UDZO -ov "$dmg" -quiet
hdiutil verify "$dmg" -quiet
unregister
rm -rf "$stage"

echo "==> Done: $dmg ($(du -h "$dmg" | cut -f1))"
