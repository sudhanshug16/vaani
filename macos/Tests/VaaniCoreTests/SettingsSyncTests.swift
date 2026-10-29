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
    func testCredentialSyncIsEncryptedAndVersionedSeparatelyFromSettings() throws {
        let keys = SyncCredentials(sarvam: "test-speech-key", processing: "test-polish-key")
        let request = SyncRequest(operation: "offer", expectedRevision: String(repeating: "a", count: 64), settings: SharedPreferences(), credentials: keys, version: 2)
        XCTAssertNoThrow(try request.validated())
        let bytes = try JSONEncoder().encode(request)
        let sealed = try SettingsSync.seal(bytes, secret: secret, direction: "request")
        XCTAssertNil(sealed.range(of: Data("test-speech-key".utf8)))
        let decoded = try JSONDecoder().decode(SyncRequest.self, from: SettingsSync.open(sealed, secret: secret, direction: "request"))
        XCTAssertEqual(decoded.credentials, keys)
        XCTAssertFalse(String(describing: keys).contains("test-speech-key"))
        XCTAssertThrowsError(try SyncRequest(operation: "get", credentials: keys).validated())
        XCTAssertThrowsError(try SyncCredentials(sarvam: String(repeating: "x", count: 16385)).validated())
        XCTAssertNotEqual(try SettingsSync.revision(SharedPreferences(), credentials: keys), try SettingsSync.revision(SharedPreferences(), credentials: SyncCredentials(sarvam: "changed")))
    }
    func testMissingKeysPreserveDestinationAndFailuresRollBack() throws {
        var saved = ["sarvam": "old-speech", "processing": "old-polish"]
        try SyncCredentials(sarvam: "new-speech", processing: " ").apply(read: { saved[$0] ?? "" }, save: { saved[$0] = $1 }, persist: {})
        XCTAssertEqual(saved, ["sarvam": "new-speech", "processing": "old-polish"])
        let before = saved
        XCTAssertThrowsError(try SyncCredentials(sarvam: "another", processing: "new-polish").apply(read: { saved[$0] ?? "" }, save: { saved[$0] = $1 }, persist: { throw VaaniError.message("Disk failure") }))
        XCTAssertEqual(saved, before)
        XCTAssertThrowsError(try SyncCredentials(sarvam: "another", processing: "bad").apply(read: { saved[$0] ?? "" }, save: { account, value in
            if value == "bad" { throw VaaniError.message("Keychain failure") }; saved[account] = value
        }, persist: { XCTFail("Settings must not save after key failure") }))
        XCTAssertEqual(saved, before)
    }
}
