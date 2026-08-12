import AppKit

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
