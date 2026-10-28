import AppKit
import AVFoundation
import SwiftUI
import VaaniCore

@main struct VaaniApp: App {
    init() {
        if CommandLine.arguments.contains("--diagnose") {
            let microphones = DeviceInventory.microphones()
            print("Inputs: \(microphones.count)")
            for mic in microphones { print("• \(mic.name)") }
            print("Setup: \(DeviceInventory.setup().summary)")
            let monitor = DeviceMonitor(onChange: {})
            print("Device monitoring: \(monitor.diagnosticSummary)")
            print("No audio captured; no credentials read; no network requests made.")
            exit(0)
        }
    }
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("Vaani", systemImage: "waveform") {
            Button("Dictate") { delegate.model.toggle() }
            Button("Show floating panel") { delegate.presentPanel() }
            Button("Settings…") { delegate.presentSettings() }
            Divider()
            Button("Quit Vaani") { delegate.model.cancel(); NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = SyncUIFixture.makeModel()
    private var panel: NSPanel?
    private var globalEscape: Any?
    private var localEscape: Any?
    private var settings: NSWindow?
    private let shortcut = Shortcut()
    private var shortcutRetry: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let arguments = CommandLine.arguments
        model.showPanel = { [weak self] in self?.presentPanel() }
        model.showErrorDetails = { [weak self] in self?.presentSettings() }
        if model.isSyncFixture {
            presentSettings()
            Task { @MainActor in await SyncUIFixture.run(model: model) }
            return
        }
        if arguments.contains("--capture-fixture") {
            Task { @MainActor in
                do { try await CaptureSmoke.run(arguments: arguments, model: model); exit(0) }
                catch { print("Microphone fixture failed: \(error.localizedDescription)"); exit(1) }
            }
            return
        }
        if let index = arguments.firstIndex(of: "--sync-smoke") {
            Task { @MainActor in
                do {
                    guard arguments.indices.contains(index + 1) else { throw VaaniError.message("Provide a temporary smoke-test directory.") }
                    let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                    if FileManager.default.fileExists(atPath: directory.path) {
                        guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
                            throw VaaniError.message("Use a new empty directory for isolated sync fixtures.")
                        }
                    }
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let store = PreferenceStore(url: directory.appendingPathComponent("settings.json"))
                    store.shared = SharedPreferences(); store.shared.dictionary = ["Vaani", "sync-smoke"]
                    let sync = SettingsSyncController(store: store, isBusy: { false })
                    let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
                    sync.start(fixtureSecret: key)
                    defer { sync.stop() }
                    for _ in 0..<50 {
                        if sync.running { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard sync.running else { throw VaaniError.message(sync.message) }
                    let pairing = directory.appendingPathComponent("pairing.json")
                    try Data(sync.pairingCode.utf8).write(to: pairing, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pairing.path)
                    print("Sync fixture ready. Pairing credential written privately; isolated settings only."); fflush(stdout)
                    for _ in 0..<1200 {
                        if sync.pending != nil {
                            sync.applyPending()
                            guard store.shared.dictionary == ["Android sync smoke"] else { throw VaaniError.message("Unexpected smoke-test offer.") }
                            print("Android offer accepted into isolated Mac fixture settings."); fflush(stdout)
                        }
                        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("done").path) { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    try? FileManager.default.removeItem(at: pairing)
                    print("Sync fixture stopped."); exit(0)
                } catch { print("Sync fixture failed: \(error.localizedDescription)"); exit(1) }
            }
            return
        }
        if let index = arguments.firstIndex(of: "--sarvam-key-file") {
            do {
                guard arguments.indices.contains(index + 1) else { throw VaaniError.message("Missing private key file path.") }
                let key = try String(contentsOfFile: arguments[index + 1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { throw VaaniError.message("The private key file is empty.") }
                try Vault.save(key, account: "sarvam")
                print("Sarvam credential saved in local Keychain.")
            } catch { print("Credential import failed: \(error.localizedDescription)"); exit(1) }
            if !arguments.contains("--check-sarvam") { exit(0) }
        }
        if arguments.contains("--check-sarvam") {
            Task { @MainActor in
                let connection = SpeechConnection()
                defer { connection.cancel() }
                do {
                    let key = try Vault.read("sarvam")
                    guard !key.isEmpty else { throw VaaniError.message("No saved Sarvam key. Add one in Voice settings.") }
                    try await connection.connect(key: key, preferences: model.store.shared.validated())
                    try await connection.finish()
                    print("Sarvam realtime session opened and finalized. No microphone audio captured.")
                    exit(0)
                } catch { print("Sarvam connection check failed: \(error.localizedDescription)"); exit(1) }
            }
            return
        }
        if let index = arguments.firstIndex(of: "--transcribe-pcm") {
            Task { @MainActor in
                let connection = SpeechConnection()
                defer { connection.cancel() }
                do {
                    guard arguments.indices.contains(index + 1) else { throw VaaniError.message("Provide a mono 16 kHz signed little-endian PCM16 file.") }
                    let file = URL(fileURLWithPath: arguments[index + 1])
                    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= 1_920_000, size % 2 == 0 else { throw VaaniError.message("PCM fixture must contain at most 60 seconds of mono 16 kHz PCM16.") }
                    let pcm = try Data(contentsOf: file)
                    var preferences = model.store.shared
                    if let settingsIndex = arguments.firstIndex(of: "--fixture-settings-file") {
                        guard arguments.indices.contains(settingsIndex + 1) else { throw VaaniError.message("Missing fixture settings file.") }
                        let settingsFile = URL(fileURLWithPath: arguments[settingsIndex + 1])
                        guard (try settingsFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 256_000 else { throw VaaniError.message("Fixture settings file is too large.") }
                        preferences = try JSONDecoder().decode(SharedPreferences.self, from: Data(contentsOf: settingsFile))
                    }
                    preferences = try preferences.validated()
                    let key: String
                    if let keyIndex = arguments.firstIndex(of: "--fixture-key-file") {
                        guard arguments.indices.contains(keyIndex + 1) else { throw VaaniError.message("Missing private fixture key file.") }
                        let file = URL(fileURLWithPath: arguments[keyIndex + 1])
                        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4096 else { throw VaaniError.message("Private fixture key file is too large.") }
                        key = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else { key = try Vault.read("sarvam") }
                    guard !key.isEmpty else { throw VaaniError.message("No saved Sarvam key.") }
                    var transcript = TranscriptAccumulator()
                    var audioStartedAt: TimeInterval?
                    var firstPartialAfterAudio: TimeInterval?
                    connection.onEvent = { event in
                        transcript.receive(event)
                        if event.event == "transcript.partial" {
                            if firstPartialAfterAudio == nil, let audioStartedAt, !transcript.liveText.isEmpty {
                                firstPartialAfterAudio = ProcessInfo.processInfo.systemUptime - audioStartedAt
                            }
                            print("Partial: \(transcript.liveText)")
                        }
                    }
                    let connectStartedAt = ProcessInfo.processInfo.systemUptime
                    try await connection.connect(key: key, preferences: preferences)
                    let connectTime = ProcessInfo.processInfo.systemUptime - connectStartedAt
                    audioStartedAt = ProcessInfo.processInfo.systemUptime
                    let sink = connection.audioSink()
                    for offset in stride(from: 0, to: pcm.count, by: 3200) {
                        sink(pcm.subdata(in: offset..<min(offset + 3200, pcm.count)))
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    let finishingStartedAt = ProcessInfo.processInfo.systemUptime
                    try await connection.finish()
                    print("Final: \(transcript.finalText)")
                    print(String(format: "Timing: connect=%.3fs first_nonempty_partial=%@ finalize=%.3fs", connectTime,
                                 firstPartialAfterAudio.map { String(format: "%.3fs", $0) } ?? "none", ProcessInfo.processInfo.systemUptime - finishingStartedAt))
                    guard !transcript.finalText.isEmpty else { throw VaaniError.message("No final transcript received.") }
                    exit(0)
                } catch { print("PCM transcription failed: \(error.localizedDescription)"); exit(1) }
            }
            return
        }
        _ = Diagnostics.log
        shortcut.action = { [weak self] in
            guard let self else { return }
            self.model.shortcutStatus = "Detected · \(self.model.store.shortcut.label)"
            self.model.toggleFromShortcut()
        }
        model.shortcutRecordingChanged = { [weak self] in self?.shortcut.suspended = $0 }
        model.shortcutChanged = { [weak self] in self?.registerShortcut() }
        registerShortcut()
        shortcutRetry = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.shortcut.ready else { return }
                self.registerShortcut()
            }
        }
        presentSettings()
    }
    private func registerShortcut() {
        if shortcut.register(model.store.shortcut) {
            model.shortcutStatus = "Ready · \(model.store.shortcut.label)"
        } else {
            model.shortcutStatus = "Shortcut inactive. Enable Accessibility for this copy of Vaani; it will retry automatically."
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        shortcutRetry?.invalidate(); shortcut.unregister()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentSettings()
        return false
    }
    func presentSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 670),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = model.isSyncFixture ? "Vaani · isolated sync fixture" : "Vaani"; window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 760, height: 580)
            window.contentView = NSHostingView(rootView: SettingsView(model: model, store: model.store, sync: model.settingsSync))
            window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if settings?.isMiniaturized == true { settings?.deminiaturize(nil) }
        settings?.makeKeyAndOrderFront(nil)
    }
    func presentPanel() {
        if panel == nil {
            let window = DictationPanel(contentRect: NSRect(x: 0, y: 0, width: 54, height: 36),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .floating; window.isFloatingPanel = true; window.hidesOnDeactivate = false
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let hosting = NSHostingView(rootView: FloatingView(model: model, hide: { [weak self] in self?.dismissPanel() },
                resize: { [weak self] size in
                    // Apply after SwiftUI's current layout pass; AppKit may
                    // adjust the hosting window's top anchor during that pass.
                    Task { @MainActor in self?.resizePanel(size) }
                }))
            // Explicit sizing preserves the pill's bottom edge. Implicit
            // NSHostingView resizing anchors the top and can push it offscreen.
            hosting.sizingOptions = []
            window.contentView = hosting
            if let frame = NSScreen.main?.visibleFrame { window.setFrameOrigin(NSPoint(x: frame.midX - 27, y: frame.minY + 70)) }
            if !model.isSyncFixture {
                _ = window.setFrameUsingName("Vaani.DictationPanel")
                window.setFrameAutosaveName("Vaani.DictationPanel")
            }
            panel = window
        }
        panel?.orderFrontRegardless()
        if globalEscape == nil {
            globalEscape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return }
                Task { @MainActor in if self?.panel?.isVisible == true { self?.dismissPanel() } }
            }
        }
        if localEscape == nil {
            localEscape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard event.keyCode == 53, self?.panel?.isVisible == true else { return false }
                    self?.dismissPanel(); return true
                }
                return consumed ? nil : event
            }
        }
    }
    private func dismissPanel() {
        if model.active || model.isPasting { model.cancelFromDismiss() }
        panel?.orderOut(nil)
        if let globalEscape { NSEvent.removeMonitor(globalEscape) }
        if let localEscape { NSEvent.removeMonitor(localEscape) }
        globalEscape = nil; localEscape = nil
    }
    private func resizePanel(_ size: CGSize) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        let old = panel.frame
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(old) } ?? NSScreen.main
        var origin = NSPoint(x: old.minX, y: old.minY)
        if let frame = screen?.visibleFrame {
            origin.x = min(max(origin.x, frame.minX), max(frame.minX, frame.maxX - size.width))
            origin.y = min(max(origin.y, frame.minY), max(frame.minY, frame.maxY - size.height))
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

private let ink = Color(red: 0.075, green: 0.08, blue: 0.095)
private let accent = Color(red: 1, green: 0.61, blue: 0.34)

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: PreferenceStore
    @ObservedObject var sync: SettingsSyncController
    @State private var page = "Voice"
    @State private var sarvamKey = ""
    @State private var processingKey = ""
    @State private var keyNotice = ""
    @State private var unlockingKeys = false
    @State private var microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var requestingMicrophone = false
    @State private var dictionaryDraft = ""
    private let pages = [("Voice", "waveform"), ("Microphones", "mic"), ("Polish", "sparkles"), ("Dictionary", "text.book.closed"), ("Devices", "point.3.connected.trianglepath.dotted")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { Image(systemName: "waveform").foregroundStyle(accent); Text("vaani").font(.system(size: 25, weight: .semibold, design: .rounded)) }.padding(.bottom, 3)
                Text("A little space to speak.").font(.caption).foregroundStyle(.secondary).padding(.bottom, 28)
                ForEach(pages, id: \.0) { item in
                    Button { page = item.0 } label: {
                        Label(item.0, systemImage: item.1).font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(11)
                            .background(page == item.0 ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(page == item.0 ? .white : .secondary)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("PERSONAL · OPEN SOURCE").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                Text("\(store.shortcut.label) to dictate").font(.caption).foregroundStyle(accent)
            }.padding(24).frame(width: 218).background(.black.opacity(0.18))
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(page).font(.system(size: 30, weight: .semibold, design: .rounded))
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle().fill(model.active ? accent : .green.opacity(0.8)).frame(width: 7, height: 7).padding(.top, 12)
                    }
                    if let notice = model.statusNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if page == "Voice" {
                        card("Try dictation") {
                            HStack {
                                Button(model.phase == .listening ? "Finish" : "Dictate") { model.toggle() }
                                    .disabled(model.active && model.phase != .listening)
                                if model.active { Button("Cancel", action: model.cancel) }
                                Text(model.phaseDescription).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(model.selectedName).font(.caption).foregroundStyle(.secondary)
                            if !model.rawText.isEmpty {
                                Text(model.output.isEmpty ? model.rawText : model.output).textSelection(.enabled)
                            }
                            Text("Try your microphone here, or start from a text editor with \(store.shortcut.label) to capture a paste destination.").font(.caption).foregroundStyle(.secondary)
                        }
                        if !model.isSyncFixture {
                            card("Troubleshooting") {
                                Text("Diagnostic logs are saved automatically. Audio, dictated text and API keys are never logged.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Show logs in Finder") {
                                    Diagnostics.log?.flush()
                                    NSWorkspace.shared.activateFileViewerSelecting([Diagnostics.directory.appendingPathComponent("events.jsonl")])
                                }
                            }
                        }
                    }
                    Group {
                        switch page {
                        case "Microphones": microphonePage
                        case "Polish": polishPage
                        case "Dictionary": dictionaryPage
                        case "Devices": devicesPage
                        default: voicePage
                        }
                    }.disabled(model.active)
                }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
            }.safeAreaInset(edge: .top, spacing: 0) {
                if let error = model.error ?? store.persistenceError {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(accent)
                        Text(error).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Voice") { page = "Voice" }
                    }.padding(18).background(ink)
                } else if model.phase == .connecting {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(model.phaseDescription).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Cancel", action: model.cancel)
                    }.padding(18).background(ink)
                }
            }
        }.background(ink).preferredColorScheme(.dark).tint(accent)
            .onAppear {
                do { if !model.isSyncFixture { sarvamKey = try Vault.read("sarvam"); processingKey = try Vault.read("processing") } }
                catch { keyNotice = error.localizedDescription }
                dictionaryDraft = store.shared.dictionary.joined(separator: "\n")
            }
            .onChange(of: store.shared.dictionary) { _, words in
                let edited = dictionaryDraft.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if edited != words { dictionaryDraft = words.joined(separator: "\n") }
            }
            .onChange(of: store.shared) { _, _ in store.save() }
    }
    private var subtitle: String {
        switch page {
        case "Microphones": "The right input, wherever you sit."
        case "Polish": "Your words. Your prompt. Your provider."
        case "Dictionary": "Names and words that sound like you."
        case "Devices": "Keep your preferences close."
        default: "Speak naturally. Keep your language."
        }
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            content()
        }.padding(19).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.065)))
    }
    private var voicePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("Sarvam speech") {
                SecureField("API subscription key", text: $sarvamKey).textFieldStyle(.roundedBorder)
                HStack { Button("Save key") { saveKey(sarvamKey, account: "sarvam") }; Text(keyNotice).font(.caption).foregroundStyle(.secondary) }
                Button(unlockingKeys ? "Waiting for Keychain approval…" : "Unlock saved keys") {
                    unlockingKeys = true
                    Task { @MainActor in
                        defer { unlockingKeys = false }
                        do {
                            let keys = try await Vault.unlockSavedKeys()
                            sarvamKey = keys.sarvam; processingKey = keys.processing
                            keyNotice = "Saved keys unlocked for this build."; model.error = nil
                        } catch { keyNotice = error.localizedDescription }
                    }
                }.disabled(unlockingKeys)
                Picker("Language", selection: $store.shared.language) { ForEach(SharedPreferences.languages, id: \.self) { Text(SharedPreferences.languageName($0)).tag($0) } }
                Picker("Output", selection: $store.shared.mode) {
                    Text("Romanized / Latin script").tag("translit"); Text("Original script").tag("transcribe")
                    Text("Native + English").tag("codemix"); Text("English translation").tag("translate"); Text("Verbatim").tag("verbatim")
                }
                Picker("Speech model", selection: $store.shared.sarvamModel) { Text("Saaras v3 Realtime").tag("saaras:v3-realtime"); Text("Saaras v4").tag("saaras:v4") }
                Text("For Hinglish, use Auto-detect and Romanized / Latin script to keep Hindi in Latin letters and preserve English words.").font(.caption).foregroundStyle(.secondary)
                Text("A nonempty dictionary uses Saaras v4, which supports recognition hints, regardless of this selection.").font(.caption).foregroundStyle(.secondary)
                Text("Audio streams to Sarvam only while recording. Vaani does not save audio or transcript history.").font(.caption).foregroundStyle(.secondary)
            }
            card("Microphone access") {
                Text(microphonePermission == .authorized ? "Microphone access is allowed." : "Allow microphone access separately from your API key. Audio is captured only when you start dictation.")
                    .font(.caption).foregroundStyle(.secondary)
                if microphonePermission == .notDetermined {
                    Button(requestingMicrophone ? "Waiting for microphone permission…" : "Allow microphone") {
                        requestingMicrophone = true
                        Task { @MainActor in
                            _ = await AVCaptureDevice.requestAccess(for: .audio)
                            microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio)
                            requestingMicrophone = false
                        }
                    }.disabled(requestingMicrophone)
                } else if microphonePermission != .authorized {
                    Text("Microphone access is unavailable. Enable Vaani in System Settings → Privacy & Security → Microphone.").font(.caption)
                    Button("Open Microphone settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
                Button("Refresh permission status") { microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio) }
            }
            card("Dictation") {
                ShortcutRecorder(model: model, store: store)
                Button("Retry shortcut") { model.shortcutChanged?() }
                Text("Tap once to start; tap again to finish and paste. Modifier+letter typing does not trigger a standalone modifier shortcut.").font(.caption).foregroundStyle(.secondary)
                Text("Requires Accessibility permission. Finished text stays on the clipboard. Start from your destination app with \(store.shortcut.label).").font(.caption).foregroundStyle(.secondary)
                Button("Open Accessibility settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                Button("Show dictation panel") { model.showPanel?() }
            }
            if !model.rawText.isEmpty { card("Last dictation · only in memory") {
                Text(model.output.isEmpty ? model.rawText : model.output).textSelection(.enabled)
                HStack { Button("Copy", action: model.copy); Button(model.pasteLabel, action: model.paste) }
                DisclosureGroup("Raw transcription") { Text(model.rawText).font(.caption).textSelection(.enabled) }
            } }
        }
    }
    private var microphonePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("Current setup") {
                Text(model.setup.summary).font(.headline)
                if model.devicesSettling { Text("Waiting for connected devices to settle…").foregroundStyle(accent) }
                Picker("Profile", selection: Binding(get: { store.manualProfileID ?? "" }, set: model.useProfile)) {
                    Text("Automatic · connected hardware").tag("")
                    ForEach(store.manualProfiles.keys.sorted(), id: \.self) { id in
                        Text(store.manualProfiles[id]?.name ?? "Profile").tag(id)
                    }
                }
                Text(store.manualProfileID == nil ? "Automatic matching follows your monitors and USB devices." : "This manual profile stays active across hardware changes and app restarts. Choose Automatic to resume detection.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Name this setup · Home, Office…", text: $model.setupName).textFieldStyle(.roundedBorder)
                if model.needsChoice { Text("Which microphone should Vaani use here?").foregroundStyle(accent) }
                ForEach(model.microphones) { mic in
                    Button { model.selectedUID = mic.id } label: {
                        HStack { Image(systemName: model.selectedUID == mic.id ? "checkmark.circle.fill" : "circle"); Text(mic.name); Spacer() }
                    }.buttonStyle(.plain).padding(.vertical, 5).foregroundStyle(model.selectedUID == mic.id ? accent : .primary)
                }
                HStack {
                    Button(store.manualProfileID == nil ? "Remember for this setup" : "Update profile", action: model.rememberMicrophone)
                    Button("Save as separate profile", action: model.createManualProfile)
                }.disabled(model.selectedUID.isEmpty || model.devicesSettling)
                Text("Matches connected displays and USB devices. A missing preferred mic pauses dictation until you choose another. Bluetooth choices are remembered by device ID within the same setup.").font(.caption).foregroundStyle(.secondary)
            }
            if !store.manualProfiles.isEmpty {
                card("Manual profiles") {
                    ForEach(store.manualProfiles.keys.sorted(), id: \.self) { id in
                        HStack {
                            Text(store.manualProfiles[id]?.name ?? "Profile")
                            if store.manualProfileID == id { Text("Active").font(.caption).foregroundStyle(accent) }
                            Spacer()
                            Button("Use") { model.useProfile(id) }
                            Button("Forget") { model.forgetManualProfile(id) }
                        }
                    }
                }
            }
            card("Saved setups") {
                if store.setups.isEmpty { Text("Your choices will appear here.").foregroundStyle(.secondary) }
                ForEach(store.setups.keys.sorted(), id: \.self) { key in
                    HStack { Text(store.setups[key]?.name ?? "Setup"); Spacer(); Button("Forget") { store.setups[key] = nil; store.save(); model.refreshDevicesAfterForget() } }
                }
            }
        }
    }
    private var polishPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("Responses API") {
                Toggle("Polish after transcription", isOn: $store.shared.processingEnabled)
                TextField("API base URL", text: $store.shared.endpoint).textFieldStyle(.roundedBorder)
                TextField("Model name", text: $store.shared.model).textFieldStyle(.roundedBorder)
                Picker("Service tier", selection: $store.shared.serviceTier) {
                    ForEach(SharedPreferences.serviceTiers, id: \.self) { tier in
                        Text(SharedPreferences.serviceTierName(tier)).tag(tier)
                    }
                }
                Text("Provider default leaves the tier unspecified. Fast / Priority may cost more; tier availability depends on your provider and model.").font(.caption).foregroundStyle(.secondary)
                Picker("Reasoning effort", selection: $store.shared.reasoningEffort) {
                    ForEach(Array(SharedPreferences.reasoningEfforts.enumerated()), id: \.offset) { index, effort in
                        Text(SharedPreferences.reasoningEffortNames[index]).tag(effort)
                    }
                }
                Text("None turns reasoning off. Supported efforts depend on the model; Provider default leaves the setting unspecified.").font(.caption).foregroundStyle(.secondary)
                SecureField("API key (optional for local servers)", text: $processingKey).textFieldStyle(.roundedBorder)
                HStack { Button("Save key") { saveKey(processingKey, account: "processing") }; Text(keyNotice).font(.caption).foregroundStyle(.secondary) }
                Text("Accepts /v1 base URLs and full /responses URLs. HTTPS required except on localhost. Only text is sent to this provider.").font(.caption).foregroundStyle(.secondary)
            }
            card("Your prompt") {
                TextEditor(text: $store.shared.prompt).font(.system(size: 12, design: .monospaced)).frame(minHeight: 170).scrollContentBackground(.hidden)
                Button("Restore default prompt") { store.shared.prompt = SharedPreferences.defaultPrompt }
            }
        }
    }
    private var dictionaryPage: some View {
        card("Personal dictionary") {
            Text("One spelling per line. A nonempty dictionary uses Saaras v4 for recognition hints and is included in the polishing prompt. Spellings are suggestions, not guaranteed replacements.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: Binding(get: { dictionaryDraft }, set: {
                dictionaryDraft = $0
                store.shared.dictionary = $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            })).font(.system(size: 14)).frame(minHeight: 270).scrollContentBackground(.hidden)
            Text("\(store.shared.dictionary.count) / 500 words").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var devicesPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("Private settings transfer") {
                Text("Export language, dictionary, prompt and provider settings. Import the same file on Android or another Mac.")
                HStack { Button("Export settings…", action: store.exportSettings); Button("Import settings…", action: store.importSettings) }
                Text("API keys, microphone identities, transcripts and audio are excluded. Provider URL and prompt are included. Import asks you to review the destination.").font(.caption).foregroundStyle(.secondary)
            }
            card("Sync now · Tailscale") {
                Text("Pair Android once, then choose which device's settings to use. Both devices must be on your Tailscale network; this Mac must be awake and sharing.").font(.callout)
                TextField("This Mac's Tailscale IPv4 · 100.x.x.x", text: $sync.host).textFieldStyle(.roundedBorder).disabled(sync.running)
                HStack {
                    Button(sync.running ? "Stop sharing" : "Start sharing") { if sync.running { sync.stop() } else { sync.start() } }
                    if sync.running { Button("Copy pairing code", action: sync.copyPairingCode) }
                    Button("Revoke pairing", action: sync.revoke)
                }
                Text(sync.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Transfers language, dictionary, prompt and provider settings with authenticated encryption. Keys, audio, transcripts and microphone setups stay local. Sharing starts only when you click Start sharing; it stops when Vaani quits.").font(.caption).foregroundStyle(.secondary)
            }
            if let incoming = sync.pending {
                card("Review settings from Android") {
                    Text("API destination: \(incoming.endpoint)")
                    Text("Processing: \(incoming.processingEnabled ? "enabled" : "disabled") · Model: \(incoming.model) · Language: \(incoming.language) · Output: \(incoming.mode)")
                    Text("Dictionary: \(incoming.dictionary.joined(separator: ", "))").font(.caption).textSelection(.enabled)
                    DisclosureGroup("Processing prompt") { Text(incoming.prompt).font(.caption).textSelection(.enabled) }
                    HStack { Button("Apply settings", action: sync.applyPending); Button("Discard", action: sync.discardPending) }
                }
            }
        }
    }
    private func saveKey(_ value: String, account: String) {
        do {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw VaaniError.message("Enter a key before saving. An empty field does not remove the saved credential.") }
            try Vault.save(key, account: account); keyNotice = "Saved in Keychain."
        }
        catch { model.error = error.localizedDescription }
    }
}
