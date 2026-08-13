#!/bin/sh
# Build ProfilePilot.app with swiftc and install it into ~/Applications.
# (No Xcode required; the Xcode project in this directory builds the same
# sources — regenerate it with `xcodegen` after changing project.yml.)
# Plain POSIX sh — run it with sh, bash, zsh, fish, anything.
set -eu
self=$0
# Resolve a symlinked script so the sources are still found next to it.
if command -v realpath >/dev/null 2>&1; then self=$(realpath "$0"); fi
src_dir=$(CDPATH= cd -- "$(dirname -- "$self")" && pwd -P)
app=$HOME/Applications/ProfilePilot.app
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -o "$app/Contents/MacOS/ProfilePilot" "$src_dir"/ProfilePilot/*.swift
cp "$src_dir/ProfilePilot/Info.plist" "$app/Contents/Info.plist"
cp "$src_dir/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
"$lsregister" -f "$app"

echo "Installed $app"
echo "Run 'open $app' once and click 'Set as Default' to make it the default browser."
