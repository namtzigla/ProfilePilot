import AppKit

// ProfilePilot: registers as the default browser, and for every URL handed to it
// shows a picker listing the Chrome profiles found in Local State, then hands
// the URL to the chosen profile. Launched with no URL, it offers to make
// itself the default browser.

struct ChromeProfile {
    let directory: String
    let name: String
}

func loadProfiles() -> [ChromeProfile] {
    let path = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Local State"
    guard let data = FileManager.default.contents(atPath: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let profile = json["profile"] as? [String: Any],
          let cache = profile["info_cache"] as? [String: [String: Any]],
          !cache.isEmpty else {
        return [ChromeProfile(directory: "Default", name: "Default")]
    }
    // Last-used profile sorts first so it is the alert's default (Return) button.
    let lastUsed = (profile["last_used"] as? String) ?? ""
    return cache
        .map { dir, meta in ChromeProfile(directory: dir, name: (meta["name"] as? String) ?? dir) }
        .sorted { a, b in
            if a.directory == lastUsed { return true }
            if b.directory == lastUsed { return false }
            return a.directory < b.directory
        }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openedAnyURL = false

    func application(_ application: NSApplication, open urls: [URL]) {
        openedAnyURL = true
        let profiles = loadProfiles()
        for url in urls {
            route(url, profiles: profiles)
        }
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // GetURL events arrive right after launch; if none shows up, the app
        // was opened by hand, so offer to become the default browser instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !self.openedAnyURL else { return }
            self.offerToBecomeDefaultBrowser()
        }
    }

    private func route(_ url: URL, profiles: [ChromeProfile]) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Open in which Chrome profile?"
        alert.informativeText = url.absoluteString
        for profile in profiles {
            alert.addButton(withTitle: profile.name)
        }
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        let response = alert.runModal()
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard index >= 0, index < profiles.count else { return }
        openInChrome(url, profileDirectory: profiles[index].directory)
    }

    private func openInChrome(_ url: URL, profileDirectory: String) {
        // `open -n` spawns a fresh Chrome process; Chrome's singleton lock
        // forwards --profile-directory and the URL to the running instance.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-na", "Google Chrome", "--args",
                          "--profile-directory=\(profileDirectory)", url.absoluteString]
        try? task.run()
        task.waitUntilExit()
    }

    private func offerToBecomeDefaultBrowser() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Set ProfilePilot as the default browser?"
        alert.informativeText = "Links clicked in other apps will then show a Chrome profile picker."
        alert.addButton(withTitle: "Set as Default")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL,
                toOpenURLsWithScheme: "http"
            ) { _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return
        }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
