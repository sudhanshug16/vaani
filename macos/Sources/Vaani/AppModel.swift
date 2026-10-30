import AppKit
import AVFoundation
import Carbon
import SwiftUI
import OSLog
import VaaniCore

@MainActor final class AppModel: ObservableObject {
    enum Phase: String { case idle = "Ready", connecting = "Connecting", listening = "Listening", finishing = "Finishing", processing = "Polishing" }
    let store: PreferenceStore
    let isSyncFixture: Bool
    private let syncFixtureSecret: String?
    lazy var settingsSync = SettingsSyncController(store: store, isBusy: { [weak self] in self?.active ?? false }, ephemeralSecret: syncFixtureSecret)
    enum StartupStep: String {
        case destination, preferences, credentials, microphonePermission, speechConnection, microphoneStart, listening
        var label: String {
            switch self {
            case .destination: "Preparing destination…"
            case .preferences: "Checking settings…"
            case .credentials: "Reading saved keys · approve Keychain if asked…"
            case .microphonePermission: "Waiting for microphone permission…"
            case .speechConnection: "Connecting to Sarvam…"
            case .microphoneStart: "Starting microphone…"
            case .listening: "Listening"
            }
        }
    }
    @Published private(set) var startupStep = StartupStep.destination
    var phaseDescription: String { phase == .connecting ? startupStep.label : (phase == .listening && !speechReady ? "Listening · connecting to Sarvam…" : (phase == .idle && error != nil ? "Needs attention" : phase.rawValue)) }
    private let startupLog = Logger(subsystem: "dev.vaani.mac", category: "Startup")
    private func startup(_ step: StartupStep) {
        startupStep = step
        Diagnostics.record(.startup, DiagnosticLog.Detail(rawValue: step.rawValue), session: generation)
        startupLog.notice("stage=\(step.rawValue, privacy: .public)")
    }
    @Published var phase: Phase = .idle {
        didSet {
            guard oldValue != phase else { return }
            let detail: DiagnosticLog.Detail = switch phase {
            case .idle: .idle
            case .connecting: .connecting
            case .listening: .listening
            case .finishing: .finishing
            case .processing: .processing
            }
            Diagnostics.record(.phase, detail, session: generation)
        }
    }
    private enum StartBlock {
        case devicesChanging, microphoneChoice
        var message: String {
            switch self {
            case .devicesChanging: "Audio devices are changing. Try dictation again in a moment."
            case .microphoneChoice: "Choose a microphone in Settings before recording."
            }
        }
    }
    private var startBlock: (kind: StartBlock, message: String)?
    private var loggedAudioBuffer = false
    private var loggedAudioSignal = false
    @Published var microphones: [Microphone] = []
    @Published var selectedUID = "" {
        didSet {
            if oldValue != selectedUID {
                Diagnostics.record(.microphoneSelection, selectedUID.isEmpty ? .unselected : .selected, session: generation)
            }
        }
    }
    @Published var setup = ConnectedSetup(fingerprint: "", summary: "Detecting setup")
    @Published var needsChoice = false
    @Published var setupName = ""
    @Published var rawText = ""
    @Published var output = ""
    @Published var level: Float = 0
    @Published var error: String?
    @Published var notice: String?
    @Published private(set) var microphoneNotice: String?
    @Published var devicesSettling = false
    private let inventory: () -> (microphones: [Microphone], setup: ConnectedSetup)
    private let process: (String, SharedPreferences, String) async throws -> String
    private var capture = AudioCapture()
    private var connection: SpeechConnection?
    private var connectionStartup: Task<Void, Error>?
    @Published private(set) var speechReady = false
    private var transcript = TranscriptAccumulator()
    private var timer: Timer?
    private var deviceMonitor: DeviceMonitor?
    private var deviceDebounce: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var pasteOperation: Task<Void, Never>?
    @Published private(set) var isPasting = false
    var shortcutChanged: (() -> Void)?
    var shortcutRecordingChanged: ((Bool) -> Void)?
    @Published var shortcutStatus = ""
    @Published private(set) var panelCompletion = 0
    private var generation = UUID()
    private var target: NSRunningApplication?
    private var destination: PasteDestination?
    private var windowDestination: PasteDestination.WindowDestination?
    private var destinationIssue: String?
    private var snapshot = SharedPreferences()
    private var processingKey = ""
    var showPanel: (() -> Void)?
    var showErrorDetails: (() -> Void)?
    var active: Bool { phase != .idle }
    var selectedName: String { microphones.first { $0.id == selectedUID }?.name ?? "Choose microphone" }
    var statusNotice: String? { microphoneNotice ?? (notice == error ? nil : notice) }
    var pasteLabel: String { destination == nil && windowDestination != nil ? "Paste to app" : "Paste" }

    init(store: PreferenceStore? = nil, syncFixtureSecret: String? = nil,
         inventory: @escaping () -> (microphones: [Microphone], setup: ConnectedSetup) = { (DeviceInventory.microphones(), DeviceInventory.setup()) },
         observeDevices: Bool = true,
         process: @escaping (String, SharedPreferences, String) async throws -> String = { text, preferences, key in
             try await PostProcessor.process(text, preferences: preferences, key: key)
         }) {
        self.store = store ?? PreferenceStore()
        self.inventory = inventory
        self.process = process
        self.syncFixtureSecret = syncFixtureSecret; self.isSyncFixture = syncFixtureSecret != nil
        refreshDevices()
        if observeDevices {
            deviceMonitor = DeviceMonitor { [weak self] in self?.devicesChanged() }
            timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshDevices() } }
        }
    }
    private func devicesChanged() {
        if phase == .listening { verifyActiveInput(inventory().microphones) }
        Diagnostics.record(.deviceChange, session: generation)
        devicesSettling = true
        deviceDebounce?.cancel()
        deviceDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            guard let self else { return }
            self.devicesSettling = false
            Diagnostics.record(.deviceSettled, session: self.generation)
            self.refreshDevices()
        }
    }
    private func verifyActiveInput(_ available: [Microphone]) {
        guard phase == .listening else { return }
        guard let input = available.first(where: { $0.id == selectedUID }), capture.isUsing(deviceID: input.deviceID) else {
            fail("The recording microphone disconnected or its route changed. Recording stopped; partial text is preserved.", reason: .inputChanged)
            return
        }
    }
    func refreshDevices(force: Bool = false) {
        defer { clearRecoveredStartBlock() }
        let (available, current) = inventory()
        if active {
            verifyActiveInput(available)
            if active { return } // A new display or hub never changes an ongoing recording's input.
            // Input verification may have stopped capture. Refresh the idle
            // picker now instead of displaying the lost input until the next poll.
        }
        guard force || available != microphones || current != setup else { return }
        microphones = available; setup = current
        let preference = store.local.preference(for: current.fingerprint)
        setupName = preference?.name ?? current.summary
        if store.manualProfileID == nil, setupName == "My setup" { setupName = current.summary }
        microphoneNotice = nil
        let decision = MicrophonePolicy.decide(available: available, preference: preference)
        let detail: DiagnosticLog.Detail
        switch decision {
        case .remembered(let mic): selectedUID = mic.id; needsChoice = false; detail = .remembered
        case .onlyAvailable(let mic): selectedUID = mic.id; needsChoice = false; detail = .onlyAvailable
        case .ask: selectedUID = ""; needsChoice = true; microphoneNotice = "Choose a microphone for this setup."; detail = .ask
        case .missingRemembered: selectedUID = ""; needsChoice = true; microphoneNotice = "Your preferred microphone is missing. Choose an input for this setup."; detail = .missingRemembered
        case .unavailable: selectedUID = ""; needsChoice = false; microphoneNotice = "No microphone is available."; detail = .unavailable
        }
        Diagnostics.record(.microphoneInventory, detail, session: generation, count: available.count)
    }
    private func clearRecoveredStartBlock() {
        guard let block = startBlock else { return }
        guard error == block.message else { startBlock = nil; return }
        let recovered: Bool = switch block.kind {
        case .devicesChanging: !devicesSettling && !selectedUID.isEmpty
        case .microphoneChoice: !selectedUID.isEmpty
        }
        if recovered { error = nil; startBlock = nil }
    }
    private func blockStart(_ kind: StartBlock, message: String? = nil) {
        let message = message ?? kind.message
        startBlock = (kind, message); error = message
    }
    private func validateMicrophoneChoice() -> Bool {
        guard !active, !devicesSettling else { return false }
        let current = inventory()
        guard current.setup == setup, current.microphones.contains(where: { $0.id == selectedUID }) else {
            refreshDevices(force: true)
            error = "Audio setup changed. Choose a microphone for the current setup before saving."
            return false
        }
        return true
    }
    func rememberMicrophone() {
        guard validateMicrophoneChoice() else { return }
        let preference = SetupPreference(name: setupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? setup.summary : setupName, microphoneUID: selectedUID)
        if let id = store.manualProfileID { store.manualProfiles[id] = preference }
        else { store.setups[setup.fingerprint] = preference }
        needsChoice = false; microphoneNotice = nil
        if store.save() { error = nil; notice = "Microphone preference saved." }
        else { error = "Input selected for this session, but the preference could not be saved: \(store.persistenceError ?? "unknown error")" }
    }
    func useProfile(_ id: String) {
        guard !active else { return }
        store.manualProfileID = id.isEmpty ? nil : id
        let saved = store.save(); refreshDevices(force: true)
        if saved { notice = id.isEmpty ? "Automatic setup matching enabled." : "Manual profile stays active until you choose Automatic." }
        else { error = "Profile selected for this session, but could not be saved: \(store.persistenceError ?? "unknown error")" }
    }
    func createManualProfile() {
        guard validateMicrophoneChoice() else { return }
        let name = setupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Give this profile a name, such as Home or Office."; return }
        let id = UUID().uuidString
        store.manualProfiles[id] = SetupPreference(name: name, microphoneUID: selectedUID)
        useProfile(id)
    }
    func forgetManualProfile(_ id: String) {
        guard !active else { return }
        store.manualProfiles[id] = nil
        if store.manualProfileID == id { useProfile("") } else { store.save() }
    }
    func chooseAndRememberMicrophone(_ uid: String) {
        guard !active else { return }
        selectedUID = uid; rememberMicrophone()
    }
    func refreshDevicesAfterForget() { refreshDevices(force: true) }
    func toggle() { toggle(source: .controls) }
    func toggleFromShortcut() { toggle(source: .shortcut) }
    func toggleFromPanel() { toggle(source: .panel) }
    private func toggle(source: DiagnosticLog.Detail) {
        Diagnostics.record(.command, source, session: generation)
        guard !isSyncFixture else { Diagnostics.record(.commandRejected, .fixture); error = "Speech is disabled in the isolated sync fixture."; return }
        if phase == .listening { stop(); return }
        guard phase == .idle else { Diagnostics.record(.commandRejected, .busy, session: generation); return }
        pasteOperation?.cancel(); isPasting = false
        target = nil; destination = nil; windowDestination = nil; destinationIssue = nil
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            target = app
        }
        showPanel?()
        // Core Audio emits notifications when capture starts/stops, even when
        // the available inputs and desk setup have not changed. Only a real
        // inventory change needs the debounce window; never block a confirmed
        // unchanged input just because its device notified us.
        if devicesSettling {
            let current = inventory()
            guard current.setup == setup, current.microphones == microphones else {
                Diagnostics.record(.commandRejected, .devicesSettling, session: generation)
                blockStart(.devicesChanging)
                return
            }
        }
        // Recover an empty selection even if the cached inventory is unchanged.
        // Reapplying policy still refuses a missing remembered mic or ambiguous setup.
        refreshDevices(force: selectedUID.isEmpty)
        guard !selectedUID.isEmpty else {
            Diagnostics.record(.commandRejected, .microphoneChoice, session: generation)
            blockStart(.microphoneChoice, message: microphoneNotice)
            return
        }
        let token = UUID(); generation = token
        startBlock = nil
        startup(.destination)
        phase = .connecting; rawText = ""; output = ""; error = nil; notice = nil
        transcript = TranscriptAccumulator(); snapshot = store.shared
        loggedAudioBuffer = false; loggedAudioSignal = false; speechReady = false
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                if let target = self.target {
                    let captured = try await PasteDestination.capture(pid: target.processIdentifier)
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    self.destination = captured.destination
                    self.windowDestination = captured.window
                    self.destinationIssue = captured.issue
                    self.notice = captured.issue
                }
                self.startup(.preferences)
                _ = try self.snapshot.validated()
                self.startup(.credentials)
                let key = try await Vault.readForDictation("sarvam")
                try Task.checkCancellation()
                guard self.generation == token else { return }
                guard !key.isEmpty else { throw VaaniError.message("Add your Sarvam API key in Settings.") }
                self.processingKey = self.snapshot.processingEnabled ? try await Vault.readForDictation("processing") : ""
                try Task.checkCancellation()
                self.startup(.microphonePermission)
                let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                try Task.checkCancellation()
                guard allowed else { throw VaaniError.message("Microphone access is required. Enable Vaani in System Settings → Privacy & Security → Microphone.") }
                guard self.generation == token else { return }
                let connection = SpeechConnection(); self.connection = connection
                connection.onEvent = { [weak self] event in
                    guard let self, self.generation == token else { return }
                    self.receiveSpeechEvent(event)
                }
                connection.onFailure = { [weak self] error in
                    guard let self, self.generation == token else { return }
                    self.fail("Streaming failed: \(error.localizedDescription)", reason: .streamFailure)
                }
                connection.onEnded = { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.speechSessionEnded()
                }
                self.startup(.speechConnection)
                let preferences = self.snapshot
                let connecting = Task { try await connection.connect(key: key, preferences: preferences) }
                self.connectionStartup = connecting
                guard let device = DeviceInventory.microphones().first(where: { $0.id == self.selectedUID }) else {
                    throw VaaniError.message("The selected microphone disconnected while connecting. Choose another input.")
                }
                let sink = connection.audioSink()
                self.startup(.microphoneStart)
                try self.capture.start(deviceID: device.deviceID, onChunk: { [weak self] chunk, level in
                    sink(chunk)
                    Task { @MainActor in
                        guard let self, self.generation == token, self.phase == .listening || self.phase == .finishing else { return }
                        if !self.loggedAudioBuffer {
                            self.loggedAudioBuffer = true
                            Diagnostics.record(.audioFirstBuffer, session: token)
                        }
                        if level > 0.01, !self.loggedAudioSignal {
                            self.loggedAudioSignal = true
                            Diagnostics.record(.audioFirstSignal, session: token)
                        }
                        self.level = level
                    }
                }, onFailure: { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.fail(message, reason: .audioFailure)
                    }
                })
                self.startup(.listening)
                self.phase = .listening
                try await connecting.value
                try Task.checkCancellation()
                guard self.generation == token else { return }
                self.speechReady = true
                Diagnostics.record(.speechReady, session: token)
            } catch is CancellationError { }
            catch { if self.generation == token { self.fail(error.localizedDescription) } }
        }
    }
    func receiveSpeechEvent(_ event: SpeechEvent) {
        Diagnostics.record(.speechEvent, session: generation)
        transcript.receive(event); rawText = transcript.liveText
    }
    func speechSessionEnded() {
        Diagnostics.record(.speechEnded, session: generation)
        guard phase == .listening else { return }
        stop(automaticallyPaste: false, reviewRequired: true)
    }
    func stop(automaticallyPaste: Bool = true, reviewRequired: Bool = false) {
        guard phase == .listening else { return }
        Diagnostics.record(.finish, reviewRequired ? .sessionEnded : .requested, session: generation)
        capture.stop(flush: true); level = 0; phase = .finishing
        let token = generation
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                // A quick Stop still sends every captured chunk before end,
                // even if the socket was not ready when the user began speaking.
                try await self.connectionStartup?.value
                try Task.checkCancellation()
                guard self.generation == token else { return }
                try await self.connection?.finish()
                guard self.generation == token else { return }
                self.connection?.cancel(); self.connection = nil; self.connectionStartup = nil
                self.rawText = self.transcript.liveText
                self.output = self.rawText
                guard !self.rawText.isEmpty else { Diagnostics.record(.emptyTranscript, session: token); self.phase = .idle; self.notice = "No speech detected."; return }
                if reviewRequired || self.transcript.hasPendingPartial {
                    Diagnostics.record(.reviewRequired, session: token)
                    self.phase = .idle
                    self.notice = self.transcript.hasPendingPartial
                        ? "The last words were not finalized. Review the captured text before inserting it."
                        : "The speech session ended. Review the captured text before inserting it."
                    return
                }
                self.phase = .processing
                let polished = try await self.process(self.rawText, self.snapshot, self.processingKey)
                try Task.checkCancellation()
                guard self.generation == token else { return }
                self.output = polished
                self.phase = .idle
                if automaticallyPaste { self.paste() }
            } catch is CancellationError { }
            catch { if self.generation == token { self.fail(error.localizedDescription) } }
        }
    }
    func cancel() { cancel(reason: .controls) }
    func cancelFromDismiss() { cancel(reason: .dismiss) }
    private func cancel(reason: DiagnosticLog.Detail) {
        Diagnostics.record(.cancel, reason, session: generation)
        pasteOperation?.cancel(); pasteOperation = nil; isPasting = false
        generation = UUID(); operation?.cancel(); operation = nil
        connectionStartup?.cancel(); connectionStartup = nil; speechReady = false
        capture.stop(); connection?.cancel(); connection = nil; level = 0; phase = .idle
        if output.isEmpty { output = rawText }
        notice = "Cancelled. Captured text stays here; nothing was inserted."
    }
    private func fail(_ message: String, reason: DiagnosticLog.Detail = .startupFailure) {
        Diagnostics.record(.failure, reason, session: generation)
        startupLog.error("failed stage=\(self.startupStep.rawValue, privacy: .public)")
        generation = UUID(); operation?.cancel(); connectionStartup?.cancel(); connectionStartup = nil; speechReady = false
        capture.stop(); connection?.cancel(); connection = nil
        if output.isEmpty { output = rawText }
        phase = .idle; level = 0; error = message
    }
    func copy() {
        if copyText() { notice = "Copied."; panelCompletion += 1 }
    }
    private func copyText() -> Bool {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(output.isEmpty ? rawText : output, forType: .string) else {
            error = "Could not write the clipboard. Your text is still here."; return false
        }
        return true
    }
    func paste() {
        Diagnostics.record(.pasteAttempt, session: generation)
        guard !active, !isPasting else { return }
        let text = output.isEmpty ? rawText : output
        guard !text.isEmpty else { return }
        guard copyText() else { return }
        guard AXIsProcessTrusted() else {
            error = "Enable Accessibility for Vaani to paste into other apps. Text is on your clipboard."
            return
        }
        guard let target, !target.isTerminated, target.bundleIdentifier != Bundle.main.bundleIdentifier else {
            error = "No destination app was captured. Start dictation with \(store.shortcut.label) while in your destination app, or use Copy."
            return
        }
        guard let route = PasteRoute.choose(hasField: destination?.pid == target.processIdentifier,
            hasWindow: windowDestination?.pid == target.processIdentifier) else {
            notice = destinationIssue ?? "No editable destination was captured. Nothing was pasted; start dictation from your text field or use Copy."
            return
        }
        let destination = self.destination, windowDestination = self.windowDestination
        let pasteGeneration = generation
        isPasting = true
        target.activate()
        pasteOperation = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == pasteGeneration { self.isPasting = false } }
            do {
                try await PasteDelivery.waitUntilReady(isFrontmost: {
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
                }, modifiersReleased: { PasteDelivery.modifiersReleased }, validate: {
                    switch route {
                case .field:
                    guard let destination else { throw VaaniError.message("The original field is unavailable. Nothing was pasted; use Copy.") }
                    try destination.validate()
                case .window:
                    guard let windowDestination else { throw VaaniError.message("The original window is unavailable. Nothing was pasted; use Copy.") }
                    try windowDestination.validate()
                    }
                    try PasteDelivery.requirePasteEnabled(pid: target.processIdentifier)
                })
                try Task.checkCancellation()
                guard self.generation == pasteGeneration, !self.active else { return }
                try PasteDelivery.dispatch(pid: target.processIdentifier)
                self.error = nil
                Diagnostics.record(.pasteDispatched, session: pasteGeneration)
                self.notice = "Paste sent. Text is also on your clipboard."
                self.panelCompletion += 1
            } catch is CancellationError { }
            catch {
                if self.generation == pasteGeneration { Diagnostics.record(.pasteFailed, session: pasteGeneration); self.error = error.localizedDescription }
                }
        }
    }
}
