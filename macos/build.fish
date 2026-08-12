#!/usr/bin/env fish
# Build ProfilePilot.app with swiftc and install it into ~/Applications.
# (No Xcode required; the Xcode project in this directory builds the same
# sources — regenerate it with `xcodegen` after changing project.yml.)
set -l src_dir (dirname (realpath (status filename)))
set -l app ~/Applications/ProfilePilot.app

mkdir -p $app/Contents/MacOS $app/Contents/Resources
swiftc -O -o $app/Contents/MacOS/ProfilePilot $src_dir/ProfilePilot/*.swift; or exit 1
cp $src_dir/ProfilePilot/Info.plist $app/Contents/Info.plist
cp $src_dir/Resources/AppIcon.icns $app/Contents/Resources/AppIcon.icns
codesign --force --sign - $app; or exit 1
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $app

echo "Installed $app"
echo "Run 'open $app' once and click 'Set as Default' to make it the default browser."
