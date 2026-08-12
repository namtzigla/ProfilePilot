import Foundation

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

func starterEntries() -> [BrowserEntry] {
    let entries = installedBrowsers().map { url -> BrowserEntry in
        let app = canonicalApp(forPath: url.path)
        return BrowserEntry(name: shortBrowserNames[appBaseName(app)], app: app)
    }
    return entries.isEmpty ? defaultConfig.browsers : entries
}
