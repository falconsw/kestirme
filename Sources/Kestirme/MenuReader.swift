import AppKit
import ApplicationServices

/// Reads keyboard shortcuts out of an app's menu bar through the Accessibility API.
enum MenuReader {
    private static let itemAttributes = [
        "AXTitle", "AXMenuItemCmdChar", "AXMenuItemCmdModifiers",
        "AXMenuItemCmdVirtualKey", "AXMenuItemCmdGlyph", "AXEnabled", "AXChildren",
    ]

    /// Bookmarks, history and similar menus can hold thousands of items.
    private static let maxItemsPerMenu = 400
    private static let maxDepth = 3
    private static let timeBudget: TimeInterval = 2.5

    static func read(pid: pid_t, appName: String) -> [ShortcutGroup] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.75)
        guard let menuBar: AXUIElement = value(app, "AXMenuBar"),
              let barItems: [AXUIElement] = value(menuBar, "AXChildren") else { return [] }

        let deadline = Date().addingTimeInterval(timeBudget)
        var groups: [ShortcutGroup] = []

        // Index 0 is the Apple menu; it is the same in every app.
        for (index, barItem) in barItems.enumerated() where index > 0 {
            if Date() > deadline { break }
            let title: String = value(barItem, "AXTitle") ?? ""
            guard !title.isEmpty,
                  let menus: [AXUIElement] = value(barItem, "AXChildren"),
                  let menu = menus.first else { continue }

            var items: [Shortcut] = []
            var seen = Set<String>()
            collect(menu: menu, groupTitle: title, path: [], depth: 1,
                    deadline: deadline, items: &items, seen: &seen, idPrefix: "\(pid).\(index)")
            guard !items.isEmpty else { continue }
            groups.append(ShortcutGroup(
                id: "\(pid).\(index).\(title)",
                title: title,
                symbol: MenuSymbols.symbol(for: title),
                items: items,
                isCurated: false,
                usesAppIcon: index == 1
            ))
        }
        return groups
    }

    private static func collect(menu: AXUIElement, groupTitle: String, path: [String], depth: Int,
                                deadline: Date, items: inout [Shortcut], seen: inout Set<String>,
                                idPrefix: String) {
        guard let children: [AXUIElement] = value(menu, "AXChildren") else { return }
        for (i, child) in children.prefix(maxItemsPerMenu).enumerated() {
            if Date() > deadline { return }
            let v = multiple(child, itemAttributes)
            let title = (v[0] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !title.isEmpty else { continue }

            if let sub = v[6] as? [AXUIElement], let submenu = sub.first, depth < maxDepth {
                collect(menu: submenu, groupTitle: groupTitle, path: path + [title], depth: depth + 1,
                        deadline: deadline, items: &items, seen: &seen, idPrefix: "\(idPrefix).\(i)")
                continue
            }

            let char = v[1] as? String
            let rawMods = (v[2] as? NSNumber)?.intValue ?? 0
            let vk = (v[3] as? NSNumber)?.intValue
            let glyph = (v[4] as? NSNumber)?.intValue
            guard let key = KeySymbols.label(char: char, glyph: glyph, virtualKey: vk) else { continue }

            var mods: Modifiers = []
            if rawMods & 1 != 0 { mods.insert(.shift) }
            if rawMods & 2 != 0 { mods.insert(.option) }
            if rawMods & 4 != 0 { mods.insert(.control) }
            if rawMods & 8 == 0 { mods.insert(.command) }
            if rawMods & 16 != 0 { mods.insert(.function) }

            let stroke = KeyStroke(modifiers: mods, key: key)
            let pathText = path.isEmpty ? nil : path.joined(separator: " › ")
            let dedupe = "\(pathText ?? "")|\(title)|\(stroke.caps.joined())"
            guard seen.insert(dedupe).inserted else { continue }

            items.append(Shortcut(
                id: "\(idPrefix).\(i)",
                title: title,
                path: pathText,
                strokes: [stroke],
                enabled: (v[5] as? Bool) ?? true,
                source: .menu,
                element: child,
                groupTitle: groupTitle
            ))
        }
    }

    // MARK: AX helpers

    private static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref else { return nil }
        return ref as? T
    }

    private static func multiple(_ element: AXUIElement, _ attributes: [String]) -> [Any?] {
        var ref: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(
            element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &ref)
        guard err == .success, let array = ref as? [AnyObject], array.count == attributes.count else {
            return Array(repeating: nil, count: attributes.count)
        }
        return array.map { item -> Any? in
            if CFGetTypeID(item) == AXValueGetTypeID(), AXValueGetType(item as! AXValue) == .axError {
                return nil
            }
            return item
        }
    }

    static func press(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}

/// SF Symbols for well-known menu names, in English and Turkish.
enum MenuSymbols {
    private static let table: [(keys: [String], symbol: String)] = [
        (["file", "dosya", "arsiv"], "doc"),
        (["edit", "duzen"], "pencil"),
        (["view", "goruntu", "gorunum", "goster"], "eye"),
        (["format", "bicim"], "textformat"),
        (["window", "pencere"], "macwindow"),
        (["help", "yardim"], "questionmark.circle"),
        (["history", "gecmis"], "clock.arrow.circlepath"),
        (["bookmark", "yer imleri", "yer isareti"], "bookmark"),
        (["selection", "secim", "secme"], "character.cursor.ibeam"),
        (["terminal", "shell", "kabuk"], "terminal"),
        (["run", "calistir"], "play"),
        (["debug", "hata ayik"], "ladybug"),
        (["product", "urun", "build"], "hammer"),
        (["navigate", "gezin", "dolas"], "location"),
        (["find", "bul", "search", "ara"], "magnifyingglass"),
        (["tools", "araclar"], "wrench.and.screwdriver"),
        (["insert", "ekle"], "plus.square"),
        (["table", "tablo"], "tablecells"),
        (["go", "git"], "arrow.right.circle"),
        (["tab", "sekme"], "rectangle.on.rectangle"),
        (["mailbox", "posta", "message", "ileti", "mesaj"], "envelope"),
        (["profile", "profil", "people", "kisi"], "person.crop.circle"),
        (["image", "resim", "gorsel"], "photo"),
        (["arrange", "yerles", "duzenle"], "square.3.layers.3d"),
        (["code", "kod", "refactor", "develop", "gelistir"], "chevron.left.forwardslash.chevron.right"),
        (["slide", "slayt", "play", "oynat", "playback", "controls", "denetim"], "play.rectangle"),
        (["account", "hesap"], "person"),
        (["session", "oturum"], "rectangle.split.3x1"),
    ]

    static func symbol(for title: String) -> String {
        let t = Search.fold(title)
        for entry in table where entry.keys.contains(where: { t == $0 || t.hasPrefix($0) }) {
            return entry.symbol
        }
        return "square.grid.2x2"
    }
}
