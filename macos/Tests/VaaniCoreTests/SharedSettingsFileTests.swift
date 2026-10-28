import Foundation
import XCTest
@testable import VaaniCore

final class SharedSettingsFileTests: XCTestCase {
    func testUnicodeRoundTripDropsUnknownFields() throws {
        var preferences = SharedPreferences()
        preferences.prompt = "Keep café, नमस्ते and 👨‍👩‍👧‍👦."
        preferences.dictionary = ["C++", "say \"hello\"", "हिंदी", String(repeating: "😀", count: 120)]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: SharedSettingsFile.encode(preferences)) as? [String: Any])
        object["sarvamKey"] = "fixture-only"; object["setups"] = ["desk": "private"]
        let imported = try SharedSettingsFile.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(imported, preferences)
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: SharedSettingsFile.encode(imported)) as? [String: Any])
        XCTAssertNil(exported["sarvamKey"]); XCTAssertNil(exported["setups"])
    }
    func testLimitsCountUnicodeScalarsAcrossScripts() throws {
        var preferences = SharedPreferences()
        for word in [String(repeating: "😀", count: 120), String(repeating: "e\u{301}", count: 60)] {
            preferences.dictionary = [word]; XCTAssertNoThrow(try preferences.validated())
        }
        for word in [String(repeating: "😀", count: 121), String(repeating: "e\u{301}", count: 61)] {
            preferences.dictionary = [word]; XCTAssertThrowsError(try preferences.validated())
        }
    }
    func testOversizedFilesAndExportsAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vaani-large-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 32, count: 256_001).write(to: url)
        XCTAssertThrowsError(try SharedSettingsFile.read(from: url))
        var preferences = SharedPreferences()
        preferences.prompt = String(repeating: "😀", count: 16000)
        preferences.dictionary = Array(repeating: String(repeating: "😀", count: 120), count: 500)
        XCTAssertNoThrow(try preferences.validated())
        XCTAssertThrowsError(try SharedSettingsFile.encode(preferences))
    }
    func testInvalidEncodingSchemaAndJSONAreRejected() throws {
        var future = SharedPreferences(); future.schemaVersion = 2
        for bytes in [Data([0xc3, 0x28]), Data("not-json".utf8), try JSONEncoder().encode(future)] {
            XCTAssertThrowsError(try SharedSettingsFile.decode(bytes))
        }
    }
}
