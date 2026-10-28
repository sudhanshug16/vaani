import AVFoundation
import CoreAudio
import Foundation
import VaaniCore

/// Opt-in hardware regression: counts PCM bytes without saving or sending audio.
/// Uses only an already-approved built-in input and never requests OS approval.
enum CaptureLifecycleSmoke {
    /// Exercises the packaged model/resampler without microphone, keys or network.
    static func runProcessing() throws {
        var seed: UInt32 = 12345
        let noise: [Float] = (0..<48000).map { _ in
            seed = 1664525 &* seed &+ 1013904223
            return (Float(seed >> 8) / Float(1 << 24) * 2 - 1) * 0.025
        }
        let start = Date()
        for cycle in 1...10 {
            let processor = try SpeechAudioProcessor()
            var bytes = 0, invalid = false
            let receive: (Data, Float) -> Void = { data, level in
                bytes += data.count
                invalid = invalid || !level.isFinite || !(0...1).contains(level) || data.count % 2 != 0
                data.withUnsafeBytes { buffer in
                    if buffer.bindMemory(to: Int16.self).contains(where: { abs(Int($0)) > 31130 }) { invalid = true }
                }
            }
            try noise.withUnsafeBufferPointer { buffer in
                for start in stride(from: 0, to: buffer.count, by: 480) {
                    try processor.process(UnsafeBufferPointer(rebasing: buffer[start..<start + 480]), emit: receive)
                }
            }
            try processor.finish(emit: receive)
            guard bytes == 32640, !invalid else { throw VaaniError.message("Invalid speech PCM in processing cycle \(cycle).") }
            print("Processing cycle \(cycle): \(bytes) PCM bytes; model and finalization passed.")
        }
        print("10 seconds of synthetic audio processed in \(Date().timeIntervalSince(start)) seconds. No microphone, saved audio, keys or network.")
    }
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
            capture.stop(flush: true)
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
