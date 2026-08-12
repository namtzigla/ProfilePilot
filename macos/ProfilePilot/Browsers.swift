import AppKit
import SQLite3

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

// Firefox profiles come in two flavors. Classic profiles are fully described
// by profiles.ini (Name=, launched with -P <name>). The newer profile
// manager (StoreID= in profiles.ini) keeps the user-visible names in
// Profile Groups/<storeid>.sqlite — the profiles.ini names go stale — and
// those are launched with --profile <absolute path>. The last-used/default
// profile (the [Install*] section's Default= path) sorts first.
struct FirefoxProfile {
    let name: String
    let launchArgs: [String]
}

func loadFirefoxProfiles(profilesIni: String) -> [FirefoxProfile] {
    guard let text = try? String(contentsOfFile: profilesIni, encoding: .utf8) else { return [] }
    let baseDir = (profilesIni as NSString).deletingLastPathComponent
    var iniProfiles: [(name: String, path: String, isDefault: Bool)] = []
    var installDefaultPath: String?
    var storeIDs: [String] = []
    var section = ""
    var current: (name: String?, path: String?, isDefault: Bool) = (nil, nil, false)
    func flush() {
        if section.hasPrefix("Profile"), let name = current.name {
            iniProfiles.append((name, current.path ?? "", current.isDefault))
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
                case "StoreID": if !storeIDs.contains(value) { storeIDs.append(value) }
                default: break
                }
            } else if section.hasPrefix("Install"), key == "Default" {
                installDefaultPath = value
            }
        }
    }
    flush()

    for storeID in storeIDs {
        let stored = loadFirefoxProfileGroup(
            dbPath: baseDir + "/Profile Groups/\(storeID).sqlite",
            baseDir: baseDir, defaultPath: installDefaultPath)
        if !stored.isEmpty { return stored }
    }

    return iniProfiles
        .sorted { a, b in
            let aDefault = a.path == installDefaultPath || a.isDefault
            let bDefault = b.path == installDefaultPath || b.isDefault
            if aDefault != bDefault { return aDefault }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        .map { FirefoxProfile(name: $0.name, launchArgs: ["-P", $0.name]) }
}

func loadFirefoxProfileGroup(dbPath: String, baseDir: String, defaultPath: String?) -> [FirefoxProfile] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        sqlite3_close(db)
        return []
    }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT name, path FROM Profiles ORDER BY id;",
                             -1, &statement, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(statement) }
    var profiles: [(name: String, path: String)] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        let name = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        let path = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
        if !name.isEmpty { profiles.append((name, path)) }
    }
    let defaults = profiles.filter { $0.path == defaultPath }
    let others = profiles.filter { $0.path != defaultPath }
    return (defaults + others).map { profile in
        let absolute = profile.path.hasPrefix("/") ? profile.path : baseDir + "/" + profile.path
        return FirefoxProfile(name: profile.name, launchArgs: ["--profile", absolute])
    }
}

// Safari profiles from SafariTabs.db: each profile is a bookmarks row with
// type=1, subtype=2; the default profile has an empty title and is shown as
// "Personal" in Safari's UI. Reading the db needs access to Safari's
// container (macOS prompts, or grant Full Disk Access); an unreadable db
// just means Safari stays a single picker entry.
struct SafariProfile {
    let name: String
    let uuid: String
}

func loadSafariProfiles() -> [SafariProfile] {
    let path = NSHomeDirectory() + "/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db"
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        sqlite3_close(db)
        return []
    }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    let sql = "SELECT title, external_uuid FROM bookmarks WHERE type = 1 AND subtype = 2 ORDER BY id;"
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(statement) }
    var profiles: [SafariProfile] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        let title = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        let uuid = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
        profiles.append(SafariProfile(name: title.isEmpty ? "Personal" : title, uuid: uuid))
    }
    return profiles
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
        || base == "Safari"
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
