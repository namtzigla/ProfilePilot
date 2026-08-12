# ProfilePilot

A tiny app that registers itself as the default browser and, for every link
you click in any app, shows a picker of your browsers and profiles — so each
URL opens where it belongs (work, personal, client, …).

No dock icon, no background process: it wakes up when a link is clicked,
shows the picker, hands the URL off, and quits.

Two implementations share one config format:

| platform | where                        | UI                        |
| -------- | ---------------------------- | ------------------------- |
| macOS    | [`macos/`](macos/)           | AppKit (Swift)            |
| Linux    | [`linux/`](linux/)           | GTK 3 (Python, PyGObject) |

## Features

- **Any browser.** Manage the list in a graphical Settings window (macOS) or
  in a small JSON config; anything not installed is silently skipped.
- **Profile awareness.**
  - Chromium browsers (Chrome, Brave, Edge, Chromium, Vivaldi) get one picker
    entry per profile, read from their `Local State` file.
  - Firefox-family browsers get one entry per profile. Classic profiles come
    from `profiles.ini` (launched with `-P <name>`); with Firefox's newer
    profile manager (`StoreID=` in `profiles.ini`) the user-visible names are
    read from `Profile Groups/<storeid>.sqlite` and launched with
    `--profile <path>`. The last-used/default profile sorts first.
  - Safari (macOS only): profiles are enumerated from `SafariTabs.db`;
    opening clicks Safari's `File → New <Profile> Window` menu item via
    System Events and then sets the new window's URL. Needs **Automation**
    and **Accessibility** permissions on first use, plus access to Safari's
    data for the profile list. Without them, Safari falls back to a single
    entry / last-used profile.
- **Enable/disable and a default browser.** Each entry can be switched off
  without deleting it, and one browser can be marked as the default: its
  entries sort first so `Return`/`Enter` opens it.
- **Keyboard-first picker.** `Return` opens the top entry — the default
  browser if one is set, otherwise the entry you picked last time — `2`–`9`
  jump to the others, `Esc` cancels. Plus a **Copy Link** button.
- If only one target exists, the picker is skipped and the URL opens directly.

## macOS

Requires macOS 12+.

**With Xcode:** open `macos/ProfilePilot.xcodeproj` and build. The project is
generated from `macos/project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen && cd macos && xcodegen`) — regenerate after adding
files, don't edit the `.xcodeproj` by hand.

**Without Xcode** (just Command Line Tools + [fish](https://fishshell.com)):

```fish
./macos/build.fish
open ~/Applications/ProfilePilot.app
```

Launching the app by hand (no URL) opens the **Settings** window: the browser
table (On / icon / editable name / Default / Profiles columns), **+** to add
any installed http handler or `.app`, reorder arrows, **Set as Default
Browser**, and **Edit JSON…** for the advanced keys. On first run the table
is pre-seeded with every browser found on the machine.

## Linux

Requires Python 3, PyGObject (GTK 3), and `xdg-utils` — all standard on most
distros (Arch: `python-gobject gtk3 xdg-utils`).

```fish
./linux/install.fish
```

This installs `profilepilot` to `~/.local/bin`, a desktop entry + icon to
`~/.local/share`, and registers it as the default browser via `xdg-settings`.
Running `profilepilot` with no arguments prints the resolved picker entries;
`profilepilot --register` re-registers it as default. There is no settings
GUI on Linux yet — edit the JSON config (below). With no config, browsers are
auto-detected each run.

## Configuration file

`~/.config/profilepilot/config.json` (honors `XDG_CONFIG_HOME`) — shared by
both platforms; the macOS Settings window reads and writes this same file:

```json
{
  "browsers": [
    { "name": "Chrome", "app": "Google Chrome", "default": true },
    { "app": "Firefox" },
    { "app": "Safari" },
    { "name": "Work", "app": "Microsoft Edge", "profiles": false },
    { "app": "/Applications/Arc.app", "enabled": false }
  ]
}
```

On Linux, `app` is an executable name or path instead:
`"google-chrome-stable"`, `"firefox"`, `"/opt/zen/zen"`.

Each entry supports:

| key           | meaning                                                                   |
| ------------- | ------------------------------------------------------------------------- |
| `app`         | macOS: app name or `.app` path. Linux: executable name or path. Required.  |
| `name`        | Display name in the picker. Defaults to the app's (shortened) name.        |
| `profiles`    | Enumerate profiles. Defaults to `true` for known Chromium/Firefox apps.    |
| `localState`  | Override the path to a Chromium `Local State` file.                        |
| `profilesIni` | Override the path to a Firefox `profiles.ini` file.                        |
| `args`        | Extra command-line arguments passed to the browser.                        |
| `enabled`     | `false` hides the browser from the picker without deleting the entry.      |
| `default`     | `true` marks the default browser (at most one entry).                      |

Picker order follows config order, with two exceptions: the default browser's
entries always sort first, and when no default is set the entry you chose last
time moves to the top. Profiles sort last-used/default first.

## Icon

`macos/Resources/AppIcon.icns` and `linux/profilepilot.png` are generated by
`macos/icon/generate.swift`. To regenerate:

```fish
swift macos/icon/generate.swift /tmp/AppIcon.iconset
iconutil -c icns -o macos/Resources/AppIcon.icns /tmp/AppIcon.iconset
cp /tmp/AppIcon.iconset/icon_256x256.png linux/profilepilot.png
```

## Caveats

- Safari profile opening is menu-name based (`New <Profile> Window`), so it
  assumes an English UI language.
- Firefox: if a different profile is already running, Firefox's remoting
  usually forwards the URL; some setups may show a "Firefox is already
  running" complaint.
- The Linux app is functional but young — Flatpak/Snap browser paths aren't
  auto-detected yet (point `localState`/`profilesIni` at them manually).

## Roadmap

- Rules: route URLs to a target automatically by domain/pattern, only ask
  when no rule matches.
- Firefox containers as first-class targets.
- Non-browser targets (e.g. open Figma/Zoom/Linear links in their apps).
- Settings GUI on Linux.
