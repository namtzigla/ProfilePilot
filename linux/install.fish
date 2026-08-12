#!/usr/bin/env fish
# Install ProfilePilot for Linux: script to ~/.local/bin, desktop entry and
# icon to ~/.local/share, then register it as the default browser.
set -l src_dir (dirname (realpath (status filename)))

mkdir -p ~/.local/bin ~/.local/share/applications ~/.local/share/icons/hicolor/256x256/apps
cp $src_dir/profilepilot ~/.local/bin/profilepilot
chmod +x ~/.local/bin/profilepilot
# Absolute Exec path so the desktop entry works even if ~/.local/bin is not
# on the session PATH.
sed "s|^Exec=profilepilot|Exec=$HOME/.local/bin/profilepilot|" \
    $src_dir/profilepilot.desktop > ~/.local/share/applications/profilepilot.desktop
cp $src_dir/profilepilot.png ~/.local/share/icons/hicolor/256x256/apps/profilepilot.png

update-desktop-database ~/.local/share/applications 2>/dev/null
xdg-settings set default-web-browser profilepilot.desktop
and echo "Installed. Links now show the ProfilePilot picker."
or echo "Installed, but registering as default browser failed — run: xdg-settings set default-web-browser profilepilot.desktop"
