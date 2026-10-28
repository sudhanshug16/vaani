import XCTest
@testable import VaaniCore

final class ShortcutTests: XCTestCase {
    func testRightOptionWithoutDeviceSpecificSideBits() {
        var tap = ModifierShortcutTap()
        XCTAssertFalse(tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0x80000))
        XCTAssertTrue(tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0))
        XCTAssertFalse(tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0))
    }
    func testDeviceSideBitsAndOtherOptionNeverTriggerWrongSide() {
        var tap = ModifierShortcutTap()
        XCTAssertFalse(tap.receive(shortcut: .rightOption, keyCode: 58, flags: 0x80020))
        XCTAssertFalse(tap.receive(shortcut: .rightOption, keyCode: 58, flags: 0))
        XCTAssertFalse(tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0x80040))
        XCTAssertFalse(tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0x80040))
        XCTAssertTrue(tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0))
    }
    func testModifierTypingAndClicksCancelTap() {
        var tap = ModifierShortcutTap()
        _ = tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0x80000)
        tap.cancel()
        XCTAssertFalse(tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0))
        _ = tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0x80000)
        _ = tap.receive(shortcut: .rightOption, keyCode: 55, flags: 0x180000)
        _ = tap.receive(shortcut: .rightOption, keyCode: 55, flags: 0x80000)
        XCTAssertFalse(tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0))
    }
    func testModifiedPressAndSimultaneousOptionKeysDoNotTrigger() {
        var tap = ModifierShortcutTap()
        _ = tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0xc0040)
        XCTAssertFalse(tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0x40000))
        _ = tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0x80060)
        XCTAssertFalse(tap.receive(shortcut: .rightOption, keyCode: 61, flags: 0x80020))
    }
    func testOtherStandaloneModifiersAndUnpairedRelease() {
        for (code, mask) in [(UInt16(62), UInt64(0x40000)), (54, 0x100000), (60, 0x20000), (63, 0x800000)] {
            var tap = ModifierShortcutTap()
            let shortcut = DictationShortcut(keyCode: code, modifiers: 0, keyLabel: "Modifier")
            XCTAssertFalse(tap.receive(shortcut: shortcut, keyCode: code, flags: 0))
            XCTAssertFalse(tap.receive(shortcut: shortcut, keyCode: code, flags: mask))
            XCTAssertTrue(tap.receive(shortcut: shortcut, keyCode: code, flags: 0))
        }
    }
    func testCustomShortcutPersistsAndNormalizesFlags() throws {
        let custom = DictationShortcut(keyCode: 40, modifiers: 0x180040, keyLabel: "K")
        XCTAssertEqual(custom.modifiers, 0x180000)
        XCTAssertEqual(custom.label, "⌥⌘K")
        let data = try JSONEncoder().encode(LocalPreferences(shortcut: custom))
        XCTAssertEqual(try JSONDecoder().decode(LocalPreferences.self, from: data).shortcut, custom)
    }
    func testFunctionKeyIgnoresAutomaticFnFlagAndChordMatchesExactly() {
        let function = DictationShortcut(keyCode: 100, modifiers: 0x800000, keyLabel: "F8")
        XCTAssertEqual(function.label, "F8")
        XCTAssertTrue(function.matches(keyCode: 100, flags: 0))
        XCTAssertTrue(function.matches(keyCode: 100, flags: 0x800000))
        XCTAssertFalse(function.matches(keyCode: 100, flags: 0x20000))
        let chord = DictationShortcut(keyCode: 40, modifiers: 0x120000, keyLabel: "K")
        XCTAssertTrue(chord.matches(keyCode: 40, flags: 0x120004))
        XCTAssertFalse(chord.matches(keyCode: 40, flags: 0x100000))
        XCTAssertFalse(chord.matches(keyCode: 41, flags: 0x120000))
    }
    func testModifierOnlyChordAcceptsEitherPressAndReleaseOrder() {
        let chord = DictationShortcut(keyCode: 61, modifiers: 0x40000, keyLabel: "Right Option")
        for firstCode in [UInt16(59), 61] {
            for releaseCode in [UInt16(59), 61] {
                var tap = ModifierShortcutTap()
                let firstFlags: UInt64 = firstCode == 59 ? 0x40000 : 0x80000
                XCTAssertFalse(tap.receive(shortcut: chord, keyCode: firstCode, flags: firstFlags))
                XCTAssertFalse(tap.receive(shortcut: chord, keyCode: firstCode == 59 ? 61 : 59, flags: 0xc0000))
                XCTAssertTrue(tap.receive(shortcut: chord, keyCode: releaseCode, flags: releaseCode == 59 ? 0x80000 : 0x40000))
                XCTAssertFalse(tap.receive(shortcut: chord, keyCode: releaseCode == 59 ? 61 : 59, flags: 0))
            }
        }
    }
    func testLegacyShortcutSettingsMigrate() throws {
        let data = try JSONEncoder().encode(LocalPreferences())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (value, expected) in [("rightOption", DictationShortcut.rightOption), ("controlOptionSpace", .controlOptionSpace)] {
            object["shortcut"] = value
            XCTAssertEqual(try JSONDecoder().decode(LocalPreferences.self, from: JSONSerialization.data(withJSONObject: object)).shortcut, expected)
        }
        object.removeValue(forKey: "shortcut")
        XCTAssertEqual(try JSONDecoder().decode(LocalPreferences.self, from: JSONSerialization.data(withJSONObject: object)).shortcut, .controlOptionSpace)
    }
}
