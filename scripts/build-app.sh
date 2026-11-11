#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache/clang
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox -debug-info-format none -c release
app_dir="$PWD/.build/MouseQuickSwitch.app"
mkdir -p "$app_dir/Contents/MacOS"
cp .build/release/MouseQuickSwitch "$app_dir/Contents/MacOS/MouseQuickSwitch"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MouseQuickSwitch</string>
<key>CFBundleDisplayName</key><string>MouseQuickSwitch</string>
<key>CFBundleIdentifier</key><string>dev.mousequickswitch.app</string>
<key>CFBundleExecutable</key><string>MouseQuickSwitch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
echo "$app_dir"
