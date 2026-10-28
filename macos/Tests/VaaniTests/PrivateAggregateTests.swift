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
    // HAL publishes the device and its input streams asynchronously after
    // creation. Check raw HAL state so the private-device assertion cannot pass
    // merely because the aggregate has not become an input yet.
    private func waitForInput(_ device: AudioDeviceID) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var alive: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive) == noErr, alive != 0 {
                address.mSelector = kAudioDevicePropertyStreamConfiguration
                address.mScope = kAudioDevicePropertyScopeInput
                var bytes: UInt32 = 0
                if AudioObjectGetPropertyDataSize(device, &address, 0, nil, &bytes) == noErr,
                   bytes >= MemoryLayout<AudioBufferList>.size {
                    let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment)
                    defer { memory.deallocate() }
                    if AudioObjectGetPropertyData(device, &address, 0, nil, &bytes, memory) == noErr {
                        let buffers = UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
                        if buffers.contains(where: { $0.mNumberChannels > 0 }) { return true }
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }
    private func waitUntil(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if predicate() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return predicate()
    }
    private func publishedDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }
    func testPrivateProcessAggregateIsNotAUserMicrophone() throws {
        let device = try makeAggregate(isPrivate: true)
        defer { AudioHardwareDestroyAggregateDevice(device) }
        guard waitForInput(device) else { return XCTFail("HAL aggregate did not expose a live input within 5 seconds") }
        XCTAssertTrue(waitUntil { publishedDevices().contains(device) }, "Private test aggregate must be published before checking filtering")
        XCTAssertFalse(DeviceInventory.microphones().contains { $0.deviceID == device },
                       "Private engine aggregates must not turn a single microphone setup into an ambiguous choice")
    }
    func testPublicUserAggregateRemainsSelectable() throws {
        let device = try makeAggregate(isPrivate: false)
        defer { AudioHardwareDestroyAggregateDevice(device) }
        guard waitForInput(device) else { return XCTFail("HAL aggregate did not expose a live input within 5 seconds") }
        XCTAssertTrue(waitUntil { DeviceInventory.microphones().contains { $0.deviceID == device } },
                      "User-created public aggregates must remain available; HAL published device: \(publishedDevices().contains(device))")
    }
}
