import Foundation
import VaaniCore

enum PasteRoute: Equatable {
    case field, window
    static func choose(hasField: Bool, hasWindow: Bool) -> Self? {
        if hasField { return .field }
        return hasWindow ? .window : nil
    }
}

/// Paste is allowed in the captured native window's current focus.
struct PasteWindowGuard<Window> {
    let original: Window
    let current: () -> Window?
    let same: (Window, Window) -> Bool
    let checkProtectedFocus: () throws -> Void

    func validate() throws {
        try checkProtectedFocus()
        guard let focused = current(), same(original, focused) else {
            throw VaaniError.message("The destination window changed. Nothing was pasted; use Copy or start again in the intended window.")
        }
    }
}

/// Resolve the actual editor around an accessibility focus node. Web editors
/// can focus a text child, or expose a focused editor below a web-area wrapper.
/// Never choose an arbitrary editable sibling just because it is nearby.
struct PasteFocusResolver<Element> {
    let role: (Element) -> String?
    let subrole: (Element) -> String?
    let parent: (Element) -> Element?
    let children: (Element) -> [Element]
    let isFocused: (Element) -> Bool
    let same: (Element, Element) -> Bool

    private func isEditor(_ node: Element) -> Bool {
        ["AXTextField", "AXTextArea", "AXComboBox"].contains(role(node) ?? "")
    }

    func requireNonsecureAncestry(_ node: Element) throws {
        var current: Element? = node
        var visited: [Element] = []
        while let element = current, visited.count < 16 {
            guard !visited.contains(where: { same($0, element) }) else { return }
            visited.append(element)
            if subrole(element) == "AXSecureTextField" || role(element) == "AXSecureTextField" {
                throw VaaniError.message("Dictation and paste are off in password fields.")
            }
            current = parent(element)
        }
    }

    func resolve(_ focus: Element) throws -> Element? {
        try requireNonsecureAncestry(focus)
        if let editor = editorAncestor(focus) { return editor }
        // A focused web area/group can contain a focused editor. Bound traversal
        // and accept exactly one focused candidate, not the first text field.
        var queue = children(focus).map { ($0, 1) }
        var visited: [Element] = [focus]
        var matches: [Element] = []
        while !queue.isEmpty, visited.count < 128 {
            let (node, depth) = queue.removeFirst()
            guard !visited.contains(where: { same($0, node) }) else { continue }
            visited.append(node)
            if isFocused(node) {
                try requireNonsecureAncestry(node)
                if let editor = editorAncestor(node), !matches.contains(where: { same($0, editor) }) {
                    matches.append(editor)
                }
            }
            if depth < 6 { queue.append(contentsOf: children(node).prefix(128).map { ($0, depth + 1) }) }
        }
        guard queue.isEmpty else { return nil }
        return matches.count == 1 ? matches[0] : nil
    }

    private func editorAncestor(_ focus: Element) -> Element? {
        var current: Element? = focus
        var ancestors: [Element] = []
        while let node = current, ancestors.count < 16 {
            guard !ancestors.contains(where: { same($0, node) }) else { break }
            ancestors.append(node)
            if isEditor(node) { return node }
            current = parent(node)
        }
        return nil
    }
}
