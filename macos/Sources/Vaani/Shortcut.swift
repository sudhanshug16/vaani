import AppKit
import Carbon
import VaaniCore

// Synchronous event-tap state is confined to the main run loop. Keeping this
// adapter nonisolated avoids a Swift executor probe inside a C event callback.
// Actions are enqueued onto the main queue rather than performed in the tap.
final class Shortcut {
    var action: (() -> Void)?
    var suspended = false { didSet { tapState = .init(); firedKey = nil } }
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var choice: DictationShortcut?
    private var tapState = ModifierShortcutTap()
    private var firedKey: Int64?
    var ready: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    func unregister() {
        precondition(Thread.isMainThread)
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil; source = nil; choice = nil; tapState = .init(); firedKey = nil
    }
    func register(_ choice: DictationShortcut) -> Bool {
        precondition(Thread.isMainThread)
        unregister()
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard Thread.isMainThread, let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<Shortcut>.fromOpaque(context).takeUnretainedValue()
                let consumed = owner.handle(type, event)
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port); return false
        }
        self.port = port; self.source = source; self.choice = choice
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        Diagnostics.record(.shortcutRegistered)
        return ready
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Diagnostics.record(.shortcutTapDisabled)
            tapState = .init(); firedKey = nil
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        guard !suspended, let choice else { return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged {
            if choice.modifierOnly, tapState.receive(shortcut: choice, keyCode: UInt16(clamping: code), flags: event.flags.rawValue) {
                DispatchQueue.main.async { [weak self] in Diagnostics.record(.shortcutTriggered); self?.action?() }
            }
            return false
        }
        if type == .keyUp, firedKey == code { firedKey = nil; return true }
        if type == .keyDown {
            tapState.cancel()
            if firedKey == code { return true }
            if !choice.modifierOnly, choice.matches(keyCode: UInt16(clamping: code), flags: event.flags.rawValue),
                event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                firedKey = code
                DispatchQueue.main.async { [weak self] in Diagnostics.record(.shortcutTriggered); self?.action?() }
                return true
            }
        } else { tapState.cancel() }
        return false
    }
}
