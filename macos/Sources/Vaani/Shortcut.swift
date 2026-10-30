import AppKit
import Carbon
import VaaniCore

// Ordinary shortcuts use the OS hot-key dispatcher. Modifier taps are passive
// observers: a busy UI thread must never hold the global keyboard/mouse stream.
final class Shortcut {
    private let permissionGranted: () -> Bool
    init(permissionGranted: @escaping () -> Bool = { AXIsProcessTrusted() }) { self.permissionGranted = permissionGranted }
    var action: (() -> Void)?
    var suspended = false {
        didSet {
            tapState = .init(); hotKeyDown = false
            guard oldValue != suspended, let choice, !choice.modifierOnly else { return }
            removeHotKey()
            if !suspended, permissionGranted() { _ = registerHotKey(choice) }
        }
    }
    static let modifierTapOptions: CGEventTapOptions = .listenOnly
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var hotKeyDown = false
    private var choice: DictationShortcut?
    private var tapState = ModifierShortcutTap()
    private static let hotKeyID = EventHotKeyID(signature: 0x56616E69, id: 1)
    var ready: Bool {
        guard permissionGranted(), let choice else { return false }
        return suspended || (choice.modifierOnly ? port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false : hotKey != nil)
    }
    func unregister() {
        precondition(Thread.isMainThread)
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        removeHotKey()
        port = nil; source = nil; choice = nil; tapState = .init()
    }
    func register(_ choice: DictationShortcut) -> Bool {
        precondition(Thread.isMainThread)
        unregister()
        guard permissionGranted() else { return false }
        self.choice = choice
        if !choice.modifierOnly { return suspended || registerHotKey(choice) }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: Self.modifierTapOptions,
            eventsOfInterest: mask, callback: { _, type, event, context in
                if Thread.isMainThread, let context {
                    Unmanaged<Shortcut>.fromOpaque(context).takeUnretainedValue().observe(type, event)
                }
                // Always return the original event. This observer cannot consume input.
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port); return false
        }
        self.port = port; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        Diagnostics.record(.shortcutRegistered)
        return ready
    }
    static func carbonModifiers(_ flags: UInt64) -> UInt32 {
        var result: UInt32 = 0
        for (flag, carbon) in [(UInt64(0x20000), UInt32(shiftKey)), (0x40000, UInt32(controlKey)),
                               (0x80000, UInt32(optionKey)), (0x100000, UInt32(cmdKey)), (0x800000, UInt32(kEventKeyModifierFnMask))] {
            if flags & flag != 0 { result |= carbon }
        }
        return result
    }
    private func registerHotKey(_ choice: DictationShortcut) -> Bool {
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard Thread.isMainThread, let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                id.signature == Shortcut.hotKeyID.signature, id.id == Shortcut.hotKeyID.id else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<Shortcut>.fromOpaque(context).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.hotKeyDown = false }
            else if !owner.suspended, !owner.hotKeyDown { owner.hotKeyDown = true; owner.enqueueAction() }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { removeHotKey(); return false }
        guard RegisterEventHotKey(UInt32(choice.keyCode), Self.carbonModifiers(choice.modifiers), Self.hotKeyID,
                                  GetApplicationEventTarget(), 0, &hotKey) == noErr else { removeHotKey(); return false }
        Diagnostics.record(.shortcutRegistered)
        return true
    }
    private func removeHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; hotKeyDown = false
    }
    private func enqueueAction() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.suspended, self.permissionGranted() else { return }
            Diagnostics.record(.shortcutTriggered); self.action?()
        }
    }
    private func observe(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Diagnostics.record(.shortcutTapDisabled); tapState = .init()
            // Do not re-enable from inside the callback: permission may have
            // just been revoked. The normal retry checks trust, unregisters old
            // resources, and only registers again after permission is restored.
            return
        }
        guard !suspended, let choice else { return }
        if type == .flagsChanged {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if tapState.receive(shortcut: choice, keyCode: UInt16(clamping: code), flags: event.flags.rawValue) { enqueueAction() }
        } else { tapState.cancel() }
    }
}
