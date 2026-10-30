import AppKit
import OSLog
import VaaniCore

/// Keep destination identity, never the destination's text or selection.
/// Cursor and selection changes are allowed inside the captured window.
@MainActor struct PasteDestination {
    let pid: pid_t
    private let originalWindow: WindowDestination?

    struct Capture {
        let destination: PasteDestination?
        let window: WindowDestination?
        let issue: String?
    }

    @MainActor struct WindowDestination {
        let pid: pid_t
        fileprivate let window: AXUIElement

        func validate() throws {
            try PasteWindowGuard(original: window, current: {
                PasteDestination.element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)
            }, same: { CFEqual($0, $1) }, checkProtectedFocus: {
                // Reject any password field that the app does expose, including
                // focused secure descendants of web-area wrappers.
                _ = try PasteDestination.resolvedElement(pid: pid)
            }).validate()
        }
    }

    static func capture(pid: pid_t) async throws -> Capture {
        guard AXIsProcessTrusted() else {
            return Capture(destination: nil, window: nil, issue: "Accessibility was unavailable when dictation started. Enable it, then start a new dictation from your text field. Copy remains available.")
        }
        let application = AXUIElementCreateApplication(pid)
        // Chromium/Electron can initially omit editable web content until an
        // assistive client requests its accessibility tree. Unsupported apps
        // simply reject this attribute. No app content or text is read.
        for attempt in 0..<7 {
            try Task.checkCancellation()
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                throw VaaniError.message("The destination app changed before recording started. Focus your text field and start again.")
            }
            if let focused = try resolvedElement(pid: pid) {
                try requireTextInput(focused)
                return Capture(destination: Self(pid: pid, originalWindow: element(application, kAXFocusedWindowAttribute).map { WindowDestination(pid: pid, window: $0) }), window: nil, issue: nil)
            }
            if attempt == 0 {
                AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            }
            if attempt < 6 { try await Task.sleep(for: .milliseconds(50)) }
        }
        let window = element(application, kAXFocusedWindowAttribute).map { WindowDestination(pid: pid, window: $0) }
        // Metadata only: never log field values, titles, selected text or audio.
        let focusRole = element(application, kAXFocusedUIElementAttribute).flatMap { string($0, kAXRoleAttribute) } ?? "unavailable"
        Logger(subsystem: "dev.vaani.mac", category: "Paste").notice("No editable AX focus. pid=\(pid) role=\(focusRole, privacy: .public) window=\(window != nil)")
        return Capture(destination: nil, window: window, issue: window == nil
            ? "The app did not expose its editor or window. Use Copy to insert your text."
            : "Editor details unavailable. Dictation will paste into this window's current input.")
    }
    func validate() throws {
        try originalWindow?.validate()
        if let focused = try Self.resolvedElement(pid: pid) { try Self.requireTextInput(focused) }
    }
    private static var resolver: PasteFocusResolver<AXUIElement> {
        PasteFocusResolver(role: { string($0, kAXRoleAttribute) }, subrole: { string($0, kAXSubroleAttribute) },
            parent: { element($0, kAXParentAttribute) }, children: { node in
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
                return value as? [AXUIElement] ?? []
            }, isFocused: { node in
                var value: CFTypeRef?
                return AXUIElementCopyAttributeValue(node, kAXFocusedAttribute as CFString, &value) == .success && (value as? Bool) == true
            }, same: { CFEqual($0, $1) })
    }
    private static func resolvedElement(pid: pid_t) throws -> AXUIElement? {
        // Some web renderers expose the leaf only through system-wide focus.
        for root in [AXUIElementCreateSystemWide(), AXUIElementCreateApplication(pid)] {
            guard let focus = element(root, kAXFocusedUIElementAttribute) else { continue }
            var owner: pid_t = 0
            guard AXUIElementGetPid(focus, &owner) == .success, owner == pid else { continue }
            if let input = try resolver.resolve(focus) { return input }
        }
        return nil
    }
    private static func element(_ root: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
    private static func requireTextInput(_ element: AXUIElement) throws {
        try resolver.requireNonsecureAncestry(element)
        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        guard subrole != kAXSecureTextFieldSubrole else { throw VaaniError.message("Dictation and paste are off in password fields.") }
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "") else {
            throw VaaniError.message("Focus a text field before dictating. This destination cannot be verified; use Copy for custom editors.")
        }
        var enabled: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled) == .success,
           let enabled = enabled as? Bool, !enabled {
            throw VaaniError.message("The destination field is disabled. Nothing was pasted.")
        }
    }
}
