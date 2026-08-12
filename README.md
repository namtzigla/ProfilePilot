# ProfilePilot

A tiny macOS app that registers itself as the default browser and, for every
link you click in any app, shows a picker of your Chrome profiles — so each
URL opens in the profile it belongs to (work, personal, client, …).

No dock icon, no background process: it wakes up when a link is clicked,
shows the picker, hands the URL to Chrome, and quits.

## How it works

- Reads Chrome's `Local State` file to discover your profiles (the last-used
  profile is pre-selected as the default button).
- Presents a native alert with one button per profile.
- Launches the URL via `open -na "Google Chrome" --args --profile-directory=…`,
  which Chrome's singleton lock forwards to the running instance.

## Install

Requires macOS 12+ and Xcode command line tools (`swiftc`), plus
[fish](https://fishshell.com) for the build script.

```fish
./build.fish
open ~/Applications/ProfilePilot.app
```

On first manual launch it offers to set itself as the default browser.
After that, every http/https link you click anywhere shows the profile picker.

## Roadmap

The goal is to grow beyond Chrome profiles into a general profile dispatcher:

- Rules: route URLs to a profile automatically by domain/pattern, only ask
  when no rule matches.
- Other browsers (Firefox containers, Safari profiles) and per-profile apps.
- Keyboard-first picker (type-ahead, number keys).
