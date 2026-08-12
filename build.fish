#!/usr/bin/env fish
# Build ProfilePilot.app and install it into ~/Applications.
set -l src_dir (dirname (realpath (status filename)))
set -l app ~/Applications/ProfilePilot.app

mkdir -p $app/Contents/MacOS
swiftc -O -o $app/Contents/MacOS/ProfilePilot $src_dir/main.swift; or exit 1
cp $src_dir/Info.plist $app/Contents/Info.plist
codesign --force --sign - $app; or exit 1
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $app

echo "Installed $app"
echo "Run 'open $app' once and click 'Set as Default' to make it the default browser."
