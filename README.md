# ProfilePilot

A tiny macOS app that registers itself as the default browser and, for every
link you click in any app, shows a picker of your browsers and profiles — so
each URL opens where it belongs (work, personal, client, …).

No dock icon, no background process: it wakes up when a link is clicked,
shows the picker, hands the URL off, and quits.

## Features

- **Any browser, not just Chrome.** Manage the list in a graphical Settings
  window or in a small JSON config; anything not installed is silently skipped.
- **Profile awareness.**
  - Chromium browsers (Chrome, Brave, Edge, Chromium, Vivaldi) get one picker
    entry per profile, read from their `Local State` file.
  - Firefox-family browsers (Firefox, Dev Edition, Nightly, Zen, LibreWolf,
    Waterfox) get one entry per profile. Classic profiles come from
    `profiles.ini` (launched with `-P <name>`); with Firefox's newer profile
    manager (`StoreID=` in `profiles.ini`) the user-visible names are read
    from `Profile Groups/<storeid>.sqlite` and launched with
    `--profile <path>`. The last-used/default profile sorts first.
  - Safari profiles are enumerated from `SafariTabs.db` (each profile row's
    title; the default profile is "Personal"). Apple provides no launch API,
    so opening clicks Safari's `File → New <Profile> Window` menu item via
    System Events and then sets the new window's URL. This needs two
    permissions on first use: **Automation** (macOS prompts automatically)
    and **Accessibility** (ProfilePilot triggers the prompt; grant in System
    Settings → Privacy & Security → Accessibility). Reading the profile list
    also needs access to Safari's data (macOS may prompt, or grant Full Disk
    Access). Without these, Safari falls back to a single picker entry /
    last-used profile.
- **Enable/disable and a default browser.** Each entry can be switched off
  without deleting it, and one browser can be marked as the default: its
  entries sort first in the picker so `Return` opens it (in its most recent
  profile).
- **Keyboard-first picker.** `Return` opens the top entry — the default
  browser if one is set, otherwise the entry you picked last time — and
  `2`–`9` jump to the others, `Esc` cancels.
- **Copy Link** button for when you don't want to open the URL at all.
- If only one target exists, the picker is skipped and the URL opens directly.

## Install

Requires macOS 12+ and Xcode command line tools (`swiftc`), plus
[fish](https://fishshell.com) for the build script.

```fish
./build.fish
open ~/Applications/ProfilePilot.app
```

## Settings

Launching the app by hand (no URL) opens the **Settings** window:

- A table of your browsers: an **On** checkbox (show/hide in the picker
  without deleting), icon, editable display name, a **Default** checkbox
  (single-select — the default browser sorts first so `Return` opens it), and
  a per-browser **Profiles** checkbox (enabled for Chromium/Firefox browsers).
- **+** adds a browser from a menu of every app on your machine registered as
  an http handler (or **Other…** to pick any `.app`); **−** removes; the
  arrows reorder the picker.
- **Set as Default Browser** registers ProfilePilot as the system default.
- **Save** writes the JSON config; **Edit JSON…** opens it in your editor for
  the advanced options below.
- On first run the table is pre-seeded with every browser found on the machine.

## Configuration file

`~/.config/profilepilot/config.json` (honors `XDG_CONFIG_HOME`) — the
Settings window reads and writes this same file:

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

Each entry supports:

| key           | meaning                                                                   |
| ------------- | ------------------------------------------------------------------------- |
| `app`         | App name (`"Safari"`, `"Google Chrome"`) or a full `.app` path. Required.  |
| `name`        | Display name in the picker. Defaults to the app's (shortened) name.        |
| `profiles`    | Enumerate profiles. Defaults to `true` for known Chromium/Firefox apps.    |
| `localState`  | Override the path to a Chromium `Local State` file.                        |
| `profilesIni` | Override the path to a Firefox `profiles.ini` file.                        |
| `args`        | Extra command-line arguments passed to the browser.                        |
| `enabled`     | `false` hides the browser from the picker without deleting the entry.      |
| `default`     | `true` marks the default browser (at most one entry).                      |

Picker order follows config order, with two exceptions: the default browser's
entries always sort first, and when no default is set the entry you chose last
time moves to the top (so `Return` repeats it). Profiles sort
last-used/default first.

## Icon

`Resources/AppIcon.icns` is generated by `icon/generate.swift`. To regenerate:

```fish
swift icon/generate.swift /tmp/AppIcon.iconset
iconutil -c icns -o Resources/AppIcon.icns /tmp/AppIcon.iconset
```

## Caveats

- Safari profile opening is menu-name based (`New <Profile> Window`), so it
  assumes an English UI language.
- Firefox: if a different profile is already running, Firefox's remoting
  usually forwards the URL; some setups may show a "Firefox is already
  running" complaint.

## Roadmap

- Rules: route URLs to a target automatically by domain/pattern, only ask
  when no rule matches.
- Firefox containers as first-class targets (needs the Open external links in
  a container extension).
- Non-browser targets (e.g. open Figma/Zoom/Linear links in their apps).
