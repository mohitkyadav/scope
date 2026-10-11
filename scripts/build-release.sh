#!/bin/bash
# Builds a signed Release copy of Scope and zips it for a GitHub release.
#
#   scripts/build-release.sh <version>
#
# Signs with the "Scope Release" certificate (or $SIGNING_IDENTITY), from $SIGNING_KEYCHAIN if set.
# Prints the zip's path; its sha256 is written next to it.
set -euo pipefail

version=${1:?usage: scripts/build-release.sh <version>}
identity=${SIGNING_IDENTITY:-Scope Release}
root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/build/release
# Counting commits gives a build number that only goes up.
build_number=$(git -C "$root" rev-list --count HEAD)

rm -rf "$out"
mkdir -p "$out"

# Signed ad hoc first so Xcode adds the entitlements (sandbox, camera, microphone, Downloads),
# then signed again below with the release certificate.
xcodebuild -project "$root/Scope.xcodeproj" -scheme Scope -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$out/DerivedData" \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
    build -quiet >&2

app=$out/DerivedData/Build/Products/Release/Scope.app
codesign -d --entitlements - --xml "$app" > "$out/entitlements.plist" 2>/dev/null
# Ad hoc signing lets debuggers attach, which a release mustn't allow.
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$out/entitlements.plist" >/dev/null 2>&1 || true
for entitlement in app-sandbox device.camera device.audio-input files.downloads.read-write; do
    if ! grep -q "com.apple.security.$entitlement" "$out/entitlements.plist"; then
        echo "error: the build is missing the com.apple.security.$entitlement entitlement" >&2
        exit 1
    fi
done
codesign --force --options runtime --timestamp=none \
    --entitlements "$out/entitlements.plist" \
    --sign "$identity" ${SIGNING_KEYCHAIN:+--keychain "$SIGNING_KEYCHAIN"} \
    "$app" >&2
codesign --verify --strict "$app" >&2

zip=$out/Scope-$version.zip
ditto -c -k --keepParent "$app" "$zip"
shasum -a 256 "$zip" | cut -d ' ' -f 1 > "$zip.sha256"
echo "$zip"
