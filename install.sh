#!/bin/bash
# Build Kickoff.app, install it to ~/Applications, schedule the 05:00 cleanup,
# and install the dsh-kickoff plugin for DeepSeek Harness Desktop.
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Kickoff"
BUNDLE_ID="dev.kickoff.launcher"
APP="$HOME/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.cleanup.plist"
DSH_ROOT="${DSH_HOME:-$HOME/.dsh}"
DSH_DESKTOP_PROFILE="$DSH_ROOT/profiles/desktop"
DSH_DESKTOP_CLI="/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh"
if [ ! -x "$DSH_DESKTOP_CLI" ]; then
    DSH_DESKTOP_CLI="$HOME/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh"
fi

echo "==> Building"
BUILD="build/$APP_NAME.app"
rm -rf build
mkdir -p "$BUILD/Contents/MacOS"
for ARCH in arm64 x86_64; do   # universal binary: Apple Silicon + Intel
    swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" \
        -framework Cocoa -framework Carbon -framework ServiceManagement \
        Sources/main.swift -o "build/$APP_NAME-$ARCH"
done
lipo -create "build/$APP_NAME-arm64" "build/$APP_NAME-x86_64" -output "$BUILD/Contents/MacOS/$APP_NAME"

ICONSET="build/AppIcon.iconset"   # every size iconutil expects, scaled from the 1024px master
mkdir -p "$ICONSET" "$BUILD/Contents/Resources"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" Resources/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    sips -z "$((SIZE * 2))" "$((SIZE * 2))" Resources/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/Contents/Resources/AppIcon.icns"
cp -R dsh-plugin "$BUILD/Contents/Resources/dsh-kickoff"

cat > "$BUILD/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.4</string>
    <key>CFBundleVersion</key><string>5</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$BUILD"

echo "==> Installing to $APP"
pkill -x "$APP_NAME" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
cp -R "$BUILD" "$APP"

echo "==> Scheduling daily cleanup at 05:00"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BUNDLE_ID.cleanup</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/$APP_NAME</string>
        <string>--cleanup</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>5</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>StandardOutPath</key><string>/tmp/$APP_NAME-cleanup.log</string>
    <key>StandardErrorPath</key><string>/tmp/$APP_NAME-cleanup.log</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

# Retire the plugin copied into the Web profile by earlier Kickoff installers.
LEGACY_WEB_PROFILE="$DSH_ROOT/profiles/web"
if [ -f "$LEGACY_WEB_PROFILE/package.json" ] && command -v node >/dev/null; then
    node - "$LEGACY_WEB_PROFILE" <<'JS'
const fs = require('node:fs')
const { join } = require('node:path')
const profile = process.argv[2]
const file = join(profile, 'package.json')
const pkg = JSON.parse(fs.readFileSync(file, 'utf8'))
const bundles = pkg.dsh?.profile?.bundles
if (Array.isArray(bundles) && bundles.includes('dsh-kickoff')) {
    pkg.dsh.profile.bundles = bundles.filter(name => name !== 'dsh-kickoff')
    const temporary = file + '.kickoff-' + process.pid
    fs.writeFileSync(temporary, JSON.stringify(pkg, null, 2) + '\n', { mode: fs.statSync(file).mode & 0o777 })
    fs.renameSync(temporary, file)
    console.log('==> Disabled the legacy Kickoff plugin in the Web profile')
}
if (!pkg.dependencies?.['dsh-kickoff']) {
    fs.rmSync(join(profile, 'node_modules/dsh-kickoff'), { recursive: true, force: true })
}
JS
fi
rm -f "$DSH_ROOT/kickoff-web-url"

if [ -x "$DSH_DESKTOP_CLI" ] && [ -f "$DSH_DESKTOP_PROFILE/package.json" ]; then
    echo "==> Installing the dsh-kickoff plugin for DeepSeek Harness Desktop"
    if "$DSH_DESKTOP_CLI" plugin --profile desktop add --offline --ignore-scripts "link:$APP/Contents/Resources/dsh-kickoff"; then
        echo "    Reopen DeepSeek Harness to load the plugin."
    else
        echo "    Desktop plugin setup failed. Quit DeepSeek Harness and rerun ./install.sh." >&2
    fi
else
    echo "==> Open and quit DeepSeek Harness Desktop once, then rerun ./install.sh to enable its shortcut."
fi

echo "==> Launching"
open "$APP"
echo "Done. Default shortcuts are ⌃⌥⌘T for VS Code, ⌥D for DeepSeek Harness, and ⌥C for Codex."
