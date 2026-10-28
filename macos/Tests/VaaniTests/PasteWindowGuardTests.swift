import XCTest
import VaaniCore
@testable import Vaani

final class PasteWindowGuardTests: XCTestCase {
    func testAutomaticPasteUsesCapturedWindowWhenEditorIsOpaque() {
        XCTAssertEqual(PasteRoute.choose(hasField: false, hasWindow: true), .window)
        XCTAssertEqual(PasteRoute.choose(hasField: true, hasWindow: true), .field)
    }
    func testExplicitPasteUsesWindowOnlyWhenFieldUnavailable() {
        XCTAssertEqual(PasteRoute.choose(hasField: false, hasWindow: true), .window)
        XCTAssertEqual(PasteRoute.choose(hasField: true, hasWindow: true), .field)
        XCTAssertNil(PasteRoute.choose(hasField: false, hasWindow: false))
    }
    func testOriginalWindowAllowsExplicitAppPaste() throws {
        var checkedProtectedFocus = false
        let guardrail = PasteWindowGuard(original: 1, current: { 1 }, same: ==,
            checkProtectedFocus: { checkedProtectedFocus = true })
        try guardrail.validate()
        XCTAssertTrue(checkedProtectedFocus)
    }
    func testChangedOrMissingWindowRejectsPaste() {
        for current in [2, nil] as [Int?] {
            XCTAssertThrowsError(try PasteWindowGuard(original: 1, current: { current }, same: ==,
                checkProtectedFocus: {}).validate())
        }
    }
    func testProtectedInputRejectsEvenMatchingWindow() {
        XCTAssertThrowsError(try PasteWindowGuard(original: 1, current: { 1 }, same: ==,
            checkProtectedFocus: { throw VaaniError.message("Password input") }).validate()) { error in
            XCTAssertEqual(error.localizedDescription, "Password input")
        }
    }
}
