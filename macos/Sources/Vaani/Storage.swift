import AppKit
import Security
import LocalAuthentication
import VaaniCore
import OSLog

enum KeychainAccessError: LocalizedError {
    case approvalRequired
    var errorDescription: String? { "Keychain access needs approval. Approve the macOS prompt or choose Unlock saved keys in Voice." }
}

enum Vault {
    private static let access = NSLock()
    private static func withAccess<T>(allowInteraction: Bool = false, _ body: () throws -> T) throws -> T {
        guard access.try() else { throw VaaniError.message("Keychain approval is already in progress. Finish or cancel the macOS prompt first.") }
        defer { access.unlock() }
        // Existing v0.1 items live in the classic login Keychain. LAContext's
        // interactionNotAllowed alone does not suppress its ACL prompt on macOS.
        // This legacy, process-local control is required for those existing items.
        let status = SecKeychainSetUserInteractionAllowed(allowInteraction)
        guard status == errSecSuccess else { throw failure(status) }
        defer { SecKeychainSetUserInteractionAllowed(false) }
        return try body()
    }
    static func read(_ account: String, allowInteraction: Bool = false) throws -> String {
        try withAccess(allowInteraction: allowInteraction) {
            let authentication = LAContext(); authentication.interactionNotAllowed = !allowInteraction
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "dev.vaani", kSecAttrAccount as String: account,
                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: authentication]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return "" }
            guard status == errSecSuccess else { throw failure(status) }
            guard let data = result as? Data else { throw VaaniError.message("The saved credential is unreadable. Save the key again.") }
            return String(decoding: data, as: UTF8.self)
        }
    }
    // An explicit Dictate action can request normal OS approval off the main
    // thread. It never bypasses the Keychain ACL or saves an alternative copy.
    static func readForDictation(_ account: String) async throws -> String {
        try await CredentialRead.value(noninteractive: { try read(account) }, authorize: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try read(account, allowInteraction: true)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        })
    }
    // Prompt-capable reads happen only after an explicit Unlock action, off the
    // main thread. A locked/changed Keychain item must never freeze the UI.
    static func unlockSavedKeys() async throws -> (sarvam: String, processing: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let sarvam = try read("sarvam", allowInteraction: true)
                    let processing = try read("processing", allowInteraction: true)
                    continuation.resume(returning: (sarvam, processing))
                }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func failure(_ status: OSStatus) -> Error {
        Logger(subsystem: "dev.vaani.mac", category: "Credentials").error("Keychain status=\(status)")
        if [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(status) {
            return KeychainAccessError.approvalRequired
        }
        return VaaniError.message("Keychain operation failed (\(status)). Your saved credential was not changed.")
    }
    static func save(_ value: String, account: String) throws {
        try withAccess {
            let authentication = LAContext(); authentication.interactionNotAllowed = true
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "dev.vaani", kSecAttrAccount as String: account,
                kSecUseAuthenticationContext as String: authentication]
            if value.isEmpty {
                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
                return
            }
            let data = Data(value.utf8)
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw failure(status) }
        }
    }
}

@MainActor final class PreferenceStore: ObservableObject {
    @Published var shared = SharedPreferences()
    @Published var setups: [String: SetupPreference] = [:]
    @Published var manualProfiles: [String: SetupPreference] = [:]
    @Published var manualProfileID: String?
    @Published var shortcut = DictationShortcut.controlOptionSpace
    @Published var autoPaste = false
    @Published var persistenceError: String?
    private let url: URL
    init(url customURL: URL? = nil) {
        url = customURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vaani/settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let saved = try JSONDecoder().decode(LocalPreferences.self, from: Data(contentsOf: url))
            shared = try saved.shared.validated(); setups = saved.setups; autoPaste = saved.autoPaste
            shortcut = saved.shortcut
            manualProfiles = saved.manualProfiles; manualProfileID = saved.manualProfileID
        } catch { persistenceError = "Could not load settings: \(error.localizedDescription)" }
    }
    @discardableResult func save() -> Bool {
        do {
            _ = try shared.validated()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(local)
            try data.write(to: url, options: .atomic)
            persistenceError = nil
            return true
        } catch { persistenceError = error.localizedDescription; return false }
    }
    func exportSettings() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "vaani-settings.json"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try SharedSettingsFile.encode(shared).write(to: destination, options: .atomic)
        } catch { persistenceError = error.localizedDescription }
    }
    func importSettings() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let incoming = try SharedSettingsFile.read(from: source)
            // Imported endpoint/prompt changes are reviewable before any request is sent.
            let alert = NSAlert(); alert.messageText = "Import shared settings?"
            alert.informativeText = "This replaces language, dictionary and processing settings.\nAPI destination: \(incoming.endpoint)\nProcessing: \(incoming.processingEnabled ? "enabled" : "disabled")\nKeys and microphone choices stay on this Mac."
            alert.addButton(withTitle: "Import"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try applyImportedSettings(incoming)
        } catch { persistenceError = error.localizedDescription }
    }
    func applyImportedSettings(_ incoming: SharedPreferences) throws {
        let before = shared
        shared = try incoming.validated()
        guard save() else {
            shared = before
            throw VaaniError.message(persistenceError ?? "Could not save imported settings.")
        }
    }
    var local: LocalPreferences {
        LocalPreferences(shared: shared, setups: setups, autoPaste: autoPaste,
                         manualProfiles: manualProfiles, manualProfileID: manualProfileID, shortcut: shortcut)
    }
}
