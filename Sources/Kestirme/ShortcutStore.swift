import AppKit

/// Reads menus off the main thread and keeps a short-lived cache per process,
/// so holding ⌘ shows the sheet instantly (the read is prefetched on app switch).
final class ShortcutStore {
    static let shared = ShortcutStore()

    private struct Entry {
        let date: Date
        let groups: [ShortcutGroup]
    }

    private let queue = DispatchQueue(label: "kestirme.menus", qos: .userInitiated)
    private var cache: [pid_t: Entry] = [:]
    private var inFlight: [pid_t: [([ShortcutGroup]) -> Void]] = [:]

    func cached(_ pid: pid_t) -> [ShortcutGroup]? { cache[pid]?.groups }

    func isFresh(_ pid: pid_t, within seconds: TimeInterval) -> Bool {
        guard let e = cache[pid] else { return false }
        return Date().timeIntervalSince(e.date) < seconds
    }

    /// Reads the app's menus; `completion` runs on the main thread.
    func load(_ app: NSRunningApplication, completion: (([ShortcutGroup]) -> Void)? = nil) {
        let pid = app.processIdentifier
        if inFlight[pid] != nil {
            if let completion { inFlight[pid]?.append(completion) }
            return
        }
        inFlight[pid] = completion.map { [$0] } ?? []
        let name = app.localizedName ?? ""
        queue.async {
            let groups = MenuReader.read(pid: pid, appName: name)
            DispatchQueue.main.async {
                self.cache[pid] = Entry(date: Date(), groups: groups)
                self.trim()
                let waiters = self.inFlight.removeValue(forKey: pid) ?? []
                waiters.forEach { $0(groups) }
            }
        }
    }

    func forget(_ pid: pid_t) { cache.removeValue(forKey: pid) }

    private func trim() {
        guard cache.count > 24 else { return }
        let oldest = cache.sorted { $0.value.date < $1.value.date }.prefix(cache.count - 24)
        oldest.forEach { cache.removeValue(forKey: $0.key) }
    }
}
