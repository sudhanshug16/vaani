import AVFoundation
import CoreAudio
import Foundation
import VaaniCore

/// Opt-in hardware regression: counts PCM bytes without saving or sending audio.
/// Uses only an already-approved built-in input and never requests OS approval.
enum CaptureLifecycleSmoke {
    static func run() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw VaaniError.message("Existing microphone permission is required; no approval was requested.")
        }
        guard let input = DeviceInventory.microphones().first(where: { mic in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var transport: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(mic.deviceID, &address, 0, nil, &size, &transport) == noErr && transport == kAudioDeviceTransportTypeBuiltIn
        }) else { throw VaaniError.message("No built-in microphone available.") }
        let capture = AudioCapture()
        let counters = Counters()
        for cycle in 1...10 {
            defer { capture.stop() }
            try capture.start(deviceID: input.deviceID, onChunk: { data, _ in counters.receive(data.count) },
                              onFailure: { _ in counters.fail() })
            let deadline = Date().addingTimeInterval(0.5)
            while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            guard capture.isUsing(deviceID: input.deviceID) else { throw VaaniError.message("Capture route changed during cycle \(cycle).") }
            capture.stop()
            let bytes = counters.finishCycle()
            guard bytes > 0 else { throw VaaniError.message("No PCM delivered during cycle \(cycle).") }
            print("Capture cycle \(cycle): \(bytes) PCM bytes; stopped."); fflush(stdout)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard counters.failures == 0 else { throw VaaniError.message("Capture reported a reconfiguration failure.") }
        print("10 capture starts/stops passed. No audio saved or sent.")
    }
    private final class Counters {
        private let lock = NSLock()
        private var bytes = 0
        private var failureCount = 0
        func receive(_ count: Int) { lock.lock(); bytes += count; lock.unlock() }
        func fail() { lock.lock(); failureCount += 1; lock.unlock() }
        func finishCycle() -> Int { lock.lock(); defer { lock.unlock() }; let count = bytes; bytes = 0; return count }
        var failures: Int { lock.lock(); defer { lock.unlock() }; return failureCount }
    }
}
