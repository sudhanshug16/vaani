import XCTest
@testable import VaaniCore

final class SettingsSyncTests: XCTestCase {
    private let secret = Data(repeating: 7, count: 32).base64EncodedString()
    func testTailnetOnlyPairing() throws {
        for host in ["100.64.0.1", "100.127.255.254"] { XCTAssertNoThrow(try SyncPairing(host: host, secret: secret).validated()) }
        for host in ["127.0.0.1", "0.0.0.0", "192.168.1.1", "100.63.1.1", "100.128.1.1", "100.064.0.1", "100.64.0.256", "example.com"] {
            XCTAssertThrowsError(try SyncPairing(host: host, secret: secret).validated(), host)
        }
        XCTAssertThrowsError(try SyncPairing(host: "100.64.0.1", secret: "weak").validated())
    }
    func testEncryptionRejectsTamperingWrongKeyAndReflection() throws {
        let source = Data("private dictionary".utf8)
        let encrypted = try SettingsSync.seal(source, secret: secret, direction: "request")
        XCTAssertEqual(try SettingsSync.open(encrypted, secret: secret, direction: "request"), source)
        XCTAssertThrowsError(try SettingsSync.open(encrypted, secret: secret, direction: "response"))
        XCTAssertThrowsError(try SettingsSync.open(encrypted, secret: Data(repeating: 8, count: 32).base64EncodedString(), direction: "request"))
        var changed = encrypted; changed[15] ^= 1
        XCTAssertThrowsError(try SettingsSync.open(changed, secret: secret, direction: "request"))
        XCTAssertNotEqual(encrypted, try SettingsSync.seal(source, secret: secret, direction: "request"))
    }
    func testReplayAndExpiredRequestsAreRejected() throws {
        var guarder = SyncReplayGuard()
        let request = SyncRequest(timestamp: 1000, operation: "get")
        try guarder.accept(request, now: 1000)
        XCTAssertThrowsError(try guarder.accept(request, now: 1000))
        XCTAssertThrowsError(try SyncRequest(timestamp: 800, operation: "get").validated(now: 1000))
        XCTAssertThrowsError(try SyncRequest(timestamp: 1201, operation: "get").validated(now: 1000))
        XCTAssertThrowsError(try SyncRequest(operation: "offer").validated())
    }
    func testRevisionDetectsSettingsChangesAndFramesAreBounded() throws {
        var settings = SharedPreferences()
        let revision = try SettingsSync.revision(settings)
        settings.dictionary = ["Vaani"]
        XCTAssertNotEqual(revision, try SettingsSync.revision(settings))
        XCTAssertEqual(try SettingsSync.frame(Data(repeating: 0, count: 28)).prefix(4), Data([0, 0, 0, 28]))
        XCTAssertThrowsError(try SettingsSync.frame(Data(repeating: 0, count: 256_001)))
    }
}
