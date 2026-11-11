#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

signed=false
if [[ -n "${CODESIGN_IDENTITY:-}" || -n "${NOTARY_PROFILE:-}" ]]; then
    if [[ -z "${CODESIGN_IDENTITY:-}" || -z "${NOTARY_PROFILE:-}" ]]; then
        echo "Set both CODESIGN_IDENTITY (Developer ID Application) and NOTARY_PROFILE, or neither for a local preview." >&2
        exit 2
    fi
    signed=true
fi

./scripts/build-app.sh
app_dir="$PWD/.build/MouseQuickSwitch.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")

if [[ "$signed" == true ]]; then
    if ! codesign -dv --verbose=4 "$app_dir" 2>&1 | grep -q '^Authority=Developer ID Application:'; then
        echo "The app is not signed with a Developer ID Application certificate." >&2
        exit 2
    fi
    dmg="$PWD/.build/MouseQuickSwitch-$version-PENDING-NOTARIZATION.dmg"
    release_dmg="$PWD/.build/MouseQuickSwitch-$version.dmg"
else
    dmg="$PWD/.build/MouseQuickSwitch-$version-UNNOTARIZED-PREVIEW.dmg"
fi

staging=$(mktemp -d "${TMPDIR:-/private/tmp}/mousequickswitch-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app_dir" "$staging/MouseQuickSwitch.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname MouseQuickSwitch -srcfolder "$staging" -ov -format UDZO "$dmg"

if [[ "$signed" == true ]]; then
    result="$PWD/.build/notary-result.json"
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$result"
    python3 - "$result" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    result = json.load(stream)
if result.get('status') != 'Accepted':
    raise SystemExit(f"Notarization failed: {result.get('status', 'unknown status')}")
PY
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    mv -f "$dmg" "$release_dmg"
    dmg="$release_dmg"
else
    echo "Created a local preview only. An ad-hoc signed DMG is not suitable for general public installation." >&2
fi
shasum -a 256 "$dmg" > "$dmg.sha256"
echo "$dmg"
