import Foundation

public struct DictationShortcut: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: UInt64
    public let keyLabel: String
    public static let modifierFlags: UInt64 = 0x9e0000 // Shift, Control, Option, Command, Fn
    public static let controlOptionSpace = Self(keyCode: 49, modifiers: 0xc0000, keyLabel: "Space")
    public static let rightOption = Self(keyCode: 61, modifiers: 0, keyLabel: "Right Option")
    public init(keyCode: UInt16, modifiers: UInt64, keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = Self.normalizedModifiers(keyCode: keyCode, flags: modifiers) & ~(Self.modifierMask(keyCode) ?? 0); self.keyLabel = keyLabel
    }
    public var modifierOnly: Bool { Self.modifierMask(keyCode) != nil }
    public var label: String {
        let names: [(UInt64, String)] = [(0x40000, "⌃"), (0x80000, "⌥"), (0x20000, "⇧"), (0x100000, "⌘"), (0x800000, "Fn ")]
        return names.filter { modifiers & $0.0 != 0 }.map(\.1).joined() + keyLabel
    }
    public static func normalizedModifiers(keyCode: UInt16, flags: UInt64) -> UInt64 {
        // macOS attaches Fn automatically to function/navigation key events.
        let functionKeys: Set<UInt16> = [64,79,80,90,96,97,98,99,100,101,103,105,106,107,109,111,113,114,115,116,117,118,119,120,121,122,123,124,125,126]
        return flags & modifierFlags & ~(functionKeys.contains(keyCode) ? 0x800000 : 0)
    }
    public func matches(keyCode: UInt16, flags: UInt64) -> Bool {
        self.keyCode == keyCode && Self.normalizedModifiers(keyCode: keyCode, flags: flags) == modifiers
    }
    public static func modifierMask(_ code: UInt16) -> UInt64? {
        switch code {
        case 54, 55: 0x100000
        case 56, 60: 0x20000
        case 58, 61: 0x80000
        case 59, 62: 0x40000
        case 63: 0x800000
        default: nil
        }
    }
    public static func sideMask(_ code: UInt16) -> UInt64 {
        switch code {
        case 54: 0x10
        case 55: 0x8
        case 56: 0x2
        case 60: 0x4
        case 58: 0x20
        case 61: 0x40
        case 59: 0x1
        case 62: 0x2000
        default: 0
        }
    }
    public init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            switch legacy {
            case "rightOption": self = .rightOption
            case "controlOptionSpace": self = .controlOptionSpace
            default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown shortcut"))
            }
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(keyCode: try values.decode(UInt16.self, forKey: .keyCode), modifiers: try values.decode(UInt64.self, forKey: .modifiers), keyLabel: try values.decode(String.self, forKey: .keyLabel))
    }
}

/// Modifier taps use the changed physical key code, including when AppKit omits
/// device-specific side bits. Other keys/clicks cancel a tap used for typing.
public struct ModifierShortcutTap {
    private var down = false
    private var armed = false
    private var interrupted = false
    public init() {}
    public mutating func cancel() { armed = false; interrupted = true }
    public mutating func receive(shortcut: DictationShortcut, keyCode: UInt16, flags: UInt64) -> Bool {
        guard let mask = DictationShortcut.modifierMask(shortcut.keyCode) else { return false }
        let normalized = flags & DictationShortcut.modifierFlags
        let expected = mask | shortcut.modifiers
        if keyCode != shortcut.keyCode {
            guard down else { return false }
            if DictationShortcut.modifierMask(keyCode) == mask || normalized & ~expected != 0 {
                cancel(); return false
            }
            if armed && normalized & expected != expected && !interrupted {
                cancel(); return true // modifier chord: first member released
            }
            if normalized == expected && !interrupted { armed = true }
            return false
        }
        let side = DictationShortcut.sideMask(keyCode)
        let anySide = flags & 0x207f
        let opposite: UInt64
        switch keyCode {
        case 54: opposite = 0x8
        case 55: opposite = 0x10
        case 56: opposite = 0x4
        case 60: opposite = 0x2
        case 58: opposite = 0x40
        case 61: opposite = 0x20
        case 59: opposite = 0x2000
        case 62: opposite = 0x1
        default: opposite = 0
        }
        let pressed: Bool
        if flags & mask == 0 { pressed = false }
        else if side != 0 && anySide & (side | opposite) != 0 { pressed = flags & side != 0 }
        else { pressed = !down }
        let invalid = normalized & ~expected != 0 || anySide & opposite != 0
        if pressed && !down { interrupted = invalid; armed = !invalid && normalized == expected }
        if invalid { cancel() }
        let fire = down && !pressed && armed && !interrupted
        down = pressed
        if !pressed { armed = false; interrupted = false }
        return fire
    }
}
