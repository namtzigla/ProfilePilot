import AppKit
import ApplicationServices

// MARK: - Targets: what the picker offers and how each one opens

struct Target {
    let title: String
    let appPath: String
    let profileDirectory: String?     // Chromium --profile-directory value
    let firefoxArgs: [String]?        // Firefox -P <name> or --profile <path>
    var safariProfile: String? = nil  // Safari profile name (opened via menu scripting)
    let extraArgs: [String]
}

func targets(for entry: BrowserEntry) -> [Target] {
    guard let appPath = resolveAppPath(entry.app) else { return [] }  // not installed
    let base = appBaseName(entry.app)
    let display = entry.name ?? shortBrowserNames[base] ?? base
    let extraArgs = entry.args ?? []
    let supportDir = NSHomeDirectory() + "/Library/Application Support/"
    let statePath = entry.localState.map { NSString(string: $0).expandingTildeInPath }
        ?? chromiumStateDirs[base].map { supportDir + $0 + "/Local State" }
    let iniPath = entry.profilesIni.map { NSString(string: $0).expandingTildeInPath }
        ?? firefoxIniDirs[base].map { supportDir + $0 + "/profiles.ini" }
    let isSafari = base == "Safari"
    let wantProfiles = entry.profiles ?? (statePath != nil || iniPath != nil || isSafari)

    if wantProfiles, isSafari {
        let profiles = loadSafariProfiles()
        if profiles.count > 1 {
            return profiles.map { profile in
                Target(title: "\(display) — \(profile.name)", appPath: appPath,
                       profileDirectory: nil, firefoxArgs: nil,
                       safariProfile: profile.name, extraArgs: extraArgs)
            }
        }
    }
    if wantProfiles, let statePath {
        let profiles = loadProfiles(localState: statePath)
        if profiles.count > 1 {
            return profiles.map { profile in
                Target(title: "\(display) — \(profile.name)", appPath: appPath,
                       profileDirectory: profile.directory, firefoxArgs: nil, extraArgs: extraArgs)
            }
        }
    }
    if wantProfiles, let iniPath {
        let profiles = loadFirefoxProfiles(profilesIni: iniPath)
        if profiles.count > 1 {
            return profiles.map { profile in
                Target(title: "\(display) — \(profile.name)", appPath: appPath,
                       profileDirectory: nil, firefoxArgs: profile.launchArgs, extraArgs: extraArgs)
            }
        }
    }
    return [Target(title: display, appPath: appPath,
                   profileDirectory: nil, firefoxArgs: nil, extraArgs: extraArgs)]
}

// The default browser's targets sort first; within a browser, profile order
// is last-used/default first, so Return always opens the default browser in
// its most recent profile.
func buildTargets(_ config: Config) -> [Target] {
    var defaultGroup: [Target] = []
    var rest: [Target] = []
    for entry in config.browsers where entry.enabled != false {
        let group = targets(for: entry)
        if entry.isDefault == true, defaultGroup.isEmpty {
            defaultGroup = group
        } else {
            rest += group
        }
    }
    return defaultGroup + rest
}

func hasDefaultBrowser(_ config: Config) -> Bool {
    config.browsers.contains {
        $0.isDefault == true && $0.enabled != false && resolveAppPath($0.app) != nil
    }
}

// The target picked last time is promoted to the top so Return repeats it.
let lastChoiceKey = "lastChoice"

func promoteLastChoice(_ targets: [Target]) -> [Target] {
    guard let last = UserDefaults.standard.string(forKey: lastChoiceKey),
          let index = targets.firstIndex(where: { $0.title == last }), index > 0 else { return targets }
    var reordered = targets
    reordered.insert(reordered.remove(at: index), at: 0)
    return reordered
}

// MARK: - Opening

func openTarget(_ target: Target, url: URL) {
    if let profile = target.safariProfile {
        openInSafariProfile(profile, appPath: target.appPath, url: url)
        return
    }
    // `open -n` spawns a fresh browser process; the browser's own remoting
    // (Chromium singleton lock, Firefox remote service) forwards the profile
    // flag and URL to the running instance.
    if target.profileDirectory != nil || target.firefoxArgs != nil || !target.extraArgs.isEmpty {
        var args = ["-na", target.appPath, "--args"]
        if let dir = target.profileDirectory { args.append("--profile-directory=\(dir)") }
        if let firefoxArgs = target.firefoxArgs { args += firefoxArgs }
        args += target.extraArgs
        args.append(url.absoluteString)
        runOpen(args)
    } else {
        runOpen(["-a", target.appPath, url.absoluteString])
    }
}

func runOpen(_ arguments: [String]) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = arguments
    try? task.run()
    task.waitUntilExit()
}

// MARK: - Safari profile launching

func appleScriptString(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

// Safari has no CLI or scripting interface for profiles, so the profile
// window is opened by clicking Safari's File > "New <Profile> Window" menu
// item via System Events (this needs Accessibility + Automation permission),
// then pointing the new front window at the URL.
func openInSafariProfile(_ profileName: String, appPath: String, url: URL) {
    guard AXIsProcessTrusted() else {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        let alert = NSAlert()
        alert.messageText = "Accessibility permission needed"
        alert.informativeText = """
        Opening a specific Safari profile works by clicking Safari's File menu, \
        which needs Accessibility access.

        Grant it to ProfilePilot in System Settings → Privacy & Security → \
        Accessibility, then click your link again. Opening Safari's last-used \
        profile for now.
        """
        alert.runModal()
        runOpen(["-a", appPath, url.absoluteString])
        return
    }
    let script = """
    tell application "Safari" to activate
    tell application "System Events"
        repeat 25 times
            try
                click menu item \(appleScriptString("New \(profileName) Window")) of menu "File" of menu bar item "File" of menu bar 1 of process "Safari"
                exit repeat
            on error
                delay 0.3
            end try
        end repeat
    end tell
    delay 0.3
    tell application "Safari"
        repeat 25 times
            try
                set URL of current tab of front window to \(appleScriptString(url.absoluteString))
                exit repeat
            on error
                delay 0.3
            end try
        end repeat
    end tell
    """
    var error: NSDictionary?
    NSAppleScript(source: script)?.executeAndReturnError(&error)
    if error != nil {
        runOpen(["-a", appPath, url.absoluteString])
    }
}
