import AppKit
import Carbon
import VaaniCore

/// Wait for activation and key release, rather than racing a fixed delay. Never
/// retry a dispatched paste: doing so could duplicate text in opaque editors.
@MainActor enum PasteDelivery {
    static func waitUntilReady(isFrontmost: () -> Bool, modifiersReleased: () -> Bool,
                               validate: () throws -> Void) async throws {
        var stable = 0
        var lastError: Error?
        for _ in 0..<30 {
            try Task.checkCancellation()
            if isFrontmost(), modifiersReleased() {
                do { try validate(); stable += 1; if stable == 2 { return } }
                catch { lastError = error; stable = 0 }
            } else { stable = 0 }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw lastError ?? VaaniError.message("The destination is not ready, or shortcut keys are still held. Release the keys and try Paste again. Text is preserved.")
    }

    static var modifiersReleased: Bool {
        CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
    }

    private static func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func pasteMenuItem(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let value = attribute(app, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let bar = value as! AXUIElement
        var queue = [bar], count = 0
        while !queue.isEmpty, count < 256 {
            let node = queue.removeFirst(); count += 1
            if (attribute(node, kAXMenuItemCmdCharAttribute) as? String)?.lowercased() == "v",
               (attribute(node, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue == 0 {
                return node
            }
            queue.append(contentsOf: (attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(128))
        }
        return nil
    }
    static func requirePasteEnabled(pid: pid_t) throws {
        if let item = pasteMenuItem(pid: pid), (attribute(item, kAXEnabledAttribute) as? Bool) == false {
            throw VaaniError.message("Paste is disabled in the destination. Click its text input, then try Paste again. Text is preserved.")
        }
    }
    static func dispatch(pid: pid_t) throws {
        if let item = pasteMenuItem(pid: pid) {
            guard (attribute(item, kAXEnabledAttribute) as? Bool) != false else {
                throw VaaniError.message("Paste is disabled in the destination. Use Copy or focus its text input.")
            }
            let status = AXUIElementPerformAction(item, kAXPressAction as CFString)
            if status == .success { return }
            // A timeout might have delivered the action. Do not send a second
            // paste when the acknowledgement is uncertain.
            guard status == .actionUnsupported || status == .notImplemented else {
                throw VaaniError.message("The app did not acknowledge Paste (\(status.rawValue)). Check the input before trying again; text is on your clipboard.")
            }
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw VaaniError.message("Could not create a paste event. Use Copy.")
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(pid); up.postToPid(pid)
    }
}
