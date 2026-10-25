import AppKit
import Carbon.HIToolbox

/// Turns the raw values the Accessibility API reports for menu items
/// (AXMenuItemCmdChar / Glyph / VirtualKey) into keycap labels.
enum KeySymbols {
    /// Carbon `kMenu…Glyph` codes (Menus.h).
    static let glyphs: [Int: String] = [
        0x02: "⇥", 0x03: "⇤", 0x04: "⌤", 0x05: "⇧", 0x06: "⌃", 0x07: "⌥",
        0x09: "Space", 0x0A: "⌦", 0x0B: "↩", 0x0C: "↩", 0x0D: "↩",
        0x10: "⇣", 0x11: "⌘", 0x17: "⌫", 0x18: "⇠", 0x19: "⇡", 0x1A: "⇢",
        0x1B: "esc", 0x1C: "⌧", 0x62: "⇞", 0x63: "⇪", 0x64: "←", 0x65: "→",
        0x66: "↖", 0x67: "?", 0x68: "↑", 0x69: "↘", 0x6A: "↓", 0x6B: "⇟",
        0x6E: "⏻", 0x6F: "F1", 0x70: "F2", 0x71: "F3", 0x72: "F4", 0x73: "F5",
        0x74: "F6", 0x75: "F7", 0x76: "F8", 0x77: "F9", 0x78: "F10", 0x79: "F11",
        0x7A: "F12", 0x87: "F13", 0x88: "F14", 0x89: "F15", 0x8C: "⏏",
        0x8F: "F16", 0x90: "F17", 0x91: "F18", 0x92: "F19",
    ]

    /// Virtual key codes for keys that have no printable character.
    static let virtualKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Escape: "esc", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_ANSI_KeypadEnter: "⌤", kVK_ANSI_KeypadClear: "⌧",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20", kVK_Help: "?",
    ]

    static func label(char: String?, glyph: Int?, virtualKey: Int?) -> String? {
        if let glyph, glyph > 0, let g = glyphs[glyph] { return g }
        if let char, !char.isEmpty, let c = label(forCharacter: char) { return c }
        if let virtualKey, let v = virtualKeys[virtualKey] { return v }
        return nil
    }

    static func label(forCharacter s: String) -> String? {
        guard let scalar = s.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x0D, 0x0A: return "↩"
        case 0x03: return "⌤"
        case 0x09: return "⇥"
        case 0x19: return "⇤"
        case 0x20: return "Space"
        case 0x1B: return "esc"
        case 0x08, 0x7F: return "⌫"
        case 0xF700: return "↑"
        case 0xF701: return "↓"
        case 0xF702: return "←"
        case 0xF703: return "→"
        case 0xF704...0xF726: return "F\(scalar.value - 0xF704 + 1)"
        case 0xF728: return "⌦"
        case 0xF729: return "↖"
        case 0xF72B: return "↘"
        case 0xF72C: return "⇞"
        case 0xF72D: return "⇟"
        case 0xF739: return "⌧"
        case 0x00...0x1F, 0xF700...0xF8FF: return nil
        default:
            // Locale-independent uppercasing so "i" stays "I" (not "İ").
            return s.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }

    /// Label for a key code as typed on the current layout (used by the hotkey recorder).
    static func label(forKeyCode code: Int, characters: String?) -> String {
        if let v = virtualKeys[code] { return v }
        if let c = characters, let l = label(forCharacter: c) { return l }
        return "#\(code)"
    }

    // MARK: Parsing the "keys" syntax of the tips library

    private static let modifierWords: [String: Modifiers] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "shift": .shift, "⇧": .shift,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "ctrl": .control, "control": .control, "⌃": .control,
        "fn": .function, "globe": .function, "🌐": .function,
    ]

    private static let keyWords: [String: String] = [
        "return": "↩", "enter": "↩", "tab": "⇥", "space": "Space", "esc": "esc", "escape": "esc",
        "delete": "⌫", "backspace": "⌫", "fwddelete": "⌦", "home": "↖", "end": "↘",
        "pgup": "⇞", "pageup": "⇞", "pgdown": "⇟", "pagedown": "⇟",
        "up": "↑", "down": "↓", "left": "←", "right": "→",
        "click": "Tıkla", "drag": "Sürükle", "scroll": "Kaydır", "power": "⏻", "eject": "⏏",
        "plus": "+", "minus": "-", "comma": ",", "backtick": "`",
    ]

    /// Parses "cmd+shift+k", "cmd+k cmd+s" (chord), "ctrl+opt+left", "f5".
    static func parse(_ text: String) -> [KeyStroke] {
        text.split(separator: " ").compactMap { chunk -> KeyStroke? in
            var mods: Modifiers = []
            var key: String?
            for raw in chunk.split(separator: "+", omittingEmptySubsequences: false) {
                let part = raw.isEmpty ? "+" : String(raw)
                let lower = part.lowercased()
                if let m = modifierWords[lower] {
                    mods.insert(m)
                } else if let k = keyWords[lower] {
                    key = k
                } else if lower.count > 1, lower.first == "f", Int(lower.dropFirst()) != nil {
                    key = part.uppercased()
                } else {
                    key = part.count == 1 ? part.uppercased() : part
                }
            }
            guard let key else { return nil }
            return KeyStroke(modifiers: mods, key: key)
        }
    }
}
