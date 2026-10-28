import CoreAudio
import Foundation
import XCTest
@testable import Vaani

/// Real HAL inventory regression, without starting IO or capturing audio.
final class PrivateAggregateTests: XCTestCase {
    private func makeAggregate(isPrivate: Bool) throws -> AudioDeviceID {
        let inputs = DeviceInventory.microphones()
        guard let source = inputs.first(where: { mic in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var transport: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(mic.deviceID, &address, 0, nil, &size, &transport) == noErr && transport == kAudioDeviceTransportTypeBuiltIn
        }) else { throw XCTSkip("No built-in input is available for an aggregate inventory test") }
        let uid = "dev.vaani.test.aggregate.\(UUID().uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vaani temporary inventory test",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: isPrivate ? 1 : 0,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: source.id]],
            kAudioAggregateDeviceMainSubDeviceKey: source.id
        ]
        var device: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &device)
        guard status == noErr else { throw XCTSkip("HAL aggregate creation unavailable (\(status))") }
        return device
    }
    func testPrivateProcessAggregateIsNotAUserMicrophone() throws {
        let device = try makeAggregate(isPrivate: true)
        defer { AudioHardwareDestroyAggregateDevice(device) }
        XCTAssertFalse(DeviceInventory.microphones().contains { $0.deviceID == device },
                       "Private engine aggregates must not turn a single microphone setup into an ambiguous choice")
    }
    func testPublicUserAggregateRemainsSelectable() throws {
        let device = try makeAggregate(isPrivate: false)
        defer { AudioHardwareDestroyAggregateDevice(device) }
        XCTAssertTrue(DeviceInventory.microphones().contains { $0.deviceID == device },
                      "User-created public aggregates must remain available")
    }
}
