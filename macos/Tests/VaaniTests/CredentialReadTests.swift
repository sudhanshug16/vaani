import XCTest
import VaaniCore
@testable import Vaani

final class CredentialReadTests: XCTestCase {
    func testAvailableCredentialDoesNotPrompt() async throws {
        let value = try await CredentialRead.value(noninteractive: { "fixture" }, authorize: { XCTFail("No approval needed"); return "unexpected" })
        XCTAssertEqual(value, "fixture")
    }
    func testApprovalIsRequestedOnceAfterDenial() async throws {
        var prompts = 0
        let value = try await CredentialRead.value(noninteractive: { throw KeychainAccessError.approvalRequired }, authorize: { prompts += 1; return "approved fixture" })
        XCTAssertEqual(value, "approved fixture"); XCTAssertEqual(prompts, 1)
    }
    func testOtherFailureNeverInitiatesApproval() async {
        do {
            _ = try await CredentialRead.value(noninteractive: { throw VaaniError.message("Unreadable") }, authorize: { XCTFail("Not an approval error"); return "unexpected" })
            XCTFail("Expected failure")
        } catch { XCTAssertEqual(error.localizedDescription, "Unreadable") }
    }
    func testCancellationAfterApprovalDoesNotReturnCredential() async {
        let task = Task {
            try await CredentialRead.value(noninteractive: { throw KeychainAccessError.approvalRequired }, authorize: {
                withUnsafeCurrentTask { $0?.cancel() }; return "fixture"
            })
        }
        do { _ = try await task.value; XCTFail("Cancelled read must not reach capture") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error") }
    }
}
