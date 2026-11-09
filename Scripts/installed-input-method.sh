#!/bin/sh
# The input method installed in DIR (~/Library/Input Methods): the app there with the bundle ID ID, whatever its folder's
# name (0.7.2 installed it as AllInOneIME.app; 0.7.1.1's move and new installs as AllInOneIME Input.app), that one first
# when there are several, as `Updater.installedInputMethod` (Sources/AllInOneIMEMac/UpdateInstall.swift) finds it. With
# --new: DIR/AllInOneIME Input.app, where a new install goes, when there is none; without, nothing (exit 1).
# Usage: Scripts/installed-input-method.sh [--new] DIR ID
set -u
new=false
[ "${1:-}" = --new ] && { new=true; shift; }
dir=$1 id=$2
for app in "$dir/AllInOneIME Input.app" "$dir"/*.app; do
    [ -d "$app" ] || continue
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)" = "$id" ] \
        && { echo "$app"; exit 0; }
done
$new && { echo "$dir/AllInOneIME Input.app"; exit 0; }
exit 1
