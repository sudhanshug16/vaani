import XCTest
@testable import VaaniCore

final class LocalPreferencesTests: XCTestCase {
    private let builtin = Microphone(id: "builtin", name: "Laptop", deviceID: 1)
    private let usb = Microphone(id: "usb", name: "Desk microphone", deviceID: 2)

    func testFirstBuildSettingsMigrateWithoutLosingHardwareChoices() throws {
        let legacy: [String: Any] = [
            "shared": try JSONSerialization.jsonObject(with: JSONEncoder().encode(SharedPreferences())),
            "setups": ["desk": ["name": "Office", "microphoneUID": "usb"]], "autoPaste": true
        ]
        let migrated = try JSONDecoder().decode(LocalPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated.setups["desk"]?.microphoneUID, "usb")
        XCTAssertTrue(migrated.autoPaste)
        XCTAssertTrue(migrated.manualProfiles.isEmpty)
        XCTAssertNil(migrated.manualProfileID)
    }

    func testHomeAndOfficeCanUseDifferentMicsWithIdenticalHardware() {
        var state = LocalPreferences(manualProfiles: [
            "home": .init(name: "Home", microphoneUID: "builtin"),
            "office": .init(name: "Office", microphoneUID: "usb")
        ])
        state.manualProfileID = "home"
        XCTAssertEqual(MicrophonePolicy.decide(available: [builtin, usb], preference: state.preference(for: "same-hardware")), .remembered(builtin))
        state.manualProfileID = "office"
        XCTAssertEqual(MicrophonePolicy.decide(available: [builtin, usb], preference: state.preference(for: "same-hardware")), .remembered(usb))
    }

    func testManualProfilePersistsAcrossRestartAndHardwareChange() throws {
        let state = LocalPreferences(manualProfiles: ["home": .init(name: "Home", microphoneUID: "builtin")], manualProfileID: "home")
        let restored = try JSONDecoder().decode(LocalPreferences.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.preference(for: "new-hub")?.microphoneUID, "builtin")
    }

    func testMissingManualMicrophoneDoesNotUseAutomaticPreference() {
        let state = LocalPreferences(setups: ["desk": .init(name: "Automatic", microphoneUID: "builtin")],
            manualProfiles: ["office": .init(name: "Office", microphoneUID: "usb")], manualProfileID: "office")
        XCTAssertEqual(MicrophonePolicy.decide(available: [builtin], preference: state.preference(for: "desk")), .missingRemembered)
    }

    func testDanglingManualProfileDoesNotSilentlyFallThrough() {
        let state = LocalPreferences(setups: ["desk": .init(name: "Automatic", microphoneUID: "builtin")], manualProfileID: "deleted")
        XCTAssertEqual(MicrophonePolicy.decide(available: [builtin], preference: state.preference(for: "desk")), .missingRemembered)
    }

    func testReturningToAutomaticUsesHardwarePreference() {
        var state = LocalPreferences(setups: ["desk": .init(name: "Office", microphoneUID: "usb")],
            manualProfiles: ["home": .init(name: "Home", microphoneUID: "builtin")], manualProfileID: "home")
        state.manualProfileID = nil
        XCTAssertEqual(state.preference(for: "desk")?.microphoneUID, "usb")
        XCTAssertNil(state.preference(for: "unknown"))
    }

    func testSharedExportNeverIncludesManualProfiles() throws {
        let local = LocalPreferences(manualProfiles: ["home": .init(name: "Home", microphoneUID: "private-uid")], manualProfileID: "home")
        let exported = String(decoding: try JSONEncoder().encode(local.shared), as: UTF8.self)
        XCTAssertFalse(exported.contains("private-uid"))
        XCTAssertFalse(exported.contains("manualProfiles"))
    }
}
