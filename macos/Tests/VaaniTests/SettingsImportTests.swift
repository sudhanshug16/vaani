import Foundation
import XCTest
import VaaniCore
@testable import Vaani

final class SettingsImportTests: XCTestCase {
    @MainActor func testFailedPersistenceRestoresActiveSettingsAndLocalChoices() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("vaani-import-\(UUID())")
        try Data("regular file, not a directory".utf8).write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = PreferenceStore(url: parent.appendingPathComponent("settings.json"))
        store.setups["desk"] = SetupPreference(name: "Office", microphoneUID: "usb")
        let before = store.local
        var incoming = SharedPreferences(); incoming.language = "kn-IN"
        XCTAssertThrowsError(try store.applyImportedSettings(incoming))
        XCTAssertEqual(store.shared, before.shared)
        XCTAssertEqual(store.setups, before.setups)
        XCTAssertNotNil(store.persistenceError)
    }
    @MainActor func testSuccessfulImportPersistsSharedSettingsAndPreservesLocalChoices() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vaani-import-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("settings.json")
        let store = PreferenceStore(url: url)
        store.setups["desk"] = SetupPreference(name: "Office", microphoneUID: "usb")
        store.autoPaste = true
        var incoming = SharedPreferences(); incoming.language = "kn-IN"; incoming.dictionary = ["Vaani"]
        try store.applyImportedSettings(incoming)
        let loaded = PreferenceStore(url: url)
        XCTAssertEqual(loaded.shared, incoming)
        XCTAssertEqual(loaded.setups, store.setups)
        XCTAssertTrue(loaded.autoPaste)
        var invalid = incoming; invalid.schemaVersion = 2
        XCTAssertThrowsError(try store.applyImportedSettings(invalid))
        XCTAssertEqual(store.shared, incoming)
        XCTAssertEqual(PreferenceStore(url: url).shared, incoming)
    }
}
