#!/bin/sh
# Install ProfilePilot for Linux: script to ~/.local/bin, desktop entry and
# icon to ~/.local/share, then register it as the default browser.
# Plain POSIX sh — run it with sh, bash, zsh, fish, anything.
set -eu
self=$0
# Resolve a symlinked script so the sources are still found next to it.
if command -v realpath >/dev/null 2>&1; then self=$(realpath "$0"); fi
src_dir=$(CDPATH= cd -- "$(dirname -- "$self")" && pwd -P)
bin_dir=$HOME/.local/bin
apps_dir=$HOME/.local/share/applications
icon_dir=$HOME/.local/share/icons/hicolor/256x256/apps

mkdir -p "$bin_dir" "$apps_dir" "$icon_dir"
cp "$src_dir/profilepilot" "$bin_dir/profilepilot"
chmod +x "$bin_dir/profilepilot"
# Absolute Exec path so the desktop entry works even if ~/.local/bin is not
# on the session PATH.
sed "s|^Exec=profilepilot|Exec=$bin_dir/profilepilot|" \
    "$src_dir/profilepilot.desktop" > "$apps_dir/profilepilot.desktop"
cp "$src_dir/profilepilot.png" "$icon_dir/profilepilot.png"

update-desktop-database "$apps_dir" 2>/dev/null || true

# The picker needs one of GTK 3 / GTK 4 / Qt; --list reports the one it picked.
if "$bin_dir/profilepilot" --list 2>/dev/null | grep -q '^toolkit: none'; then
    echo "Warning: no GTK or Qt toolkit found — links will still open, but in the"
    echo "first browser instead of showing the picker. Install PyGObject (Arch:"
    echo "python-gobject gtk4, Debian/Ubuntu: python3-gi gir1.2-gtk-4.0) or Qt for"
    echo "Python (Arch: python-pyqt6, Debian/Ubuntu: python3-pyqt6)."
fi

if xdg-settings set default-web-browser profilepilot.desktop; then
    echo "Installed. Links now show the ProfilePilot picker."
else
    echo "Installed, but registering as default browser failed — run: xdg-settings set default-web-browser profilepilot.desktop"
fi
