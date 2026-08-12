import AppKit
import UniformTypeIdentifiers

// ProfilePilot: registers as the default browser and routes every URL handed
// to it into the browser/profile you pick. Browsers come from
// ~/.config/profilepilot/config.json; with no config it falls back to Chrome
// and its profiles. Launched with no URL it opens the Settings window.

// MARK: - Config file

struct BrowserEntry: Codable {
    var name: String?        // display name; defaults to the app's name
    var app: String          // app name ("Google Chrome", "Safari") or a full .app path
    var profiles: Bool?      // enumerate profiles; defaults to true for known Chromium/Firefox browsers
    var localState: String?  // override path to the Chromium "Local State" file
    var profilesIni: String? // override path to the Firefox "profiles.ini" file
    var args: [String]?      // extra command-line args passed to the browser
    var enabled: Bool?       // false hides the browser from the picker without deleting it
    var isDefault: Bool?     // the default browser: its entries sort first, Return opens it

    enum CodingKeys: String, CodingKey {
        case name, app, profiles, localState, profilesIni, args, enabled
        case isDefault = "default"
    }

    init(name: String? = nil, app: String, profiles: Bool? = nil, localState: String? = nil,
         profilesIni: String? = nil, args: [String]? = nil, enabled: Bool? = nil, isDefault: Bool? = nil) {
        self.name = name
        self.app = app
        self.profiles = profiles
        self.localState = localState
        self.profilesIni = profilesIni
        self.args = args
        self.enabled = enabled
        self.isDefault = isDefault
    }
}

struct Config: Codable {
    var browsers: [BrowserEntry]
}

let defaultConfig = Config(browsers: [
    BrowserEntry(name: "Chrome", app: "Google Chrome", profiles: true),
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

@discardableResult
func writeConfig(_ entries: [BrowserEntry]) -> Bool {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(Config(browsers: entries)) else { return false }
    let url = configFileURL()
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    return (try? data.write(to: url)) != nil
}

// MARK: - Browsers and profiles

let chromiumStateDirs: [String: String] = [
    "Google Chrome": "Google/Chrome",
    "Google Chrome Beta": "Google/Chrome Beta",
    "Google Chrome Canary": "Google/Chrome Canary",
    "Brave Browser": "BraveSoftware/Brave-Browser",
    "Microsoft Edge": "Microsoft Edge",
    "Chromium": "Chromium",
    "Vivaldi": "Vivaldi",
]

// Firefox-family browsers keep their profiles in a profiles.ini under
// ~/Library/Application Support/<dir>/.
let firefoxIniDirs: [String: String] = [
    "Firefox": "Firefox",
    "Firefox Developer Edition": "Firefox",
    "Firefox Nightly": "Firefox",
    "Zen": "zen",
    "LibreWolf": "librewolf",
    "Waterfox": "Waterfox",
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

// Firefox profile names from profiles.ini, default profile first. The
// default is the profile an [Install*] section points at (or Default=1).
func loadFirefoxProfiles(profilesIni: String) -> [String] {
    guard let text = try? String(contentsOfFile: profilesIni, encoding: .utf8) else { return [] }
    var profiles: [(name: String, path: String, isDefault: Bool)] = []
    var installDefaultPath: String?
    var section = ""
    var current: (name: String?, path: String?, isDefault: Bool) = (nil, nil, false)
    func flush() {
        if section.hasPrefix("Profile"), let name = current.name {
            profiles.append((name, current.path ?? "", current.isDefault))
        }
        current = (nil, nil, false)
    }
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("[") {
            flush()
            section = String(line.dropFirst().dropLast())
        } else if let eq = line.firstIndex(of: "=") {
            let key = String(line[..<eq])
            let value = String(line[line.index(after: eq)...])
            if section.hasPrefix("Profile") {
                switch key {
                case "Name": current.name = value
                case "Path": current.path = value
                case "Default": current.isDefault = value == "1"
                default: break
                }
            } else if section.hasPrefix("Install"), key == "Default" {
                installDefaultPath = value
            }
        }
    }
    flush()
    return profiles
        .sorted { a, b in
            let aDefault = a.path == installDefaultPath || a.isDefault
            let bDefault = b.path == installDefaultPath || b.isDefault
            if aDefault != bDefault { return aDefault }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        .map { $0.name }
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

func appBaseName(_ app: String) -> String {
    (app as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
}

func isProfileCapable(_ entry: BrowserEntry) -> Bool {
    let base = appBaseName(entry.app)
    return entry.localState != nil || entry.profilesIni != nil
        || chromiumStateDirs[base] != nil || firefoxIniDirs[base] != nil
}

func isDefaultBrowser() -> Bool {
    guard let http = URL(string: "http://example.com"),
          let url = NSWorkspace.shared.urlForApplication(toOpen: http) else {
        return false
    }
    return Bundle(url: url)?.bundleIdentifier == Bundle.main.bundleIdentifier
}

// Every app registered as an http handler, minus ProfilePilot itself.
func installedBrowsers() -> [URL] {
    guard let http = URL(string: "http://example.com") else { return [] }
    let own = Bundle.main.bundleIdentifier
    return NSWorkspace.shared.urlsForApplications(toOpen: http)
        .filter { Bundle(url: $0)?.bundleIdentifier != own }
}

// Prefer the bare app name when it resolves back to the same bundle.
func canonicalApp(forPath path: String) -> String {
    let base = appBaseName(path)
    return resolveAppPath(base) == path ? base : path
}

func starterEntries() -> [BrowserEntry] {
    let entries = installedBrowsers().map { url -> BrowserEntry in
        let app = canonicalApp(forPath: url.path)
        return BrowserEntry(name: shortBrowserNames[appBaseName(app)], app: app)
    }
    return entries.isEmpty ? defaultConfig.browsers : entries
}

struct Target {
    let title: String
    let appPath: String
    let profileDirectory: String?  // Chromium --profile-directory value
    let firefoxProfile: String?    // Firefox -P profile name
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
    let wantProfiles = entry.profiles ?? (statePath != nil || iniPath != nil)

    if wantProfiles, let statePath {
        let profiles = loadProfiles(localState: statePath)
        if profiles.count > 1 {
            return profiles.map { profile in
                Target(title: "\(display) — \(profile.name)", appPath: appPath,
                       profileDirectory: profile.directory, firefoxProfile: nil, extraArgs: extraArgs)
            }
        }
    }
    if wantProfiles, let iniPath {
        let profiles = loadFirefoxProfiles(profilesIni: iniPath)
        if profiles.count > 1 {
            return profiles.map { profile in
                Target(title: "\(display) — \(profile)", appPath: appPath,
                       profileDirectory: nil, firefoxProfile: profile, extraArgs: extraArgs)
            }
        }
    }
    return [Target(title: display, appPath: appPath,
                   profileDirectory: nil, firefoxProfile: nil, extraArgs: extraArgs)]
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

func openTarget(_ target: Target, url: URL) {
    // `open -n` spawns a fresh browser process; the browser's own remoting
    // (Chromium singleton lock, Firefox remote service) forwards the profile
    // flag and URL to the running instance.
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    if target.profileDirectory != nil || target.firefoxProfile != nil || !target.extraArgs.isEmpty {
        var args = ["-na", target.appPath, "--args"]
        if let dir = target.profileDirectory { args.append("--profile-directory=\(dir)") }
        if let profile = target.firefoxProfile { args += ["-P", profile] }
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

// MARK: - Settings window

final class SettingsController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                                NSWindowDelegate, NSTextFieldDelegate {
    private var entries: [BrowserEntry]
    private let window: NSWindow
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let defaultButton = NSButton(title: "Set as Default Browser", target: nil, action: nil)
    private let removeButton = NSButton(title: "", target: nil, action: nil)
    private let upButton = NSButton(title: "", target: nil, action: nil)
    private let downButton = NSButton(title: "", target: nil, action: nil)

    override init() {
        // First run (no config yet) seeds the list with every installed browser.
        if FileManager.default.fileExists(atPath: configFileURL().path) {
            entries = loadConfig().config.browsers
        } else {
            entries = starterEntries()
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 460),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "ProfilePilot Settings"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = buildContent()
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        refreshDefaultStatus()
        refreshSelectionButtons()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    // MARK: Layout

    private func buildContent() -> NSView {
        let contentWidth: CGFloat = 540

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.widthAnchor.constraint(equalToConstant: 44).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let title = NSTextField(labelWithString: "ProfilePilot")
        title.font = .boldSystemFont(ofSize: 15)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, statusLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        defaultButton.target = self
        defaultButton.action = #selector(setDefault(_:))
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 10
        header.addView(iconView, in: .leading)
        header.addView(titleStack, in: .leading)
        header.addView(defaultButton, in: .trailing)
        header.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        let browsersLabel = NSTextField(labelWithString: "Browsers shown in the picker")
        browsersLabel.font = .boldSystemFont(ofSize: 12)

        for (identifier, columnTitle, width) in [("enabled", "On", 30.0),
                                                 ("browser", "Browser", 185.0),
                                                 ("name", "Display Name", 145.0),
                                                 ("default", "Default", 55.0),
                                                 ("profiles", "Profiles", 55.0)] {
            let column = NSTableColumn(identifier: .init(identifier))
            column.title = columnTitle
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.rowHeight = 26
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true

        let addButton = NSButton(title: "", target: self, action: #selector(addClicked(_:)))
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add browser")
        removeButton.target = self
        removeButton.action = #selector(removeSelected(_:))
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove browser")
        upButton.target = self
        upButton.action = #selector(moveUp(_:))
        upButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Move up")
        downButton.target = self
        downButton.action = #selector(moveDown(_:))
        downButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Move down")

        let listButtons = NSStackView()
        listButtons.orientation = .horizontal
        listButtons.spacing = 6
        listButtons.addView(addButton, in: .leading)
        listButtons.addView(removeButton, in: .leading)
        listButtons.addView(upButton, in: .leading)
        listButtons.addView(downButton, in: .leading)
        listButtons.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        let hint = NSTextField(labelWithString:
            "On shows or hides a browser without deleting it. Default sorts that browser first so Return opens it; with no default, the picker remembers your last pick. Chromium and Firefox browsers expand into one entry per profile (Safari has no public profile API). Extra args and custom profile paths live in the JSON.")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = contentWidth
        hint.widthAnchor.constraint(lessThanOrEqualToConstant: contentWidth).isActive = true

        let editJSONButton = NSButton(title: "Edit JSON…", target: self, action: #selector(editJSON(_:)))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        saveButton.keyEquivalent = "\r"
        let bottom = NSStackView()
        bottom.orientation = .horizontal
        bottom.spacing = 8
        bottom.addView(editJSONButton, in: .leading)
        bottom.addView(cancelButton, in: .trailing)
        bottom.addView(saveButton, in: .trailing)
        bottom.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(makeSeparator(width: contentWidth))
        stack.addArrangedSubview(browsersLabel)
        stack.addArrangedSubview(scroll)
        stack.addArrangedSubview(listButtons)
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(14, after: hint)
        stack.addArrangedSubview(bottom)
        return stack
    }

    private func makeSeparator(width: CGFloat) -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: width).isActive = true
        return box
    }

    private func refreshDefaultStatus() {
        let isDefault = isDefaultBrowser()
        statusLabel.stringValue = isDefault
            ? "ProfilePilot is your default browser."
            : "Not the default browser — links won't reach the picker yet."
        defaultButton.isHidden = isDefault
    }

    private func refreshSelectionButtons() {
        let row = tableView.selectedRow
        removeButton.isEnabled = row >= 0
        upButton.isEnabled = row > 0
        downButton.isEnabled = row >= 0 && row < entries.count - 1
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        switch tableColumn?.identifier.rawValue {
        case "enabled":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
            checkbox.state = entry.enabled != false ? .on : .off
            checkbox.toolTip = "Show this browser in the picker"
            return checkbox
        case "browser":
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: appBaseName(entry.app))
            let imageView = NSImageView()
            if resolveAppPath(entry.app) == nil {
                label.textColor = .disabledControlTextColor
                label.toolTip = "Not installed — skipped in the picker"
            } else if let path = resolveAppPath(entry.app) {
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 18, height: 18)
                imageView.image = icon
                if entry.enabled == false {
                    label.textColor = .disabledControlTextColor
                }
            }
            let cellStack = NSStackView(views: [imageView, label])
            cellStack.orientation = .horizontal
            cellStack.spacing = 6
            cellStack.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(cellStack)
            NSLayoutConstraint.activate([
                cellStack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                cellStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                cellStack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            ])
            return cell
        case "name":
            let field = NSTextField(string: entry.name ?? "")
            field.placeholderString = shortBrowserNames[appBaseName(entry.app)] ?? appBaseName(entry.app)
            field.isBordered = false
            field.drawsBackground = false
            field.usesSingleLineMode = true
            field.lineBreakMode = .byTruncatingTail
            field.delegate = self
            return field
        case "default":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleDefault(_:)))
            checkbox.state = entry.isDefault == true ? .on : .off
            checkbox.toolTip = "Default browser: sorts first in the picker so Return opens it. Uncheck to fall back to remembering your last pick."
            return checkbox
        case "profiles":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleProfiles(_:)))
            let capable = isProfileCapable(entry)
            checkbox.state = (entry.profiles ?? capable) ? .on : .off
            checkbox.isEnabled = capable
            checkbox.toolTip = capable ? "Show one entry per browser profile"
                                       : "Profile listing is only supported for Chromium and Firefox browsers"
            return checkbox
        default:
            return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshSelectionButtons()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = tableView.row(for: field)
        guard row >= 0, row < entries.count else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespaces)
        entries[row].name = value.isEmpty ? nil : value
    }

    @objc private func toggleProfiles(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0, row < entries.count else { return }
        entries[row].profiles = sender.state == .on
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0, row < entries.count else { return }
        entries[row].enabled = sender.state == .on ? nil : false
        reload(selecting: tableView.selectedRow)
    }

    // Behaves like a radio group, except unchecking the current default is
    // allowed (no default → the picker remembers the last choice instead).
    @objc private func toggleDefault(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0, row < entries.count else { return }
        let makeDefault = sender.state == .on
        for index in entries.indices {
            entries[index].isDefault = nil
        }
        if makeDefault {
            entries[row].isDefault = true
        }
        reload(selecting: tableView.selectedRow)
    }

    // MARK: List actions

    private func reload(selecting row: Int?) {
        window.makeFirstResponder(nil)
        tableView.reloadData()
        if let row, row >= 0, row < entries.count {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        refreshSelectionButtons()
    }

    @objc private func addClicked(_ sender: NSButton) {
        let menu = NSMenu()
        let configured = Set(entries.compactMap { resolveAppPath($0.app) })
        for url in installedBrowsers() where !configured.contains(url.path) {
            let item = NSMenuItem(title: appBaseName(url.path), action: #selector(addBrowser(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let other = NSMenuItem(title: "Other…", action: #selector(addOther(_:)), keyEquivalent: "")
        other.target = self
        menu.addItem(other)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func addBrowser(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        appendEntry(forPath: path)
    }

    @objc private func addOther(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appendEntry(forPath: url.path)
    }

    private func appendEntry(forPath path: String) {
        let app = canonicalApp(forPath: path)
        entries.append(BrowserEntry(name: shortBrowserNames[appBaseName(app)], app: app))
        reload(selecting: entries.count - 1)
    }

    @objc private func removeSelected(_ sender: NSButton) {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return }
        window.makeFirstResponder(nil)
        entries.remove(at: row)
        reload(selecting: min(row, entries.count - 1))
    }

    @objc private func moveUp(_ sender: NSButton) {
        let row = tableView.selectedRow
        guard row > 0 else { return }
        window.makeFirstResponder(nil)
        entries.swapAt(row, row - 1)
        reload(selecting: row - 1)
    }

    @objc private func moveDown(_ sender: NSButton) {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count - 1 else { return }
        window.makeFirstResponder(nil)
        entries.swapAt(row, row + 1)
        reload(selecting: row + 1)
    }

    // MARK: Footer actions

    @objc private func setDefault(_ sender: NSButton) {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpenURLsWithScheme: "http"
        ) { _ in
            DispatchQueue.main.async { self.refreshDefaultStatus() }
        }
    }

    @objc private func editJSON(_ sender: NSButton) {
        let url = configFileURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            writeConfig(entries)
        }
        NSWorkspace.shared.open(url)
        window.close()
    }

    @objc private func save(_ sender: NSButton) {
        window.makeFirstResponder(nil)  // commit any in-progress name edit
        if !writeConfig(entries) {
            let alert = NSAlert()
            alert.messageText = "Could not save config"
            alert.informativeText = configFileURL().path
            alert.runModal()
            return
        }
        window.close()
    }

    @objc private func cancel(_ sender: NSButton) {
        window.close()
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openedAnyURL = false
    private var reportedConfigError = false
    private var settings: SettingsController?

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
        // An explicit default browser owns the top spot; otherwise the last
        // picked target is promoted so Return repeats it.
        var targets = buildTargets(config)
        if !hasDefaultBrowser(config) {
            targets = promoteLastChoice(targets)
        }
        for url in urls {
            route(url, targets: targets)
        }
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // GetURL events arrive right after launch; if none shows up, the app
        // was opened by hand, so show the Settings window instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !self.openedAnyURL else { return }
            self.settings = SettingsController()
            self.settings?.show()
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
}

// A minimal main menu so Cmd+Q/W and text editing shortcuts work in the
// Settings window (LSUIElement apps get no menu for free).
func makeMainMenu() -> NSMenu {
    let main = NSMenu()

    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(NSMenuItem(title: "Quit ProfilePilot",
                               action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appItem.submenu = appMenu
    main.addItem(appItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
    editMenu.addItem(.separator())
    editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editItem.submenu = editMenu
    main.addItem(editItem)

    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(NSMenuItem(title: "Close Window",
                                  action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    windowItem.submenu = windowMenu
    main.addItem(windowItem)

    return main
}

let app = NSApplication.shared
app.mainMenu = makeMainMenu()
let delegate = AppDelegate()
app.delegate = delegate
app.run()
