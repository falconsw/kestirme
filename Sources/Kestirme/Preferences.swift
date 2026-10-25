import AppKit
import Carbon.HIToolbox
import Observation
import ServiceManagement

struct HotKeySpec: Codable, Equatable {
    var keyCode: Int
    var modifiers: UInt   // NSEvent.ModifierFlags raw value
    var label: String

    static let `default` = HotKeySpec(
        keyCode: kVK_ANSI_K,
        modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue,
        label: "K"
    )

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    var stroke: KeyStroke { KeyStroke(modifiers: Modifiers(flags), key: label) }
    var display: String { stroke.caps.joined() }
}

@Observable
final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    var holdEnabled: Bool { didSet { defaults.set(holdEnabled, forKey: "holdEnabled") } }
    var holdDelay: Double { didSet { defaults.set(holdDelay, forKey: "holdDelay") } }
    var hotKeyEnabled: Bool { didSet { defaults.set(hotKeyEnabled, forKey: "hotKeyEnabled") } }
    var hotKey: HotKeySpec {
        didSet { defaults.set(try? JSONEncoder().encode(hotKey), forKey: "hotKey") }
    }
    var showDisabled: Bool { didSet { defaults.set(showDisabled, forKey: "showDisabled") } }
    var showTips: Bool { didSet { defaults.set(showTips, forKey: "showTips") } }
    var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    /// Set once the login item has been turned on by default, so a later "off" sticks.
    var loginItemConfigured: Bool { didSet { defaults.set(loginItemConfigured, forKey: "loginItemConfigured") } }

    private init() {
        defaults.register(defaults: [
            "holdEnabled": true, "holdDelay": 0.8, "hotKeyEnabled": true,
            "showDisabled": true, "showTips": true, "onboardingDone": false,
            "showMenuBarIcon": true, "loginItemConfigured": false,
        ])
        holdEnabled = defaults.bool(forKey: "holdEnabled")
        holdDelay = defaults.double(forKey: "holdDelay")
        hotKeyEnabled = defaults.bool(forKey: "hotKeyEnabled")
        showDisabled = defaults.bool(forKey: "showDisabled")
        showTips = defaults.bool(forKey: "showTips")
        onboardingDone = defaults.bool(forKey: "onboardingDone")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        loginItemConfigured = defaults.bool(forKey: "loginItemConfigured")
        if let data = defaults.data(forKey: "hotKey"), let spec = try? JSONDecoder().decode(HotKeySpec.self, from: data) {
            hotKey = spec
        } else {
            hotKey = .default
        }
    }

    /// Registered counts as on even while macOS waits for the user to approve it.
    var launchAtLogin: Bool {
        get { [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Kestirme: login item error: \(error)")
            }
        }
    }
}
