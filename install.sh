#!/bin/bash
# Build Kickoff.app, install it to ~/Applications, and schedule the 05:00 cleanup.
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Kickoff"
BUNDLE_ID="dev.kickoff.launcher"
APP="$HOME/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.cleanup.plist"

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

cat > "$BUILD/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
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

echo "==> Launching"
open "$APP"
echo "Done. Press your shortcut (default ⌃⌥⌘T) or click the folder icon in the menu bar."
