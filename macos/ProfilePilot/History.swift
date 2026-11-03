import Foundation

// MARK: - Per-site history
//
// Every pick is remembered against the URL it opened, so the next link to
// the same site (or the same part of it) comes up with that browser/profile
// already on top of the picker. The store is a small JSON file shared in
// format with the Linux app:
//
//   { "github.com/namtzigla/profilepilot": { "title": "Chrome — Personal",
//                                            "used": 1762183215 }, ... }
//
// Lookup is fuzzy: a stored key matches when at least two host labels line
// up from the right (gist.github.com matches github.com), and once the host
// matches in full, leading path segments add to the match. The longest
// match wins; ties go to the most recently used entry.

let historyLimit = 1000

struct HistoryEntry: Codable {
    var title: String
    var used: Double
}

func historyFileURL() -> URL {
    let env = ProcessInfo.processInfo.environment
    let base = env["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
    return base.appendingPathComponent("profilepilot/history.json")
}

func loadHistory() -> [String: HistoryEntry] {
    guard let data = try? Data(contentsOf: historyFileURL()),
          let history = try? JSONDecoder().decode([String: HistoryEntry].self, from: data) else {
        return [:]
    }
    return history
}

func saveHistory(_ history: [String: HistoryEntry]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(history) else { return }
    let url = historyFileURL()
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
}

// "https://www.GitHub.com:443/Namtzigla/ProfilePilot/?tab=x#y"
//   -> "github.com/namtzigla/profilepilot"
// Scheme, port, query, fragment, a leading "www." and letter case are all
// dropped so that variations of the same link land on the same key. URLs
// without a host (file:, mailto:) are not remembered.
func historyKey(for url: URL) -> String? {
    guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
    if host.hasPrefix("www."), host.count > 4 { host.removeFirst(4) }
    let segments = url.path.lowercased().split(separator: "/").filter { !$0.isEmpty }
    return segments.isEmpty ? host : host + "/" + segments.joined(separator: "/")
}

private func splitKey(_ key: String) -> (host: [Substring], path: [Substring]) {
    let parts = key.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    let host = parts[0].split(separator: ".")
    let path = parts.count > 1 ? parts[1].split(separator: "/") : []
    return (host, path)
}

// Number of characters of `key` that `stored` matches, 0 for no match.
func historyMatchScore(stored: String, key: String) -> Int {
    let a = splitKey(stored)
    let b = splitKey(key)
    var labels = 0
    var score = 0
    for (x, y) in zip(a.host.reversed(), b.host.reversed()) {
        guard x == y else { break }
        labels += 1
        score += x.count
    }
    // Two labels are the least that identify a site; single-label hosts
    // (localhost, intranet names) must match in full.
    let required = min(2, a.host.count, b.host.count)
    guard labels >= required, labels > 0 else { return 0 }
    score += labels - 1  // the dots
    guard labels == a.host.count, labels == b.host.count else { return score }
    for (x, y) in zip(a.path, b.path) {
        guard x == y else { break }
        score += x.count + 1  // the slash
    }
    return score
}

// The title remembered for the closest stored key, if any of `titles` is.
func historyMatch(for url: URL, among titles: [String], history: [String: HistoryEntry]) -> String? {
    guard let key = historyKey(for: url) else { return nil }
    var best: (score: Int, used: Double, title: String)?
    for (stored, entry) in history where titles.contains(entry.title) {
        let score = historyMatchScore(stored: stored, key: key)
        guard score > 0 else { continue }
        if let current = best, (current.score, current.used) >= (score, entry.used) { continue }
        best = (score, entry.used, entry.title)
    }
    return best?.title
}

// Moves the target remembered for this URL's site to the top of the picker,
// where it is highlighted and Return opens it.
func promoteHistoryMatch(_ targets: [Target], url: URL) -> [Target] {
    guard let title = historyMatch(for: url, among: targets.map(\.title), history: loadHistory()),
          let index = targets.firstIndex(where: { $0.title == title }), index > 0 else { return targets }
    var reordered = targets
    reordered.insert(reordered.remove(at: index), at: 0)
    return reordered
}

func recordHistory(url: URL, title: String) {
    guard let key = historyKey(for: url) else { return }
    var history = loadHistory()
    history[key] = HistoryEntry(title: title, used: Date().timeIntervalSince1970.rounded())
    if history.count > historyLimit {
        let oldest = history.sorted { $0.value.used < $1.value.used }
        for (key, _) in oldest.prefix(history.count - historyLimit) {
            history.removeValue(forKey: key)
        }
    }
    saveHistory(history)
}
