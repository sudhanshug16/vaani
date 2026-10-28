import AppKit
import AVFoundation
import CoreAudio
import IOKit
import VaaniCore

struct ConnectedSetup: Equatable {
    var fingerprint: String
    var summary: String
}

enum DeviceInventory {
    static func microphones() -> [Microphone] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        // AVAudioEngine can create process-private aggregate devices. They
        // are implementation details, not additional user microphones.
        let visible = devices.filter { !isPrivateAggregate($0) }
        if visible.count != devices.count {
            Diagnostics.record(.privateAggregatesFiltered, count: devices.count - visible.count)
        }
        return visible.compactMap { id in
            var aliveAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var alive: UInt32 = 0; var aliveSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &aliveAddress, 0, nil, &aliveSize, &alive) == noErr, alive != 0 else { return nil }
            var inputAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &inputAddress, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { memory.deallocate() }
            guard AudioObjectGetPropertyData(id, &inputAddress, 0, nil, &bytes, memory) == noErr else { return nil }
            let buffers = UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
            guard buffers.contains(where: { $0.mNumberChannels > 0 }), let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return Microphone(id: uid, name: string(id, kAudioObjectPropertyName) ?? "Microphone", deviceID: id)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private static func isPrivateAggregate(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioAggregateDevicePropertyComposition,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return false }
        var value: Unmanaged<CFDictionary>?
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let composition = value?.takeRetainedValue() as? [String: Any] else { return false }
        return (composition[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue == true
    }
    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    static func setup() -> ConnectedSetup {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16); var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &displays, &count)
        let online = Array(displays.prefix(Int(count)))
        let namesByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (id.uint32Value, screen.localizedName)
        })
        let displayNames = online.map { namesByID[$0] ?? (CGDisplayIsBuiltin($0) != 0 ? "Built-in display" : "External display") }
        let ids = online.map { id in
            "\(CGDisplayVendorNumber(id)):\(CGDisplayModelNumber(id)):\(CGDisplaySerialNumber(id))"
        }
        var iterator: io_iterator_t = 0; var peripherals: [String] = []; var peripheralNames: [String] = []
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                func property(_ name: String) -> String {
                    guard let value = IORegistryEntryCreateCFProperty(entry, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return "" }
                    return String(describing: value)
                }
                let name = property("USB Product Name").trimmingCharacters(in: .whitespacesAndNewlines)
                peripheralNames.append(name.isEmpty ? "USB device" : name)
                peripherals.append("\(property("idVendor")):\(property("idProduct")):\(property("USB Serial Number"))")
            }
        }
        return ConnectedSetup(fingerprint: MicrophonePolicy.fingerprint(displays: ids, peripherals: peripherals),
            summary: SetupLabel.make(displays: displayNames, peripherals: peripheralNames))
    }
}

// The selected input is changed only on this engine's AudioUnit, never system-wide.
final class AudioCapture {
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var gate: CaptureGate?
    func start(deviceID: AudioDeviceID, onChunk: @escaping (Data, Float) -> Void,
               onFailure: @escaping (String) -> Void) throws {
        stop()
        let engine = AVAudioEngine(); let input = engine.inputNode
        guard let unit = input.audioUnit else { throw VaaniError.message("Audio input is unavailable.") }
        var id = deviceID
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw VaaniError.message("Could not select microphone (\(status)).") }
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else { throw VaaniError.message("Unsupported microphone format.") }
        let gate = CaptureGate(); self.gate = gate
        input.installTap(onBus: 0, bufferSize: 2048, format: source) { buffer, _ in
            guard buffer.format.sampleRate == source.sampleRate, buffer.format.channelCount == source.channelCount else {
                if gate.close() { onFailure("The microphone format changed. Recording stopped; partial text is preserved.") }
                return
            }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / source.sampleRate) + 16)
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false; var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            if error != nil {
                if gate.close() { onFailure("Microphone audio conversion failed. Recording stopped; partial text is preserved.") }
                return
            }
            guard let samples = output.int16ChannelData?[0], output.frameLength > 0 else { return }
            let length = Int(output.frameLength)
            var sum: Float = 0
            for index in 0..<length { let value = Float(samples[index]) / 32768; sum += value * value }
            gate.deliver { onChunk(Data(bytes: samples, count: length * 2), min(1, sqrt(sum / Float(length)) * 5)) }
        }
        engine.prepare()
        do {
            try engine.start(); self.engine = engine
            guard isUsing(deviceID: deviceID) else { throw VaaniError.message("The selected microphone could not be confirmed.") }
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                object: engine, queue: nil) { _ in
                    // Core Audio can notify after startup when only the engine's
                    // output/aggregate device settles. Keep recording only if
                    // the input is still running with exactly the chosen route
                    // and format; real input changes still close the PCM gate.
                    var current: AudioDeviceID = 0
                    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
                    let routeStatus = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                        kAudioUnitScope_Global, 0, &current, &size)
                    if engine.isRunning, routeStatus == noErr, current == deviceID,
                       input.outputFormat(forBus: 0).isEqual(source) { return }
                    // Close the PCM gate synchronously, before hopping to the UI.
                    if gate.close() { onFailure("The audio input was reconfigured. Recording stopped; partial text is preserved.") }
                }
            guard gate.open() else { throw VaaniError.message("Audio configuration changed while starting. Try recording again.") }
        } catch {
            gate.close()
            if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
            configurationObserver = nil
            input.removeTap(onBus: 0); engine.stop(); self.engine = nil; self.gate = nil; throw error
        }
    }
    func isUsing(deviceID: AudioDeviceID) -> Bool {
        guard let engine, engine.isRunning, let unit = engine.inputNode.audioUnit else { return false }
        var current: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size) == noErr && current == deviceID
    }
    func stop() {
        gate?.close(); gate = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
    }
    deinit { stop() }
}

private final class CaptureGate {
    private let lock = NSLock()
    private var enabled = false
    private var closed = false
    func open() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return false }
        enabled = true; return true
    }
    @discardableResult func close() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let wasEnabled = enabled; enabled = false; closed = true; return wasEnabled
    }
    func deliver(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        if enabled { body() }
    }
}
