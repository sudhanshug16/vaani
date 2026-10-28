import AppKit
import SwiftUI
import VaaniCore

@MainActor final class ShortcutCapture: ObservableObject {
    @Published private(set) var recording = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var candidate: DictationShortcut?
    private var finish: ((DictationShortcut?) -> Void)?
    func begin(completion: @escaping (DictationShortcut?) -> Void) {
        end(nil)
        guard let window = NSApp.keyWindow else { completion(nil); return }
        finish = completion; candidate = nil; recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self, weak window] event in
            let consume = MainActor.assumeIsolated {
                guard let self, self.recording, event.window === window else { return false }
                self.receive(event); return true
            }
            return consume ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.end(nil) } }
    }
    private func receive(_ event: NSEvent) {
        let code = event.keyCode
        if event.type == .keyDown {
            guard !event.isARepeat else { return }
            end(DictationShortcut(keyCode: code, modifiers: UInt64(event.modifierFlags.rawValue), keyLabel: Self.label(event)))
        } else if let mask = DictationShortcut.modifierMask(code) {
            let flags = UInt64(event.modifierFlags.rawValue) & DictationShortcut.modifierFlags
            let required = candidate.map { $0.modifiers | (DictationShortcut.modifierMask($0.keyCode) ?? 0) }
            if let candidate, let required, flags & required != required {
                end(candidate)
            } else if flags & mask != 0 {
                candidate = DictationShortcut(keyCode: code, modifiers: flags & ~mask, keyLabel: Self.label(event))
            }
        }
    }

    func end(_ value: DictationShortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
        recording = false; candidate = nil
        let callback = finish; finish = nil; callback?(value)
    }
    static func label(_ event: NSEvent) -> String {
        let special: [UInt16: String] = [36:"Return",48:"Tab",49:"Space",51:"Delete",53:"Escape",54:"Right Command",55:"Left Command",56:"Left Shift",58:"Left Option",59:"Left Control",60:"Right Shift",61:"Right Option",62:"Right Control",63:"Fn",64:"F17",65:"Keypad .",67:"Keypad *",69:"Keypad +",71:"Keypad Clear",75:"Keypad /",76:"Keypad Enter",78:"Keypad −",81:"Keypad =",82:"Keypad 0",83:"Keypad 1",84:"Keypad 2",85:"Keypad 3",86:"Keypad 4",87:"Keypad 5",88:"Keypad 6",89:"Keypad 7",91:"Keypad 8",92:"Keypad 9",79:"F18",80:"F19",90:"F20",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",106:"F16",107:"F14",109:"F10",111:"F12",113:"F15",114:"Help",115:"Home",116:"Page Up",117:"Forward Delete",118:"F4",119:"End",120:"F2",121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"]
        return special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}

struct ShortcutRecorder: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: PreferenceStore
    @StateObject private var capture = ShortcutCapture()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shortcut")
                Button(capture.recording ? "Press your shortcut…" : store.shortcut.label) {
                    guard !capture.recording else { return }
                    model.shortcutRecordingChanged?(true)
                    capture.begin { value in
                        model.shortcutRecordingChanged?(false)
                        guard let value else { return }
                        let previous = store.shortcut
                        store.shortcut = value
                        if store.save() { model.shortcutChanged?() }
                        else { store.shortcut = previous; model.shortcutStatus = "Shortcut was not saved. \(store.persistenceError ?? "Try again.")" }
                    }
                }.accessibilityLabel("Record shortcut")
                if capture.recording { Button("Cancel") { capture.end(nil) } }
            }
            Text(capture.recording ? "Press a key combination, or press and release a modifier key. Cancel keeps your current shortcut." : "Click the shortcut to change it. Use a key combination, function key, or a left/right modifier by itself.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.shortcutStatus.isEmpty { Text(model.shortcutStatus).font(.caption).foregroundStyle(.secondary) }
            if !store.shortcut.modifierOnly && store.shortcut.modifiers == 0 {
                Text("This key will start dictation instead of typing while Vaani is running.").font(.caption).foregroundStyle(.secondary)
            }
        }.onDisappear { capture.end(nil) }
    }
}
