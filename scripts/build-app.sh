#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
module_cache="${TMPDIR:-/private/tmp}/mousequickswitch-clang-cache"
mkdir -p "$module_cache"
export CLANG_MODULE_CACHE_PATH="$module_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$module_cache"
for arch in arm64 x86_64; do
    swift build --disable-sandbox -debug-info-format none -c release \
        --triple "$arch-apple-macosx13.0" --scratch-path "build/$arch"
done
app_dir="$PWD/build/MouseQuickSwitch.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp Assets/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
xcrun lipo -create \
    build/arm64/release/MouseQuickSwitch \
    build/x86_64/release/MouseQuickSwitch \
    -output "$app_dir/Contents/MacOS/MouseQuickSwitch"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MouseQuickSwitch</string>
<key>CFBundleDisplayName</key><string>MouseQuickSwitch</string>
<key>CFBundleIdentifier</key><string>dev.mousequickswitch.app</string>
<key>CFBundleExecutable</key><string>MouseQuickSwitch</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.1</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app_dir"
else
    codesign --force --sign - "$app_dir"
fi
echo "$app_dir"
