import AppKit
import Carbon

/// Shortcuts that never show up in menus: system-wide keys, mouse modifiers,
/// shell line editing, tools like Rectangle. Loaded from the bundled Library.json
/// plus the user's own file, then corrected with the user's real settings.
final class TipsLibrary {
    struct Item: Decodable {
        let title: String
        let keys: String
        var note: String?
        var symbolic: Int?
        var pref: String?
    }

    struct Group: Decodable {
        let group: String
        var symbol: String?
        var note: String?
        let items: [Item]
    }

    struct AppEntry: Decodable {
        let bundleIDs: [String]
        let groups: [Group]
    }

    struct Tool: Decodable {
        let name: String
        let bundleIDs: [String]
        var symbol: String?
        var preferences: String?
        let items: [Item]
    }

    struct File: Decodable {
        var system: [Group]?
        var apps: [AppEntry]?
        var tools: [Tool]?
    }

    static let shared = TipsLibrary()

    private var bundled = File()
    private var user = File()

    static var userFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kestirme", isDirectory: true)
        return dir.appendingPathComponent("kisayollar.json")
    }

    init() { reload() }

    func reload() {
        if let url = Bundle.main.url(forResource: "Library", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            bundled = file
        }
        if let data = try? Data(contentsOf: Self.userFileURL),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            user = file
        } else {
            user = File()
        }
    }

    /// Validates the user's file; returns an error message or nil.
    func validateUserFile() -> String? {
        guard let data = try? Data(contentsOf: Self.userFileURL) else { return nil }
        do {
            _ = try JSONDecoder().decode(File.self, from: data)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Sheets

    func systemSheet() -> Sheet {
        let hotkeys = SymbolicHotKeys.load()
        var groups: [ShortcutGroup] = []
        for (i, g) in ((bundled.system ?? []) + (user.system ?? [])).enumerated() {
            groups.append(makeGroup(g, id: "sys.\(i)", hotkeys: hotkeys))
        }
        for tool in (bundled.tools ?? []) + (user.tools ?? []) where isInstalled(tool.bundleIDs) {
            let prefs = tool.preferences
            let items = tool.items.enumerated().map { j, item -> Shortcut in
                var strokes = KeySymbols.parse(item.keys)
                if let prefs, let key = item.pref, let custom = Self.toolShortcut(domain: prefs, key: key) {
                    strokes = custom
                }
                return Shortcut(id: "tool.\(tool.name).\(j)", title: item.title, path: nil, strokes: strokes,
                                enabled: !strokes.isEmpty, source: .curated, note: item.note,
                                groupTitle: tool.name)
            }.filter { !$0.strokes.isEmpty }
            groups.append(ShortcutGroup(id: "tool.\(tool.name)", title: tool.name,
                                        symbol: tool.symbol ?? "wrench.and.screwdriver",
                                        items: items, isCurated: true))
        }
        let count = groups.reduce(0) { $0 + $1.items.count }
        return Sheet(
            id: "system",
            name: "macOS",
            subtitle: "\(count) sistem kısayolu · Mac'indeki ayarlara göre",
            icon: NSWorkspace.shared.icon(forFile: "/System/Applications/System Settings.app"),
            groups: groups.filter { !$0.items.isEmpty },
            pid: nil
        )
    }

    /// Tips for a specific app, minus anything its menus already list.
    func extraGroups(for bundleID: String?, excluding menuGroups: [ShortcutGroup]) -> [ShortcutGroup] {
        guard let bundleID else { return [] }
        let known = Set(menuGroups.flatMap { $0.items.map(\.keyText) })
        let entries = ((bundled.apps ?? []) + (user.apps ?? [])).filter { $0.bundleIDs.contains(bundleID) }
        var out: [ShortcutGroup] = []
        for (i, entry) in entries.enumerated() {
            for (j, g) in entry.groups.enumerated() {
                let group = makeGroup(g, id: "tip.\(bundleID).\(i).\(j)", hotkeys: [:])
                let items = group.items.filter { !known.contains($0.keyText) }
                guard !items.isEmpty else { continue }
                out.append(group.with(items: items))
            }
        }
        return out
    }

    private func makeGroup(_ g: Group, id: String, hotkeys: [Int: SymbolicHotKeys.Entry]) -> ShortcutGroup {
        let items = g.items.enumerated().compactMap { j, item -> Shortcut? in
            var strokes = KeySymbols.parse(item.keys)
            var enabled = true
            var note = item.note
            if let sid = item.symbolic, let entry = hotkeys[sid] {
                enabled = entry.enabled
                if let custom = entry.stroke { strokes = [custom] }
                if !enabled { note = "Sistem Ayarları'nda kapalı" }
            }
            guard !strokes.isEmpty else { return nil }
            return Shortcut(id: "\(id).\(j)", title: item.title, path: nil, strokes: strokes,
                            enabled: enabled, source: .curated, note: note, groupTitle: g.group)
        }
        var group = ShortcutGroup(id: id, title: g.group, symbol: g.symbol ?? "sparkles", items: items, isCurated: true)
        group.note = g.note
        return group
    }

    private func isInstalled(_ ids: [String]) -> Bool {
        ids.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// Reads a MASShortcut-style `{keyCode, modifierFlags}` value from another app's preferences.
    private static func toolShortcut(domain: String, key: String) -> [KeyStroke]? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? [String: Any],
              let code = (value["keyCode"] as? NSNumber)?.intValue,
              let flags = (value["modifierFlags"] as? NSNumber)?.uintValue else { return nil }
        guard let label = KeyboardLayout.label(for: code) else { return nil }
        let mods = Modifiers(NSEvent.ModifierFlags(rawValue: flags))
        return [KeyStroke(modifiers: mods, key: label)]
    }

    // MARK: User file

    static let userTemplate = """
    {
      "apps": [
        {
          "bundleIDs": ["com.googlecode.iterm2"],
          "groups": [
            {
              "group": "Midnight Commander",
              "symbol": "folder",
              "items": [
                { "title": "Dosyayı kopyala", "keys": "f5" },
                { "title": "Dosyayı taşı", "keys": "f6" },
                { "title": "Klasör oluştur", "keys": "f7" },
                { "title": "Sil", "keys": "f8" },
                { "title": "Panelleri değiştir", "keys": "tab" }
              ]
            }
          ]
        }
      ],
      "system": [
        {
          "group": "Benim kısayollarım",
          "symbol": "star",
          "items": [
            { "title": "Örnek: Raycast", "keys": "opt+space" }
          ]
        }
      ]
    }

    """

    func openUserFile() {
        let url = Self.userFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Self.userTemplate.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }
}

/// The user's real system shortcut settings (System Settings › Keyboard › Keyboard Shortcuts).
enum SymbolicHotKeys {
    struct Entry {
        let enabled: Bool
        let stroke: KeyStroke?
    }

    static func load() -> [Int: Entry] {
        guard let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                  "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        else { return [:] }
        var out: [Int: Entry] = [:]
        for (key, raw) in all {
            guard let id = Int(key), let dict = raw as? [String: Any] else { continue }
            let enabled = (dict["enabled"] as? NSNumber)?.boolValue ?? true
            var stroke: KeyStroke?
            if let value = dict["value"] as? [String: Any],
               (value["type"] as? String) == "standard",
               let params = value["parameters"] as? [NSNumber], params.count == 3 {
                let char = params[0].intValue
                let code = params[1].intValue
                let flags = NSEvent.ModifierFlags(rawValue: params[2].uintValue)
                var label: String?
                if let v = KeySymbols.virtualKeys[code] {
                    label = v
                } else if char != 65535, let scalar = UnicodeScalar(char) {
                    label = KeySymbols.label(forCharacter: String(Character(scalar)))
                } else {
                    label = KeyboardLayout.label(for: code)
                }
                if let label {
                    stroke = KeyStroke(modifiers: Modifiers(flags), key: label)
                }
            }
            out[id] = Entry(enabled: enabled, stroke: stroke)
        }
        return out
    }
}

/// Maps virtual key codes to what is printed on the user's keyboard layout.
enum KeyboardLayout {
    static func label(for keyCode: Int) -> String? {
        if let v = KeySymbols.virtualKeys[keyCode] { return v }
        guard let char = character(for: keyCode) else { return nil }
        return KeySymbols.label(forCharacter: char)
    }

    static func character(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
                ?? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
