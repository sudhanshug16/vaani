import AppKit
import AVFoundation
import AudioToolbox
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

// A device-bound input queue avoids AVAudioEngine's automatic aggregate graph.
// CurrentDevice is set on this queue only; the system default is never changed.
final class AudioCapture {
    private var queue: AudioQueueRef?
    private var session: InputSession?
    private var deviceID: AudioDeviceID?
    private let callbackQueue = DispatchQueue(label: "dev.vaani.capture")

    func start(deviceID: AudioDeviceID, onChunk: @escaping (Data, Float) -> Void,
               onFailure: @escaping (String) -> Void) throws {
        stop()
        guard let microphone = DeviceInventory.microphones().first(where: { $0.deviceID == deviceID }) else {
            throw VaaniError.message("The selected microphone is unavailable.")
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate: Float64 = 0; var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr,
              rate > 0, rate <= 384_000,
              let source = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true),
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else {
            throw VaaniError.message("Unsupported microphone format.")
        }
        let session = InputSession(uid: microphone.id, source: source, target: target, converter: converter,
                                   onChunk: onChunk, onFailure: onFailure)
        var format = source.streamDescription.pointee
        var created: AudioQueueRef?
        try Self.check(AudioQueueNewInputWithDispatchQueue(&created, &format, 0, callbackQueue) { queue, buffer, _, _, _ in
            session.receive(queue, buffer)
        }, "Create microphone input")
        guard let queue = created else { throw VaaniError.message("Audio input is unavailable.") }
        self.queue = queue; self.session = session; self.deviceID = deviceID
        do {
            let deviceUID = microphone.id as CFString
            var uid = Unmanaged.passUnretained(deviceUID)
            try Self.check(AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, &uid,
                                                UInt32(MemoryLayout<Unmanaged<CFString>>.size)), "Select microphone")
            guard Self.currentUID(queue) == microphone.id else {
                throw VaaniError.message("The selected microphone could not be confirmed.")
            }
            let context = Unmanaged.passUnretained(session).toOpaque()
            for property in [kAudioQueueProperty_IsRunning, kAudioQueueProperty_CurrentDevice] {
                try Self.check(AudioQueueAddPropertyListener(queue, property, Self.propertyChanged, context), "Monitor microphone")
            }
            let bytes = UInt32(max(1024, Int(rate / 10)) * Int(format.mBytesPerFrame))
            for _ in 0..<3 {
                var buffer: AudioQueueBufferRef?
                try Self.check(AudioQueueAllocateBuffer(queue, bytes, &buffer), "Allocate microphone buffer")
                guard let buffer else { throw VaaniError.message("Microphone buffer unavailable.") }
                try Self.check(AudioQueueEnqueueBuffer(queue, buffer, 0, nil), "Queue microphone buffer")
            }
            try Self.check(AudioQueueStart(queue, nil), "Start microphone")
            guard isUsing(deviceID: deviceID), session.gate.open() else {
                throw VaaniError.message("The selected microphone could not be confirmed after starting.")
            }
        } catch { stop(); throw error }
    }
    func isUsing(deviceID: AudioDeviceID) -> Bool {
        guard self.deviceID == deviceID, let queue, let session else { return false }
        var running: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &running, &size) == noErr && running != 0 && Self.currentUID(queue) == session.uid
    }
    func stop() {
        session?.gate.close()
        if let queue {
            // Synchronous disposal guarantees no more callbacks before releasing
            // their session context. A closed gate rejects late PCM immediately.
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
        }
        queue = nil; session = nil; deviceID = nil
    }
    deinit { stop() }
    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw VaaniError.message("\(operation) failed (\(status)).") }
    }
    private static func currentUID(_ queue: AudioQueueRef) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentDevice, &value, &size) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    private static let propertyChanged: AudioQueuePropertyListenerProc = { context, queue, property in
        guard let context else { return }
        let session = Unmanaged<InputSession>.fromOpaque(context).takeUnretainedValue()
        if property == kAudioQueueProperty_CurrentDevice {
            if currentUID(queue) != session.uid { session.fail("The selected microphone changed. Recording stopped; partial text is preserved.") }
        } else {
            var running: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &running, &size) != noErr || running == 0 {
                session.fail("The microphone stopped. Partial text is preserved.")
            }
        }
    }
    private final class InputSession {
        let uid: String
        let source: AVAudioFormat
        let target: AVAudioFormat
        let converter: AVAudioConverter
        var inputGain = InputGainControl()
        let gate = CaptureGate()
        let onChunk: (Data, Float) -> Void
        let onFailure: (String) -> Void
        init(uid: String, source: AVAudioFormat, target: AVAudioFormat, converter: AVAudioConverter,
             onChunk: @escaping (Data, Float) -> Void, onFailure: @escaping (String) -> Void) {
            self.uid = uid; self.source = source; self.target = target; self.converter = converter
            self.onChunk = onChunk; self.onFailure = onFailure
        }
        func fail(_ message: String) { if gate.close() { onFailure(message) } }
        func receive(_ queue: AudioQueueRef, _ buffer: AudioQueueBufferRef) {
            defer {
                let status = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
                if status != noErr { fail("Microphone buffering failed. Partial text is preserved.") }
            }
            guard currentUID(queue) == uid else {
                fail("The selected microphone changed. Recording stopped; partial text is preserved.")
                return
            }
            let frames = AVAudioFrameCount(buffer.pointee.mAudioDataByteSize / source.streamDescription.pointee.mBytesPerFrame)
            guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames) else { return }
            input.frameLength = frames
            guard let destination = input.mutableAudioBufferList.pointee.mBuffers.mData else { return }
            memcpy(destination, buffer.pointee.mAudioData, Int(buffer.pointee.mAudioDataByteSize))
            let capacity = AVAudioFrameCount(ceil(Double(frames) * 16000 / source.sampleRate) + 16)
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false; var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return input
            }
            guard error == nil else { fail("Microphone audio conversion failed. Partial text is preserved."); return }
            guard let samples = output.int16ChannelData?[0], output.frameLength > 0 else { return }
            let length = Int(output.frameLength)
            let rms = inputGain.process(UnsafeMutableBufferPointer(start: samples, count: length))
            gate.deliver { onChunk(Data(bytes: samples, count: length * 2), min(1, rms * 5)) }
        }
    }
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
