import XCTest
import AppKit
import Carbon
import VaaniCore
@testable import Vaani

final class ShortcutSafetyTests: XCTestCase {
    func testModifierObserverCannotFilterSystemInput() {
        XCTAssertEqual(Shortcut.modifierTapOptions, .listenOnly)
    }
    func testNativeModifierTranslationKeepsExactChord() {
        XCTAssertEqual(Shortcut.carbonModifiers(0xc0000), UInt32(controlKey | optionKey))
        XCTAssertEqual(Shortcut.carbonModifiers(0x120000), UInt32(cmdKey | shiftKey))
        XCTAssertEqual(Shortcut.carbonModifiers(0x800000), UInt32(kEventKeyModifierFnMask))
        XCTAssertEqual(Shortcut.carbonModifiers(0), 0)
    }
    @MainActor func testNativeHotKeyReleasesDuringRecordingAndUnregister() throws {
        guard ProcessInfo.processInfo.environment["VAANI_NATIVE_SHORTCUT_TESTS"] == "1" else {
            throw XCTSkip("Opt in from a logged-in Mac session to test OS hot-key registration.")
        }
        let chord = DictationShortcut(keyCode: 90, modifiers: 0x1c0000, keyLabel: "F20")
        let first = Shortcut(permissionGranted: { true }), competitor = Shortcut(permissionGranted: { true })
        defer { first.unregister(); competitor.unregister() }
        XCTAssertTrue(first.register(chord)); XCTAssertTrue(first.ready)
        XCTAssertFalse(competitor.register(chord), "OS must arbitrate a conflicting chord")
        first.suspended = true
        XCTAssertTrue(competitor.register(chord), "Shortcut recorder must receive keys without a registered hot key consuming them")
        competitor.unregister()
        first.suspended = false
        XCTAssertTrue(first.ready)
        first.unregister()
        XCTAssertFalse(first.ready)
        XCTAssertTrue(competitor.register(chord), "Unregister must release the system hot key")
    }
    @MainActor func testPermissionRevocationReleasesHotKeyAndRestoreRecovers() throws {
        guard ProcessInfo.processInfo.environment["VAANI_NATIVE_SHORTCUT_TESTS"] == "1" else {
            throw XCTSkip("Opt in from a logged-in Mac session for native hot-key lifecycle checks.")
        }
        var trusted = true
        let first = Shortcut(permissionGranted: { trusted })
        let competitor = Shortcut(permissionGranted: { true })
        let chord = DictationShortcut(keyCode: 90, modifiers: 0x1c0000, keyLabel: "F20")
        defer { first.unregister(); competitor.unregister() }
        XCTAssertTrue(first.register(chord))
        trusted = false
        XCTAssertFalse(first.ready)
        // This is the same retry path the app runs when Accessibility is removed.
        XCTAssertFalse(first.register(chord))
        XCTAssertTrue(competitor.register(chord), "Revocation retry must release the old OS hot key")
        competitor.unregister()
        trusted = true
        XCTAssertTrue(first.register(chord)); XCTAssertTrue(first.ready)
    }
    @MainActor func testRevokedPermissionNeverInstallsModifierObserver() {
        let shortcut = Shortcut(permissionGranted: { false })
        defer { shortcut.unregister() }
        XCTAssertFalse(shortcut.register(.rightOption)); XCTAssertFalse(shortcut.ready)
        shortcut.suspended = true; shortcut.suspended = false
        XCTAssertFalse(shortcut.ready)
    }
}
