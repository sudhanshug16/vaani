import Foundation
import XCTest
import VaaniCore
@testable import Vaani

final class MicrophoneRecoveryTests: XCTestCase {
    private let builtin = Microphone(id: "builtin", name: "Laptop", deviceID: 1)
    private let usb = Microphone(id: "usb", name: "Desk microphone", deviceID: 2)
    private var temporaryFiles: [URL] = []
    @MainActor private func makeStore() -> PreferenceStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vaani-recovery-\(UUID()).json")
        temporaryFiles.append(url)
        return PreferenceStore(url: url)
    }
    override func tearDown() {
        for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }
        temporaryFiles = []
        super.tearDown()
    }

    @MainActor func testUnchangedInputCanStartDuringDeviceNotificationDebounce() {
        let model = AppModel(store: makeStore(), inventory: { ([self.builtin], ConnectedSetup(fingerprint: "laptop", summary: "Laptop")) }, observeDevices: false)
        model.devicesSettling = true
        model.error = "Audio devices are changing. Try dictation again in a moment."
        model.toggle()
        XCTAssertEqual(model.phase, .connecting, "An unchanged confirmed input must remain usable after Core Audio notifications")
        XCTAssertNil(model.error)
        model.cancel() // Cancel before the startup task can read keys or capture audio.
    }

    @MainActor func testActualSetupChangeStillWaitsForDeviceDebounce() {
        var setup = ConnectedSetup(fingerprint: "laptop", summary: "Laptop")
        let model = AppModel(store: makeStore(), inventory: { ([self.builtin], setup) }, observeDevices: false)
        model.devicesSettling = true
        setup = ConnectedSetup(fingerprint: "desk", summary: "Desk")
        model.toggle()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.setup.fingerprint, "laptop")
        XCTAssertTrue(model.error?.contains("Audio devices are changing") == true)
    }

    @MainActor func testRecoveredDeviceChangeClearsOnlyItsOwnStartError() {
        var setup = ConnectedSetup(fingerprint: "laptop", summary: "Laptop")
        let model = AppModel(store: makeStore(), inventory: { ([self.builtin], setup) }, observeDevices: false)
        model.devicesSettling = true
        setup = ConnectedSetup(fingerprint: "desk", summary: "Desk")
        model.toggle()
        XCTAssertNotNil(model.error)
        model.devicesSettling = false
        model.refreshDevices()
        XCTAssertNil(model.error, "A resolved transient notification must not leave the pill stuck orange")
        XCTAssertEqual(model.selectedUID, builtin.id)

        model.devicesSettling = true
        setup = ConnectedSetup(fingerprint: "laptop", summary: "Laptop")
        model.toggle()
        model.error = "Unrelated provider error"
        model.devicesSettling = false
        model.refreshDevices()
        XCTAssertEqual(model.error, "Unrelated provider error")
    }

    @MainActor func testMissingInputStartErrorClearsOnlyWhenInputReturns() {
        var inputs: [Microphone] = []
        let model = AppModel(store: makeStore(), inventory: { (inputs, ConnectedSetup(fingerprint: "laptop", summary: "Laptop")) }, observeDevices: false)
        model.toggle()
        XCTAssertEqual(model.error, "No microphone is available.")
        model.refreshDevices()
        XCTAssertNotNil(model.error)
        inputs = [builtin]; model.refreshDevices()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.selectedUID, builtin.id)
    }

    @MainActor func testActualInputChangeStillWaitsForDeviceDebounce() {
        var inputs = [builtin]
        let model = AppModel(store: makeStore(), inventory: { (inputs, ConnectedSetup(fingerprint: "laptop", summary: "Laptop")) }, observeDevices: false)
        model.devicesSettling = true
        inputs = [builtin, usb]
        model.toggle()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.selectedUID, builtin.id)
        XCTAssertTrue(model.error?.contains("Audio devices are changing") == true)
    }

    @MainActor func testEmptySelectionReappliesPolicyForUnchangedSingleInput() {
        let model = AppModel(store: makeStore(), inventory: { ([self.builtin], ConnectedSetup(fingerprint: "laptop", summary: "Laptop")) }, observeDevices: false)
        model.selectedUID = ""
        model.toggle()
        XCTAssertEqual(model.selectedUID, builtin.id)
        XCTAssertEqual(model.phase, .connecting)
        model.cancel()
    }

    @MainActor func testEmptySelectionRecoveryNeverSubstitutesMissingRememberedInput() {
        let store = makeStore()
        store.setups["laptop"] = SetupPreference(name: "Home", microphoneUID: usb.id)
        let model = AppModel(store: store, inventory: { ([self.builtin], ConnectedSetup(fingerprint: "laptop", summary: "Laptop")) }, observeDevices: false)
        model.toggle()
        XCTAssertEqual(model.selectedUID, "")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.error?.contains("preferred microphone is missing") == true)
    }

    @MainActor func testMissingPreferredMicNeverSubstitutesAndReturnClearsWarning() {
        let store = makeStore()
        store.setups["desk"] = SetupPreference(name: "Office", microphoneUID: usb.id)
        var inputs = [builtin, usb]
        let model = AppModel(store: store, inventory: { (inputs, ConnectedSetup(fingerprint: "desk", summary: "Desk")) }, observeDevices: false)
        XCTAssertEqual(model.selectedUID, usb.id)
        inputs = [builtin]; model.refreshDevices()
        XCTAssertEqual(model.selectedUID, "")
        XCTAssertTrue(model.needsChoice)
        XCTAssertTrue(model.statusNotice?.contains("preferred microphone is missing") == true)
        inputs = [usbWithNewPort(), builtin]; model.refreshDevices()
        XCTAssertEqual(model.selectedUID, usb.id)
        XCTAssertEqual(model.microphones.first { $0.id == usb.id }?.deviceID, 27)
        XCTAssertFalse(model.needsChoice)
        XCTAssertNil(model.microphoneNotice)
        XCTAssertNil(model.statusNotice, "Reconnection must clear the obsolete missing-input warning")
    }
    private func usbWithNewPort() -> Microphone { Microphone(id: usb.id, name: usb.name, deviceID: 27) }

    @MainActor func testNoInputsThenSingleInputRecoversWithoutErasingUnrelatedFeedback() {
        var inputs: [Microphone] = []
        let model = AppModel(store: makeStore(), inventory: { (inputs, ConnectedSetup(fingerprint: "laptop", summary: "Laptop")) }, observeDevices: false)
        model.notice = "Copied."
        XCTAssertEqual(model.statusNotice, "No microphone is available.")
        inputs = [builtin]; model.refreshDevices()
        XCTAssertEqual(model.selectedUID, builtin.id)
        XCTAssertFalse(model.needsChoice)
        XCTAssertEqual(model.statusNotice, "Copied.")
    }

    @MainActor func testManualProfileMissingInputWarningOutranksProfileSuccess() {
        let store = makeStore()
        store.setups["desk"] = SetupPreference(name: "Desk", microphoneUID: builtin.id)
        store.manualProfiles["office"] = SetupPreference(name: "Office", microphoneUID: usb.id)
        let model = AppModel(store: store, inventory: { ([self.builtin], ConnectedSetup(fingerprint: "desk", summary: "Desk")) }, observeDevices: false)
        model.useProfile("office")
        XCTAssertEqual(model.selectedUID, "")
        XCTAssertTrue(model.needsChoice)
        XCTAssertTrue(model.statusNotice?.contains("preferred microphone is missing") == true)
        model.useProfile("")
        XCTAssertEqual(model.selectedUID, builtin.id)
        XCTAssertNil(model.microphoneNotice)
        XCTAssertEqual(model.statusNotice, "Automatic setup matching enabled.")
        XCTAssertNil(store.manualProfileID)
    }

    @MainActor func testSavingChoiceRevalidatesSetupBeforeWritingPreferences() {
        let store = makeStore()
        var setup = ConnectedSetup(fingerprint: "desk", summary: "Desk")
        var inputs = [builtin, usb]
        let model = AppModel(store: store, inventory: { (inputs, setup) }, observeDevices: false)
        model.selectedUID = usb.id
        // Hardware changes before the OS notification/debounce reaches the UI.
        setup = ConnectedSetup(fingerprint: "laptop", summary: "Laptop"); inputs = [builtin]
        model.rememberMicrophone()
        XCTAssertTrue(store.setups.isEmpty, "A stale choice must not be saved under the old setup")
        XCTAssertEqual(model.setup.fingerprint, "laptop")
        XCTAssertEqual(model.selectedUID, builtin.id)
        XCTAssertTrue(model.error?.contains("Audio setup changed") == true)
        model.chooseAndRememberMicrophone(builtin.id)
        XCTAssertNil(model.error, "A valid new choice resolves the stale-setup error")
        XCTAssertEqual(store.setups["laptop"]?.microphoneUID, builtin.id)
    }

    @MainActor func testUnknownSetupCanBeRememberedAndReturningSetupsRestoreIndependentChoices() {
        let store = makeStore()
        store.setups["desk"] = SetupPreference(name: "Desk", microphoneUID: usb.id)
        var setup = ConnectedSetup(fingerprint: "laptop", summary: "Laptop")
        let model = AppModel(store: store, inventory: { ([self.builtin, self.usb], setup) }, observeDevices: false)
        XCTAssertTrue(model.needsChoice)
        XCTAssertEqual(model.statusNotice, "Choose a microphone for this setup.")
        model.chooseAndRememberMicrophone(builtin.id)
        XCTAssertFalse(model.needsChoice)
        XCTAssertNil(model.microphoneNotice)
        XCTAssertEqual(model.statusNotice, "Microphone preference saved.")
        setup = ConnectedSetup(fingerprint: "desk", summary: "Desk"); model.refreshDevices()
        XCTAssertEqual(model.selectedUID, usb.id)
        setup = ConnectedSetup(fingerprint: "laptop", summary: "Laptop"); model.refreshDevices()
        XCTAssertEqual(model.selectedUID, builtin.id)
        XCTAssertEqual(store.setups["desk"]?.microphoneUID, usb.id)
    }

    @MainActor func testInputLostBeforeSaveCannotBeRememberedOrMadeIntoAProfile() {
        for separateProfile in [false, true] {
            let store = makeStore()
            var inputs = [builtin, usb]
            let model = AppModel(store: store, inventory: { (inputs, ConnectedSetup(fingerprint: "desk", summary: "Desk")) }, observeDevices: false)
            model.selectedUID = usb.id; model.setupName = "Office"
            inputs = [builtin] // Same monitor/hub signature; selected input disappeared.
            if separateProfile { model.createManualProfile() } else { model.rememberMicrophone() }
            XCTAssertTrue(store.setups.isEmpty)
            XCTAssertTrue(store.manualProfiles.isEmpty)
            XCTAssertNil(store.manualProfileID)
            XCTAssertEqual(model.selectedUID, builtin.id)
            XCTAssertTrue(model.error?.contains("Audio setup changed") == true)
        }
    }

    @MainActor func testSetupTransitionIsDeferredWhileConnecting() {
        var setup = ConnectedSetup(fingerprint: "laptop", summary: "Laptop")
        let store = makeStore()
        store.setups["desk"] = SetupPreference(name: "Office", microphoneUID: usb.id)
        let model = AppModel(store: store, inventory: { ([self.builtin, self.usb], setup) }, observeDevices: false)
        model.chooseAndRememberMicrophone(builtin.id)
        model.phase = .connecting
        setup = ConnectedSetup(fingerprint: "desk", summary: "Desk"); model.refreshDevices()
        XCTAssertEqual(model.selectedUID, builtin.id)
        XCTAssertEqual(model.setup.fingerprint, "laptop")
        model.phase = .idle; model.refreshDevices()
        XCTAssertEqual(model.selectedUID, usb.id)
        XCTAssertEqual(model.setup.fingerprint, "desk")
    }

    @MainActor func testInputLossDuringListeningStopsAndPreservesText() {
        let store = makeStore()
        store.setups["desk"] = SetupPreference(name: "Office", microphoneUID: usb.id)
        var inputs = [builtin, usb]
        let model = AppModel(store: store, inventory: { (inputs, ConnectedSetup(fingerprint: "desk", summary: "Desk")) }, observeDevices: false)
        model.rawText = "Kal office mein"; model.phase = .listening
        inputs = [builtin]; model.refreshDevices()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.rawText, "Kal office mein")
        XCTAssertEqual(model.output, "Kal office mein")
        XCTAssertTrue(model.error?.contains("disconnected") == true)
        XCTAssertEqual(model.selectedUID, "")
        XCTAssertTrue(model.needsChoice)
    }

    @MainActor func testReadableSetupNameKeepsRoutingAndCustomNames() {
        let store = makeStore()
        let model = AppModel(store: store, inventory: { ([self.builtin], ConnectedSetup(fingerprint: "desk", summary: "DELL + Hub")) }, observeDevices: false)
        XCTAssertEqual(model.setupName, "DELL + Hub")
        model.rememberMicrophone()
        XCTAssertEqual(store.setups["desk"]?.name, "DELL + Hub")
        XCTAssertEqual(store.setups["desk"]?.microphoneUID, builtin.id)
        model.setupName = "Office"; model.rememberMicrophone(); model.refreshDevices(force: true)
        XCTAssertEqual(model.setupName, "Office")
    }

}
