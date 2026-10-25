import AppKit
import Carbon

/// System-wide hotkey through Carbon's RegisterEventHotKey (needs no permission).
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var onPress: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ spec: HotKeySpec?) {
        unregister()
        guard let spec else { return }
        installHandlerIfNeeded()
        var carbon: UInt32 = 0
        let flags = spec.flags
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        let id = EventHotKeyID(signature: OSType(0x4B53_5452), id: 1) // 'KSTR'
        RegisterEventHotKey(UInt32(spec.keyCode), carbon, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyCenter.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}

/// Watches the keyboard through a listen-only event tap and reports when ⌘ is
/// held on its own long enough, released, or interrupted by another key.
final class HoldMonitor {
    var delay: TimeInterval = 0.8
    var isEnabled = true
    var onHold: (() -> Void)?
    var onCommandReleased: (() -> Void)?
    /// keyCode + modifiers of any key pressed (used to dismiss the hold panel).
    var onKeyDown: ((Int, NSEvent.ModifierFlags) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: DispatchWorkItem?
    private var commandDown = false

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown,
                                    .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                let monitor = Unmanaged<HoldMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type, event)
            }
            return Unmanaged.passUnretained(event)
        }
        // The HID tap also sees ⌘⇥ and ⌘Space, which the system swallows before session taps.
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            if let port = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .listenOnly,
                                            eventsOfInterest: mask, callback: callback, userInfo: refcon) {
                tap = port
                break
            }
        }
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        cancelPending()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let f = event.flags
            let hasCommand = f.contains(.maskCommand)
            let onlyCommand = hasCommand && !f.contains(.maskShift) && !f.contains(.maskAlternate)
                && !f.contains(.maskControl) && !f.contains(.maskSecondaryFn)
            if onlyCommand, !commandDown {
                commandDown = true
                schedule()
            } else if !onlyCommand {
                cancelPending()
            }
            if !hasCommand, commandDown {
                commandDown = false
                onCommandReleased?()
            }
        case .keyDown:
            cancelPending()
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            onKeyDown?(code, Self.flags(event.flags))
        default:
            cancelPending()
        }
    }

    private func schedule() {
        cancelPending()
        guard isEnabled else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            let f = CGEventSource.flagsState(.combinedSessionState)
            let still = f.contains(.maskCommand) && !f.contains(.maskShift) && !f.contains(.maskAlternate)
                && !f.contains(.maskControl)
            if still { self.onHold?() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }

    private static func flags(_ f: CGEventFlags) -> NSEvent.ModifierFlags {
        var out: NSEvent.ModifierFlags = []
        if f.contains(.maskCommand) { out.insert(.command) }
        if f.contains(.maskAlternate) { out.insert(.option) }
        if f.contains(.maskControl) { out.insert(.control) }
        if f.contains(.maskShift) { out.insert(.shift) }
        return out
    }
}
