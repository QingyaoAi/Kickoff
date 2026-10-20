#!/bin/bash
# Remove Kickoff, its cleanup schedule and its dsh plugin. Task folders are left untouched.
BUNDLE_ID="dev.kickoff.launcher"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.cleanup.plist"
DSH_PROFILE="${DSH_HOME:-$HOME/.dsh}/profiles/web"

pkill -x Kickoff 2>/dev/null
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null
rm -f "$PLIST"
rm -rf "$HOME/Applications/Kickoff.app"
defaults delete "$BUNDLE_ID" 2>/dev/null

rm -rf "$DSH_PROFILE/node_modules/dsh-kickoff"
if [ -f "$DSH_PROFILE/package.json" ] && command -v node >/dev/null; then
    node -e '
        const fs = require("fs"), file = process.argv[1]
        const pkg = JSON.parse(fs.readFileSync(file, "utf8"))
        const bundles = pkg.dsh?.profile?.bundles
        if (Array.isArray(bundles) && bundles.includes("dsh-kickoff")) {
            pkg.dsh.profile.bundles = bundles.filter(name => name !== "dsh-kickoff")
            fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + "\n")
        }' "$DSH_PROFILE/package.json"
fi
echo "Uninstalled."
