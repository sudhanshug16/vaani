import XCTest
import VaaniCore
@testable import Vaani

final class DictationIssueTests: XCTestCase {
    func testCreditsErrorHasBillingRecoveryAndRetainsProviderDetail() {
        let message = "Streaming failed: Credits exhausted. Visit the API Dashboard to review and manage your subscription."
        let issue = DictationIssue(message)
        XCTAssertEqual(issue.title, "Sarvam credits exhausted")
        XCTAssertEqual(issue.diagnostic, .creditsExhausted)
        XCTAssertTrue(issue.dashboard)
        XCTAssertTrue(issue.recovery.contains("Add credits"))
        XCTAssertEqual(issue.detail, message)
    }
    func testCommonFailuresHaveSpecificRecovery() {
        for (message, code) in [
            ("Keychain access needs approval", DiagnosticLog.Detail.keychainApproval),
            ("Streaming failed: invalid API key (401)", .providerAuthentication),
            ("Streaming failed: Too many requests (429)", .providerRateLimited),
            ("Sarvam did not begin a session within 15 seconds.", .networkTimeout),
            ("The Internet connection appears to be offline.", .networkUnavailable),
            ("Microphone access is required.", .microphonePermission),
            ("Your preferred microphone is missing.", .microphoneChoice)
        ] {
            let issue = DictationIssue(message)
            XCTAssertEqual(issue.diagnostic, code, message)
            XCTAssertFalse(issue.dashboard)
            XCTAssertFalse(issue.recovery.isEmpty)
        }
    }
    func testPolishingAuthenticationFailureDoesNotBlameSpeechKey() {
        let issue = DictationIssue("Post-processing failed: HTTP 401 unauthorized")
        XCTAssertEqual(issue.title, "Polishing failed")
        XCTAssertEqual(issue.diagnostic, .processing)
        XCTAssertFalse(issue.dashboard)
    }
    func testUnknownErrorStillShowsActualReason() {
        let issue = DictationIssue("Unexpected fixture failure")
        XCTAssertEqual(issue.recovery, "Unexpected fixture failure")
        XCTAssertEqual(issue.diagnostic, .unknownFailure)
    }
    func testErrorLayoutIsVisibleWithoutChangingNormalPill() {
        XCTAssertEqual(FloatingPanelLayout.size(active: false, controls: false), CGSize(width: 54, height: 36))
        XCTAssertEqual(FloatingPanelLayout.size(active: false, controls: false, error: true), CGSize(width: 350, height: 112))
    }
}
