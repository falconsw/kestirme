import AppKit
import ApplicationServices

/// Modifier keys in Apple's display order: ⌃ ⌥ ⇧ ⌘ (fn first).
struct Modifiers: OptionSet, Hashable {
    let rawValue: Int
    static let function = Modifiers(rawValue: 1 << 0)
    static let control = Modifiers(rawValue: 1 << 1)
    static let option = Modifiers(rawValue: 1 << 2)
    static let shift = Modifiers(rawValue: 1 << 3)
    static let command = Modifiers(rawValue: 1 << 4)

    var symbols: [String] {
        var out: [String] = []
        if contains(.function) { out.append("fn") }
        if contains(.control) { out.append("⌃") }
        if contains(.option) { out.append("⌥") }
        if contains(.shift) { out.append("⇧") }
        if contains(.command) { out.append("⌘") }
        return out
    }

    var names: String {
        var out: [String] = []
        if contains(.function) { out.append("fn") }
        if contains(.control) { out.append("ctrl control kontrol") }
        if contains(.option) { out.append("opt option alt") }
        if contains(.shift) { out.append("shift") }
        if contains(.command) { out.append("cmd command") }
        return out.joined(separator: " ")
    }

    init(rawValue: Int) { self.rawValue = rawValue }

    init(_ flags: NSEvent.ModifierFlags) {
        var m: Modifiers = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        self = m
    }
}

/// One key press, e.g. ⇧⌘K. A shortcut is one or more strokes (chords like ⌘K ⌘S).
struct KeyStroke: Hashable {
    var modifiers: Modifiers
    var key: String

    var caps: [String] { modifiers.symbols + [key] }
}

struct Shortcut: Identifiable, Equatable {
    enum Source { case menu, curated }

    let id: String
    let title: String
    /// Submenu path inside the top-level menu ("Bul", "Biçim › Yazı Tipi").
    let path: String?
    let strokes: [KeyStroke]
    let enabled: Bool
    let source: Source
    let note: String?
    /// Menu item to press when the row is clicked.
    let element: AXUIElement?

    var isRunnable: Bool { element != nil && enabled }

    var keyText: String {
        strokes.map { $0.caps.joined() }.joined(separator: " ")
    }

    var plainKeyText: String {
        strokes.map { $0.caps.joined(separator: " ") }.joined(separator: " , ")
    }

    /// Lowercased, diacritic-folded text used by search.
    let searchText: String

    init(id: String, title: String, path: String?, strokes: [KeyStroke], enabled: Bool,
         source: Source, note: String? = nil, element: AXUIElement? = nil, groupTitle: String) {
        self.id = id
        self.title = title
        self.path = path
        self.strokes = strokes
        self.enabled = enabled
        self.source = source
        self.note = note
        self.element = element
        let keyWords = strokes.map { $0.caps.joined(separator: " ") + " " + $0.caps.joined() + " " + $0.modifiers.names }
        self.searchText = Search.fold(([title, path ?? "", groupTitle, note ?? ""] + keyWords).joined(separator: " "))
    }

    static func == (a: Shortcut, b: Shortcut) -> Bool {
        a.id == b.id && a.title == b.title && a.enabled == b.enabled && a.strokes == b.strokes
    }
}

struct ShortcutGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let items: [Shortcut]
    /// Comes from the built-in tips library rather than the app's menus.
    let isCurated: Bool
    /// The app menu (second menu bar item) gets the app icon instead of a symbol.
    var usesAppIcon = false
    /// Short caption shown next to the title (e.g. "macOS 15+").
    var note: String? = nil

    func with(items: [Shortcut]) -> ShortcutGroup {
        var copy = ShortcutGroup(id: id, title: title, symbol: symbol, items: items, isCurated: isCurated)
        copy.usesAppIcon = usesAppIcon
        copy.note = note
        return copy
    }
}

/// Everything the panel shows for one source (an app or macOS itself).
struct Sheet: Equatable {
    let id: String
    let name: String
    let subtitle: String
    let icon: NSImage?
    let groups: [ShortcutGroup]
    let pid: pid_t?

    var shortcutCount: Int { groups.reduce(0) { $0 + $1.items.count } }

    static func == (a: Sheet, b: Sheet) -> Bool {
        a.id == b.id && a.groups == b.groups && a.name == b.name
    }
}

enum Search {
    static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func tokens(_ query: String) -> [String] {
        fold(query)
            .replacingOccurrences(of: "+", with: " ")
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
    }

    static func matches(_ item: Shortcut, _ tokens: [String]) -> Bool {
        tokens.allSatisfy { item.searchText.contains($0) }
    }
}
