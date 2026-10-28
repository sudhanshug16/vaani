import AppKit
import CoreAudio
import IOKit

/// OS notifications drive changes; the model retains a slow inventory fallback.
@MainActor final class DeviceMonitor {
    private struct Registration {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var systemRegistrations: [Registration] = []
    private var deviceRegistrations: [Registration] = []
    private var observedIDs: Set<AudioDeviceID> = []
    private var screenObserver: NSObjectProtocol?
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    let onChange: () -> Void
    var diagnosticSummary: String {
        "\(systemRegistrations.count) CoreAudio system + \(deviceRegistrations.count) input listeners; display observer \(screenObserver == nil ? "unavailable" : "ready"); USB attach/detach \(addedIterator != 0 && removedIterator != 0 ? "ready" : "unavailable")"
    }

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            if let registration = register(AudioObjectID(kAudioObjectSystemObject), selector: selector) {
                systemRegistrations.append(registration)
            }
        }
        refreshInputs()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange() }
            }
        if let port = IONotificationPortCreate(kIOMainPortDefault) {
            notificationPort = port
            IONotificationPortSetDispatchQueue(port, .main)
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"),
                Self.usbChanged, context, &addedIterator)
            IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"),
                Self.usbChanged, context, &removedIterator)
            Self.drain(addedIterator); Self.drain(removedIterator) // Arm both notifications.
        }
    }
    private func register(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Registration? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.onChange()
                // Never unregister an input listener from inside that listener.
                DispatchQueue.main.async { [weak self] in self?.refreshInputs() }
            }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
        return Registration(object: object, address: address, block: block)
    }
    private func refreshInputs() {
        let ids = Set(DeviceInventory.microphones().map(\.deviceID))
        guard ids != observedIDs else { return }
        Self.remove(deviceRegistrations); deviceRegistrations.removeAll(); observedIDs = ids
        for id in ids {
            for selector in [kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyNominalSampleRate] {
                if let registration = register(id, selector: selector) { deviceRegistrations.append(registration) }
            }
            if let registration = register(id, selector: kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput) {
                deviceRegistrations.append(registration)
            }
        }
    }
    private static let usbChanged: IOServiceMatchingCallback = { context, iterator in
        drain(iterator)
        guard let context else { return }
        let monitor = Unmanaged<DeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { monitor.onChange() }
    }
    private nonisolated static func drain(_ iterator: io_iterator_t) {
        guard iterator != 0 else { return }
        while case let entry = IOIteratorNext(iterator), entry != 0 { IOObjectRelease(entry) }
    }
    private nonisolated static func remove(_ registrations: [Registration]) {
        for var registration in registrations {
            AudioObjectRemovePropertyListenerBlock(registration.object, &registration.address, .main, registration.block)
        }
    }
    deinit {
        Self.remove(systemRegistrations); Self.remove(deviceRegistrations)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
        if addedIterator != 0 { IOObjectRelease(addedIterator) }
        if removedIterator != 0 { IOObjectRelease(removedIterator) }
    }
}
