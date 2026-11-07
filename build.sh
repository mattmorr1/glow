#!/bin/bash
# Builds dist/Lid Glow.app and a release ZIP.
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)"  sign for distribution
#   NOTARY_PROFILE=name   also notarize and staple (create the profile once with
#                         xcrun notarytool store-credentials name)
set -euo pipefail
cd "$(dirname "$0")"

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
stage=$(mktemp -d "${TMPDIR:-/tmp}/lid-glow.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/Lid Glow.app"
archive="Lid-Glow-$version-macOS-arm64.zip"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist
cp Info.plist "$app/Contents/Info.plist"
cp AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

xcrun clang -arch arm64 -mmacosx-version-min=13.0 -O2 -Wall -Wextra -Werror -Wno-unused-parameter -fobjc-arc \
    -framework AppKit -framework IOKit -framework ServiceManagement MenuBar.m -o "$app/Contents/MacOS/LidGlow"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ -n "${DEVELOPER_ID:-}" ]] || { echo "NOTARY_PROFILE needs DEVELOPER_ID" >&2; exit 1; }
    ditto -c -k --keepParent "$app" "$stage/notarize.zip"
    xcrun notarytool submit "$stage/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    spctl --assess --type execute --verbose "$app"
fi

ditto -c -k --keepParent "$app" "$stage/$archive"
rm -rf "dist/Lid Glow.app"
ditto "$app" "dist/Lid Glow.app"
mv -f "$stage/$archive" "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
printf '%s\n' "dist/Lid Glow.app" "dist/$archive" "dist/$archive.sha256"
