import AppKit
import SwiftUI

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = AppController()

    let prefs = Preferences.shared
    let model = PanelModel()
    private(set) lazy var panel = PanelController(model: model)
    private let hold = HoldMonitor()
    private let store = ShortcutStore.shared

    var isRecordingHotKey = false
    private var statusItem: NSStatusItem!
    private var lastExternalApp: NSRunningApplication?
    private var targetApp: NSRunningApplication?
    private var trustTimer: Timer?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var statusVisibility: NSKeyValueObservation?
    private var backgroundActivity: NSObjectProtocol?

    private var isTrusted: Bool { AXIsProcessTrusted() }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.75)
        // Without this, App Nap can delay the ⌘-hold timer while Kestirme sits in the background.
        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "⌘ tuşunu dinliyor")
        enableLoginItemOnFirstRun()
        setupStatusItem()
        wire()
        observeWorkspace()
        applyPreferences()

        if let front = NSWorkspace.shared.frontmostApplication, !isSelf(front) { lastExternalApp = front }
        if isTrusted { startMonitoring() } else { startTrustPolling() }
        if !prefs.onboardingDone || !isTrusted { showOnboarding() }
    }

    /// Starts at login by default, but only for the installed copy and only once.
    private func enableLoginItemOnFirstRun() {
        guard !prefs.loginItemConfigured else { return }
        let path = Bundle.main.bundlePath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") else { return }
        prefs.loginItemConfigured = true
        prefs.launchAtLogin = true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    private func wire() {
        model.onRun = { [weak self] item in self?.run(item) }
        model.onOpenSettings = { [weak self] in
            self?.panel.hide(animated: false)
            self?.openSettings()
        }
        model.onExportPDF = { [weak self] in self?.panel.exportPDF() }
        model.onRequestPermission = { [weak self] in
            self?.panel.hide(animated: false)
            self?.requestPermission()
        }

        HotKeyCenter.shared.onPress = { [weak self] in self?.hotKeyPressed() }

        hold.onHold = { [weak self] in
            guard let self, !self.isRecordingHotKey, !self.panel.isVisible else { return }
            self.showPanel(mode: .hold)
        }
        hold.onCommandReleased = { [weak self] in
            guard let self, self.panel.isVisible, self.model.mode == .hold else { return }
            self.panel.hide()
        }
        hold.onKeyDown = { [weak self] code, flags in
            guard let self, self.panel.isVisible, self.model.mode == .hold else { return }
            // The hotkey pins the panel instead of closing it.
            if self.prefs.hotKeyEnabled, code == self.prefs.hotKey.keyCode, flags == self.prefs.hotKey.flags { return }
            self.panel.hide(animated: false)
        }
    }

    func applyPreferences() {
        hold.delay = prefs.holdDelay
        hold.isEnabled = prefs.holdEnabled
        if statusItem?.isVisible != prefs.showMenuBarIcon { statusItem?.isVisible = prefs.showMenuBarIcon }
        if !isRecordingHotKey {
            HotKeyCenter.shared.register(prefs.hotKeyEnabled ? prefs.hotKey : nil)
        }
    }

    // MARK: Permission

    private func startMonitoring() {
        model.trusted = true
        if !hold.start() {
            // Right after the permission is granted the tap can still fail for a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startMonitoring() }
            return
        }
        if let app = lastExternalApp { store.load(app) }
    }

    private func startTrustPolling() {
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self, self.isTrusted else { return }
            t.invalidate()
            self.trustTimer = nil
            self.startMonitoring()
        }
    }

    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        startTrustPolling()
    }

    // MARK: Showing the sheet

    private func hotKeyPressed() {
        if panel.isVisible {
            if model.mode == .hold { panel.pin() } else { panel.hide() }
        } else {
            showPanel(mode: .interactive)
        }
    }

    func showPanel(mode: PanelModel.Mode, tab: PanelModel.Tab = .app) {
        let trusted = isTrusted
        let app = currentTarget()
        targetApp = app
        model.trusted = trusted
        model.systemSheet = nil
        model.tab = app == nil ? .system : tab
        if model.tab == .system { model.systemSheet = TipsLibrary.shared.systemSheet() }

        if let app {
            let cached = store.cached(app.processIdentifier)
            model.isLoading = trusted && cached == nil
            model.setAppSheet(makeSheet(app, groups: cached ?? [], trusted: trusted))
        } else {
            model.setAppSheet(nil)
        }
        panel.show(mode: mode)

        guard trusted, let app, !store.isFresh(app.processIdentifier, within: 1.5) else {
            model.isLoading = false
            return
        }
        store.load(app) { [weak self] groups in
            guard let self, self.targetApp?.processIdentifier == app.processIdentifier else { return }
            self.model.isLoading = false
            self.model.setAppSheet(self.makeSheet(app, groups: groups, trusted: true))
        }
    }

    private func makeSheet(_ app: NSRunningApplication, groups: [ShortcutGroup], trusted: Bool) -> Sheet {
        let tips = TipsLibrary.shared.extraGroups(for: app.bundleIdentifier, excluding: groups)
        let menuCount = groups.reduce(0) { $0 + $1.items.count }
        let tipCount = tips.reduce(0) { $0 + $1.items.count }
        var subtitle = trusted ? "\(menuCount) kısayol · \(groups.count) menü" : "Erişilebilirlik izni bekleniyor"
        if trusted, tipCount > 0, prefs.showTips { subtitle += " · \(tipCount) gizli ipucu" }
        return Sheet(
            id: app.bundleIdentifier ?? "\(app.processIdentifier)",
            name: app.localizedName ?? "Uygulama",
            subtitle: subtitle,
            icon: app.icon,
            groups: groups + tips,
            pid: app.processIdentifier
        )
    }

    private func currentTarget() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, !isSelf(front) { return front }
        return lastExternalApp
    }

    private func isSelf(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func run(_ item: Shortcut) {
        guard let element = item.element else { return }
        let app = targetApp
        panel.hide(animated: false)
        if let pid = app?.processIdentifier { store.forget(pid) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            app?.activate()
            // Some actions open modal dialogs and block the AX call until they return.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.06) {
                MenuReader.press(element)
            }
        }
    }

    private func observeWorkspace() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  !self.isSelf(app) else { return }
            self.lastExternalApp = app
            if self.panel.isVisible, app.processIdentifier != self.targetApp?.processIdentifier {
                self.panel.hide()
            }
            guard self.isTrusted else { return }
            // Prefetch so a ⌘-hold in this app opens instantly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard !self.store.isFresh(app.processIdentifier, within: 8) else { return }
                self.store.load(app)
            }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.store.forget(app.processIdentifier)
            }
        }
    }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "KestirmeStatusItem"
        // ⌘-dragging the icon off the menu bar hides it; keep the setting in sync.
        statusItem.behavior = .removalAllowed
        statusVisibility = statusItem.observe(\.isVisible, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.prefs.showMenuBarIcon != item.isVisible else { return }
                self.prefs.showMenuBarIcon = item.isVisible
            }
        }
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
            let image = NSImage(systemSymbolName: "command", accessibilityDescription: "Kestirme")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let appName = currentTarget()?.localizedName ?? "Uygulama"
        let show = item("\(appName) Kısayolları", #selector(showFromMenu))
        if prefs.hotKeyEnabled, prefs.hotKey.label.count == 1 {
            show.keyEquivalent = prefs.hotKey.label.lowercased()
            show.keyEquivalentModifierMask = prefs.hotKey.flags
        }
        menu.addItem(show)
        menu.addItem(item("macOS Kısayolları", #selector(showSystemFromMenu)))
        menu.addItem(.separator())
        if !isTrusted {
            let perm = item("Erişilebilirlik İzni Ver…", #selector(permissionFromMenu))
            perm.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            menu.addItem(perm)
        }
        menu.addItem(item("Kendi Kısayollarını Düzenle…", #selector(editUserFile)))
        let settings = item("Ayarlar…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(item("Hoş Geldin Ekranı", #selector(showOnboarding)))
        menu.addItem(item("Simgeyi Menü Çubuğundan Gizle", #selector(hideStatusItem)))
        menu.addItem(.separator())
        let quit = item("Kestirme'den Çık", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func showFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.showPanel(mode: .interactive) }
    }

    @objc private func showSystemFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.showPanel(mode: .interactive, tab: .system) }
    }

    @objc private func permissionFromMenu() { requestPermission() }

    @objc private func hideStatusItem() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Simge gizlensin mi?"
        alert.informativeText = "Kestirme arka planda çalışmaya devam eder. Ayarlara dönmek için Kestirme'yi Spotlight'tan ya da Uygulamalar klasöründen yeniden aç; panel açıkken ⌘, de olur."
        alert.addButton(withTitle: "Gizle")
        alert.addButton(withTitle: "Vazgeç")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        prefs.showMenuBarIcon = false
        applyPreferences()
    }
    @objc private func editUserFile() { TipsLibrary.shared.openUserFile() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Windows

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                onChange: { [weak self] in self?.applyPreferences() },
                onRequestPermission: { [weak self] in self?.requestPermission() }
            )
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: host)
            w.title = "Kestirme Ayarları"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(
                hotKey: prefs.hotKey.stroke,
                onRequestPermission: { [weak self] in self?.requestPermission() },
                onDone: { [weak self] in
                    self?.prefs.onboardingDone = true
                    self?.onboardingWindow?.close()
                }
            )
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
}
