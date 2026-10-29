import XCTest
import VaaniCore
@testable import Vaani

@MainActor final class SharingStartupTests: XCTestCase {
    private func store() -> PreferenceStore {
        PreferenceStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("settings.json"))
    }
    func testApprovalFailureClearsStartingAndAllowsRetry() async {
        var attempts = 0
        let sync = SettingsSyncController(store: store(), isBusy: { false }, loadSharingSecret: {
            attempts += 1; throw KeychainAccessError.approvalRequired
        }, addresses: { ["100.64.0.1"] })
        sync.host = "100.64.0.1"
        sync.start(); sync.start()
        XCTAssertTrue(sync.starting)
        for _ in 0..<100 where sync.starting { await Task.yield() }
        XCTAssertEqual(attempts, 1); XCTAssertFalse(sync.starting); XCTAssertFalse(sync.running)
        XCTAssertTrue(sync.message.contains("Keychain")); XCTAssertTrue(sync.pairingCode.isEmpty)
        sync.start()
        for _ in 0..<100 where sync.starting { await Task.yield() }
        XCTAssertEqual(attempts, 2)
    }
    func testStopDuringApprovalCannotStartListenerLater() async throws {
        var waiting: CheckedContinuation<String, Error>?
        let sync = SettingsSyncController(store: store(), isBusy: { false }, loadSharingSecret: {
            try await withCheckedThrowingContinuation { waiting = $0 }
        }, addresses: { ["100.64.0.1"] })
        sync.host = "100.64.0.1"; sync.start()
        for _ in 0..<100 where waiting == nil { await Task.yield() }
        let approval = try XCTUnwrap(waiting)
        sync.stop()
        approval.resume(returning: Data(repeating: 7, count: 32).base64EncodedString())
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(sync.starting); XCTAssertFalse(sync.running); XCTAssertTrue(sync.pairingCode.isEmpty)
        XCTAssertTrue(sync.message.contains("Sharing stopped"))
    }
    func testDisconnectedTailscaleNeverRequestsKeychainApproval() async {
        let sync = SettingsSyncController(store: store(), isBusy: { false }, loadSharingSecret: {
            XCTFail("No Keychain prompt without a valid Tailscale address"); return ""
        }, addresses: { [] })
        sync.start()
        await Task.yield()
        XCTAssertFalse(sync.starting); XCTAssertFalse(sync.running)
    }
}
