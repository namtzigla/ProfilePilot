import AppKit

// ProfilePilot: registers as the default browser and routes every URL handed
// to it into the browser/profile you pick. Browsers come from
// ~/.config/profilepilot/config.json; with no config it falls back to Chrome
// and its profiles. Launched with no URL it offers setup actions instead.

// MARK: - Config file

struct BrowserEntry: Decodable {
    var name: String?        // display name; defaults to the app's name
    var app: String          // app name ("Google Chrome", "Safari") or a full .app path
    var profiles: Bool?      // enumerate Chromium profiles; defaults to true for known Chromium browsers
    var localState: String?  // override path to the Chromium "Local State" file
    var args: [String]?      // extra command-line args passed to the browser
}

struct Config: Decodable {
    var browsers: [BrowserEntry]
}

let defaultConfig = Config(browsers: [
    BrowserEntry(name: "Chrome", app: "Google Chrome", profiles: true, localState: nil, args: nil),
])

func configFileURL() -> URL {
    let env = ProcessInfo.processInfo.environment
    let base = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
    return base.appendingPathComponent("profilepilot/config.json")
}

func loadConfig() -> (config: Config, error: String?) {
    guard let data = try? Data(contentsOf: configFileURL()) else { return (defaultConfig, nil) }
    do { return (try JSONDecoder().decode(Config.self, from: data), nil) }
    catch { return (defaultConfig, error.localizedDescription) }
}

// MARK: - Browsers and profiles

let chromiumApps = ["Google Chrome", "Google Chrome Beta", "Google Chrome Canary",
                    "Brave Browser", "Microsoft Edge", "Chromium", "Vivaldi"]

let chromiumStateDirs: [String: String] = [
    "Google Chrome": "Google/Chrome",
    "Google Chrome Beta": "Google/Chrome Beta",
    "Google Chrome Canary": "Google/Chrome Canary",
    "Brave Browser": "BraveSoftware/Brave-Browser",
    "Microsoft Edge": "Microsoft Edge",
    "Chromium": "Chromium",
    "Vivaldi": "Vivaldi",
]

let shortBrowserNames: [String: String] = [
    "Google Chrome": "Chrome",
    "Google Chrome Beta": "Chrome Beta",
    "Google Chrome Canary": "Chrome Canary",
    "Brave Browser": "Brave",
    "Microsoft Edge": "Edge",
]

struct ChromeProfile {
    let directory: String
    let name: String
}

func loadProfiles(localState: String) -> [ChromeProfile] {
    guard let data = FileManager.default.contents(atPath: localState),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let profile = json["profile"] as? [String: Any],
          let cache = profile["info_cache"] as? [String: [String: Any]],
          !cache.isEmpty else {
        return []
    }
    // Last-used profile sorts first so it becomes the picker's default button.
    let lastUsed = (profile["last_used"] as? String) ?? ""
    return cache
        .map { dir, meta in ChromeProfile(directory: dir, name: (meta["name"] as? String) ?? dir) }
        .sorted { a, b in
            if a.directory == lastUsed { return true }
            if b.directory == lastUsed { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
}

func resolveAppPath(_ app: String) -> String? {
    if app.hasPrefix("/") || app.hasPrefix("~") {
        let path = NSString(string: app).expandingTildeInPath
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
    let candidates = [
        "/Applications/\(app).app",
        NSHomeDirectory() + "/Applications/\(app).app",
        "/System/Applications/\(app).app",
        "/System/Cryptexes/App/System/Applications/\(app).app",
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0) }
}

struct Target {
    let title: String
    let appPath: String
    let profileDirectory: String?
    let extraArgs: [String]
}

func buildTargets(_ config: Config) -> [Target] {
    var targets: [Target] = []
    for entry in config.browsers {
        guard let appPath = resolveAppPath(entry.app) else { continue }  // not installed
        let appBase = (entry.app as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let display = entry.name ?? shortBrowserNames[appBase] ?? appBase
        let statePath = entry.localState.map { NSString(string: $0).expandingTildeInPath }
            ?? chromiumStateDirs[appBase].map { NSHomeDirectory() + "/Library/Application Support/\($0)/Local State" }
        let wantProfiles = entry.profiles ?? (statePath != nil)
        let profiles = (wantProfiles && statePath != nil) ? loadProfiles(localState: statePath!) : []
        if profiles.count > 1 {
            for profile in profiles {
                targets.append(Target(title: "\(display) — \(profile.name)", appPath: appPath,
                                      profileDirectory: profile.directory, extraArgs: entry.args ?? []))
            }
        } else {
            targets.append(Target(title: display, appPath: appPath,
                                  profileDirectory: profiles.first?.directory, extraArgs: entry.args ?? []))
        }
    }
    return targets
}

func openTarget(_ target: Target, url: URL) {
    // `open -n` spawns a fresh browser process; a Chromium singleton lock
    // forwards --profile-directory and the URL to the running instance.
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    if target.profileDirectory != nil || !target.extraArgs.isEmpty {
        var args = ["-na", target.appPath, "--args"]
        if let dir = target.profileDirectory { args.append("--profile-directory=\(dir)") }
        args += target.extraArgs
        args.append(url.absoluteString)
        task.arguments = args
    } else {
        task.arguments = ["-a", target.appPath, url.absoluteString]
    }
    try? task.run()
    task.waitUntilExit()
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

// MARK: - Picker panel

enum PickResult {
    case open(Int)
    case copy
    case cancel
}

final class Picker: NSObject {
    private var result: PickResult = .cancel

    func run(url: URL, targets: [Target]) -> PickResult {
        let width: CGFloat = 344

        let title = NSTextField(labelWithString: "Open link with")
        title.font = .boldSystemFont(ofSize: 13)

        let urlLabel = NSTextField(labelWithString: url.absoluteString)
        urlLabel.font = .systemFont(ofSize: 11)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 16, bottom: 14, right: 16)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(urlLabel)
        stack.setCustomSpacing(12, after: urlLabel)
        urlLabel.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true

        for (index, target) in targets.enumerated() {
            let button = NSButton(title: target.title, target: self, action: #selector(choose(_:)))
            button.tag = index
            button.controlSize = .large
            let icon = NSWorkspace.shared.icon(forFile: target.appPath)
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.imagePosition = .imageLeading
            // Return opens the first (last-used) entry; 2–9 jump to the rest.
            button.keyEquivalent = index == 0 ? "\r" : (index < 9 ? "\(index + 1)" : "")
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            stack.addArrangedSubview(button)
        }
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)

        let copyButton = NSButton(title: "Copy Link", target: self, action: #selector(copyLink(_:)))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let bottom = NSStackView(views: [copyButton, cancelButton])
        bottom.orientation = .horizontal
        bottom.spacing = 8
        stack.addArrangedSubview(bottom)

        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(buttonType)?.isHidden = true
        }
        panel.contentView = stack
        panel.setContentSize(stack.fittingSize)
        panel.center()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return result
    }

    @objc private func choose(_ sender: NSButton) {
        result = .open(sender.tag)
        NSApp.stopModal()
    }

    @objc private func copyLink(_ sender: NSButton) {
        result = .copy
        NSApp.stopModal()
    }

    @objc private func cancel(_ sender: NSButton) {
        result = .cancel
        NSApp.stopModal()
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openedAnyURL = false
    private var reportedConfigError = false

    func application(_ application: NSApplication, open urls: [URL]) {
        openedAnyURL = true
        let (config, error) = loadConfig()
        if let error, !reportedConfigError {
            reportedConfigError = true
            let alert = NSAlert()
            alert.messageText = "ProfilePilot config error"
            alert.informativeText = "\(configFileURL().path)\n\n\(error)\n\nFalling back to Chrome profiles."
            alert.runModal()
        }
        let targets = promoteLastChoice(buildTargets(config))
        for url in urls {
            route(url, targets: targets)
        }
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // GetURL events arrive right after launch; if none shows up, the app
        // was opened by hand, so offer setup actions instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !self.openedAnyURL else { return }
            self.showSetup()
        }
    }

    private func route(_ url: URL, targets: [Target]) {
        NSApp.activate(ignoringOtherApps: true)
        guard !targets.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No browsers found"
            alert.informativeText = "None of the browsers in \(configFileURL().path) are installed."
            alert.runModal()
            return
        }
        if targets.count == 1 {
            openTarget(targets[0], url: url)
            return
        }
        switch Picker().run(url: url, targets: targets) {
        case .open(let index):
            UserDefaults.standard.set(targets[index].title, forKey: lastChoiceKey)
            openTarget(targets[index], url: url)
        case .copy:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.absoluteString, forType: .string)
        case .cancel:
            break
        }
    }

    private func isDefaultBrowser() -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "http://example.com")!) else {
            return false
        }
        return Bundle(url: url)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func showSetup() {
        NSApp.activate(ignoringOtherApps: true)
        let isDefault = isDefaultBrowser()
        let alert = NSAlert()
        alert.messageText = "ProfilePilot"
        alert.informativeText = (isDefault
            ? "ProfilePilot is your default browser. Links clicked in other apps show the browser picker."
            : "Set ProfilePilot as the default browser so links clicked in other apps show the browser picker.")
            + "\n\nConfig: \(configFileURL().path)"
        if !isDefault {
            alert.addButton(withTitle: "Set as Default")
        }
        alert.addButton(withTitle: "Open Config")
        alert.addButton(withTitle: "Quit")
        let response = alert.runModal()
        let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if !isDefault, response.rawValue == first {
            NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL,
                toOpenURLsWithScheme: "http"
            ) { _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return
        }
        if response.rawValue == (isDefault ? first : first + 1) {
            openConfigFile()
        }
        NSApp.terminate(nil)
    }

    private func openConfigFile() {
        let url = configFileURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            writeStarterConfig(to: url)
        }
        NSWorkspace.shared.open(url)
    }

    // Starter config listing the browsers actually installed on this machine.
    private func writeStarterConfig(to url: URL) {
        var browsers: [[String: Any]] = []
        for app in chromiumApps where resolveAppPath(app) != nil {
            browsers.append(["name": shortBrowserNames[app] ?? app, "app": app])
        }
        for app in ["Safari", "Firefox", "Arc", "Orion", "Zen"] where resolveAppPath(app) != nil {
            browsers.append(["app": app])
        }
        if browsers.isEmpty {
            browsers = [["name": "Chrome", "app": "Google Chrome"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["browsers": browsers],
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
