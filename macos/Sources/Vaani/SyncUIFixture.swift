import CryptoKit
import AppKit
import Foundation
import VaaniCore

/// Explicit opt-in UI acceptance fixture. Personal settings and Keychain are not
/// opened. The actual Devices UI and sync controller run against this store.
@MainActor enum SyncUIFixture {
    private static var directory: URL?
    static func makeModel() -> AppModel {
        let args = CommandLine.arguments
        let index = args.firstIndex(of: "--sync-ui-smoke")
        let bundlePath = Bundle.main.object(forInfoDictionaryKey: "VaaniSyncUIFixtureDirectory") as? String
        guard index != nil || bundlePath != nil else { return AppModel() }
        do {
            let path: String
            if let index {
                guard args.indices.contains(index + 1) else { throw VaaniError.message("Provide a new empty sync UI fixture directory.") }
                path = args[index + 1]
            } else { path = bundlePath! }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                guard try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty else { throw VaaniError.message("Sync UI fixture directory must be empty.") }
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let store = PreferenceStore(url: url.appendingPathComponent("settings.json"))
            store.shared.dictionary = ["Vaani", "Mac UI fixture"]
            guard store.save() else { throw VaaniError.message("Could not save isolated fixture settings.") }
            directory = url
            let secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
            return AppModel(store: store, syncFixtureSecret: secret)
        } catch { print("Sync UI fixture failed: \(error.localizedDescription)"); exit(1) }
    }
    static func run(model: AppModel) async {
        guard let directory else { return }
        let sync = model.settingsSync
        let pairing = directory.appendingPathComponent("pairing.json")
        defer { sync.stop(); try? FileManager.default.removeItem(at: pairing) }
        var previous = ""
        var previousScenario = ""
        var previousPanelState = Data()
        print("Isolated sync UI fixture ready. Use Devices to start sharing; no personal credentials or settings are loaded."); fflush(stdout)
        for _ in 0..<9000 {
            // Synthetic panel states and geometry are confined to this explicit
            // isolated fixture; no audio, personal text or production store.
            if let scenario = try? String(contentsOf: directory.appendingPathComponent("panel-scenario"), encoding: .utf8),
               scenario != previousScenario {
                previousScenario = scenario
                model.error = nil; model.notice = nil
                switch scenario.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "listening": model.rawText = ""; model.output = ""; model.phase = .listening; model.level = 0.7
                case "processing": model.phase = .processing
                case "result": model.rawText = "Kal office mein Vaani ka demo karna hai."; model.output = model.rawText; model.phase = .idle
                case "keychain-error": model.phase = .idle; model.error = "Keychain access needs approval. Approve the macOS prompt or choose Unlock saved keys in Voice."
                case "error": model.phase = .idle; model.error = "The selected microphone disconnected. Your captured words are preserved. Choose another microphone to continue."
                default: model.phase = .idle; model.rawText = ""; model.output = ""
                }
            }
            let windows = NSApp.windows.compactMap { window -> [String: Any]? in
                guard window is DictationPanel else { return nil }
                return ["x": window.frame.minX, "y": window.frame.minY,
                    "width": window.frame.width, "height": window.frame.height,
                    "visible": window.isVisible, "key": window.isKeyWindow, "main": window.isMainWindow]
            }
            if let state = try? JSONSerialization.data(withJSONObject: windows, options: [.sortedKeys]), state != previousPanelState {
                try? state.write(to: directory.appendingPathComponent("panel-state.json"), options: .atomic)
                previousPanelState = state
            }
            if sync.pairingCode != previous {
                previous = sync.pairingCode
                do {
                    if previous.isEmpty { try? FileManager.default.removeItem(at: pairing) }
                    else {
                        try Data(previous.utf8).write(to: pairing, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pairing.path)
                    }
                } catch { sync.stop(); print("Could not write private UI pairing fixture."); break }
            }
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("done").path) { break }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        }
        sync.stop(); try? FileManager.default.removeItem(at: pairing)
        print("Sync UI fixture stopped."); fflush(stdout); exit(0)
    }
}
