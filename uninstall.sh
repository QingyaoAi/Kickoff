#!/bin/bash
# Remove Kickoff and its cleanup schedule. Task folders are left untouched.
BUNDLE_ID="com.aqy.kickoff"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.cleanup.plist"

pkill -x Kickoff 2>/dev/null
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null
rm -f "$PLIST"
rm -rf "$HOME/Applications/Kickoff.app"
defaults delete "$BUNDLE_ID" 2>/dev/null
echo "Uninstalled."
