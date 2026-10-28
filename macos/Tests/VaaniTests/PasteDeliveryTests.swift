import AppKit
import XCTest
import VaaniCore
@testable import Vaani

final class PasteDeliveryTests: XCTestCase {
    @MainActor func testWaitsForActivationAndModifierReleaseBeforeValidation() async throws {
        var polls = 0, validations = 0
        try await PasteDelivery.waitUntilReady(isFrontmost: { polls += 1; return polls >= 2 },
            modifiersReleased: { polls >= 4 }, validate: {
                XCTAssertGreaterThanOrEqual(polls, 4); validations += 1
            })
        XCTAssertEqual(validations, 2)
    }
    @MainActor func testTransientUnreadyFieldRequiresTwoStableValidations() async throws {
        var validations = 0
        try await PasteDelivery.waitUntilReady(isFrontmost: { true }, modifiersReleased: { true }, validate: {
            validations += 1
            if validations <= 2 { throw VaaniError.message("Still activating") }
        })
        XCTAssertEqual(validations, 4)
    }
    @MainActor func testCancellationStopsPendingDelivery() async throws {
        let task = Task { @MainActor in
            try await PasteDelivery.waitUntilReady(isFrontmost: { false }, modifiersReleased: { true },
                validate: { XCTFail("Must not validate a background target") })
        }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }
    @MainActor func testPersistentInvalidDestinationTimesOutWithoutDelivery() async throws {
        do {
            try await PasteDelivery.waitUntilReady(isFrontmost: { true }, modifiersReleased: { true },
                validate: { throw VaaniError.message("Changed window") })
            XCTFail("Must not accept an invalid target")
        } catch { XCTAssertEqual(error.localizedDescription, "Changed window") }
    }
    @MainActor func testOverlayCannotTakeKeyboardOrMainWindowFocus() {
        _ = NSApplication.shared
        let panel = DictationPanel(contentRect: NSRect(x: 0, y: 0, width: 54, height: 36),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        panel.close()
    }
    @MainActor func testPanelResizePreservesBottomAndStaysOnscreen() throws {
        _ = NSApplication.shared
        let bounds = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let panel = DictationPanel(contentRect: NSRect(x: bounds.midX, y: bounds.minY + 70, width: 54, height: 36),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.orderFrontRegardless()
        let bottom = panel.frame.minY
        panel.setFrame(NSRect(x: panel.frame.minX, y: bottom - 141, width: 336, height: 177), display: true)
        XCTAssertEqual(panel.frame.minY, bottom, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, bounds.minY)
        panel.close()
    }
}
