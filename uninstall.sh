#!/bin/bash
# Remove Kickoff, its cleanup schedule and its dsh plugin. Task folders are left untouched.
BUNDLE_ID="dev.kickoff.launcher"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.cleanup.plist"
DSH_DESKTOP_PROFILE="${DSH_HOME:-$HOME/.dsh}/profiles/desktop"
DSH_DESKTOP_CLI="/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh"
if [ ! -x "$DSH_DESKTOP_CLI" ]; then
    DSH_DESKTOP_CLI="$HOME/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh"
fi

if [ -x "$DSH_DESKTOP_CLI" ] && [ "$DSH_DESKTOP_PROFILE/node_modules/dsh-kickoff" -ef "$HOME/Applications/Kickoff.app/Contents/Resources/dsh-kickoff" ]; then
    "$DSH_DESKTOP_CLI" plugin --profile desktop remove --offline dsh-kickoff || exit 1
fi

pkill -x Kickoff 2>/dev/null
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null
rm -f "$PLIST"
rm -rf "$HOME/Applications/Kickoff.app"
rm -rf "$HOME/Library/Application Support/$BUNDLE_ID/DeepSeek"
defaults delete "$BUNDLE_ID" 2>/dev/null

echo "Uninstalled."
