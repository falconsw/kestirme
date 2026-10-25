import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Borderless floating panel that can take keyboard focus without activating Kestirme,
/// so the app underneath stays frontmost and its menus stay readable.
final class SheetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a row run it, even while the panel is not key (⌘-hold mode).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    private let panel: SheetPanel
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var hiding = false

    var isVisible: Bool { panel.isVisible && !hiding }

    init(model: PanelModel) {
        self.model = model
        panel = SheetPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.delegate = self

        let host = FirstMouseHostingView(rootView: SheetView(model: model))
        host.sizingOptions = []
        panel.contentView = host

        model.onSizeChange = { [weak self] size in self?.resize(to: size) }
        model.onClose = { [weak self] in self?.hide() }
    }

    // MARK: Show / hide

    func show(mode: PanelModel.Mode) {
        hiding = false
        let screen = Self.activeScreen()
        let visible = screen.visibleFrame
        model.maxSize = CGSize(width: visible.width * 0.94, height: visible.height * 0.9)
        model.mode = mode
        model.rebuild()

        panel.setFrame(frame(for: model.baseLayout.panelSize, on: screen), display: false)
        model.appeared = false
        panel.alphaValue = 0
        if mode == .interactive {
            panel.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { self.model.focusToken += 1 }
        } else {
            panel.orderFrontRegardless()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { model.appeared = true }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            self?.panel.invalidateShadow()
        }
        installMonitors()
    }

    /// Turns a ⌘-hold panel into a sticky one (hotkey pressed while holding).
    func pin() {
        guard isVisible else { return }
        model.mode = .interactive
        panel.makeKey()
        model.focusToken += 1
        installMonitors()
    }

    func hide(animated: Bool = true) {
        guard panel.isVisible, !hiding else { return }
        hiding = true
        removeMonitors()
        let finish = { [weak self] in
            guard let self, self.hiding else { return }
            self.panel.orderOut(nil)
            self.hiding = false
            self.model.reset()
            self.model.appeared = false
        }
        guard animated else { finish(); return }
        withAnimation(.easeIn(duration: 0.1)) { model.appeared = false }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        } completionHandler: { finish() }
    }

    private func resize(to size: CGSize) {
        guard panel.isVisible else { return }
        let screen = panel.screen ?? Self.activeScreen()
        let target = frame(for: size, on: screen)
        guard target != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            self?.panel.invalidateShadow()
        }
    }

    private func frame(for size: CGSize, on screen: NSScreen) -> NSRect {
        let v = screen.visibleFrame
        let x = v.midX - size.width / 2
        // Slightly above centre, like Spotlight.
        let y = v.minY + max(0, (v.height - size.height) * 0.55)
        return NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: Events

    private func installMonitors() {
        removeMonitors()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        guard model.mode == .interactive else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    /// Returns true when the key was handled.
    private func handleKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch Int(e.keyCode) {
        case 53: // esc
            if model.query.isEmpty { hide() } else { model.query = "" }
            return true
        case 125: model.move(.down); return true
        case 126: model.move(.up); return true
        // ←/→ move between columns unless the user is editing the query text.
        case 123 where model.query.isEmpty || model.selectedID != nil: model.move(.left); return true
        case 124 where model.query.isEmpty || model.selectedID != nil: model.move(.right); return true
        case 36, 76: model.runSelected(); return true
        case 48: model.switchTab(); return true
        default: break
        }
        guard cmd, let ch = e.charactersIgnoringModifiers?.lowercased() else { return false }
        switch ch {
        case "f": model.focusToken += 1; return true
        case "w": hide(); return true
        case ",": model.onOpenSettings?(); return true
        case "s", "p": model.onExportPDF?(); return true
        case "1": model.switchTab(.app); return true
        case "2": model.switchTab(.system); return true
        default: return false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else dismisses a pinned sheet.
        if model.mode == .interactive { hide() }
    }

    // MARK: Export

    func exportPDF() {
        guard let sheet = model.sheet else { return }
        let groups = model.exportGroups()
        hide(animated: false)
        NSApp.activate(ignoringOtherApps: true)
        let save = NSSavePanel()
        save.allowedContentTypes = [.pdf]
        save.nameFieldStringValue = "\(sheet.name) Kısayolları.pdf"
        save.title = "Kısayol sayfasını PDF olarak kaydet"
        save.level = .modalPanel
        guard save.runModal() == .OK, let url = save.url else { return }
        do {
            try MainActor.assumeIsolated { try Exporter.writePDF(sheet: sheet, groups: groups, to: url) }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
