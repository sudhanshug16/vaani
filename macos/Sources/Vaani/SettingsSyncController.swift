import AppKit
import CryptoKit
import Darwin
import Network
import SwiftUI
import VaaniCore

@MainActor final class SettingsSyncController: ObservableObject {
    @Published var host: String
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var message = "Start sharing on your Tailscale address, then pair Android."
    @Published private(set) var pending: SharedPreferences?
    @Published private(set) var pairingCode = ""
    private var ephemeralSecret: String?
    private var fixtureCredentials = SyncCredentials()
    private let store: PreferenceStore
    private let isBusy: () -> Bool
    private let loadSharingSecret: () async throws -> String
    private let addresses: () -> [String]
    private var listener: NWListener?
    private var peers: [UUID: SyncPeer] = [:]
    private var replay = SyncReplayGuard()
    @Published private(set) var pendingKeySummary = ""
    private var pendingCredentials: SyncCredentials?
    private var pendingRevision: String?
    private var generation = UUID()

    init(store: PreferenceStore, isBusy: @escaping () -> Bool, ephemeralSecret: String? = nil,
         loadSharingSecret: @escaping () async throws -> String = { try await Vault.sharingSecret() },
         addresses: @escaping () -> [String] = { SettingsSyncController.tailnetAddresses() }) {
        self.store = store; self.isBusy = isBusy; self.ephemeralSecret = ephemeralSecret
        self.loadSharingSecret = loadSharingSecret; self.addresses = addresses
        host = UserDefaults.standard.string(forKey: "vaani.sync.host") ?? addresses().first ?? ""
    }
    nonisolated static func tailnetAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var results: Set<String> = []; var cursor = head
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: buffer)
                if SyncPairing.isTailnetAddress(value) { results.insert(value) }
            }
        }
        return results.sorted()
    }
    func start(fixtureSecret: String? = nil) {
        guard !running, !starting, listener == nil else { return }
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard addresses().contains(address) else {
            message = "Choose a Tailscale IPv4 address currently assigned to this Mac. Connect Tailscale first."
            return
        }
        if let fixtureSecret { ephemeralSecret = fixtureSecret }
        let token = UUID(); generation = token; starting = true
        message = "Unlocking sharing credential… Approve the macOS Keychain prompt if shown."
        Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.starting = false } }
            do {
                let secret: String
                if let fixture = self.ephemeralSecret {
                    let value = fixture.isEmpty ? SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() } : fixture
                    self.ephemeralSecret = value; secret = value
                } else { secret = try await self.loadSharingSecret() }
                guard self.generation == token else { return } // Stop/revoke while OS approval was pending.
                guard self.addresses().contains(address) else { throw VaaniError.message("Tailscale disconnected while unlocking sharing. Reconnect and try again.") }
                try self.startListener(address: address, secret: secret, token: token)
            } catch {
                guard self.generation == token else { return }
                self.message = error.localizedDescription
            }
        }
    }
    private func startListener(address: String, secret: String, token: UUID) throws {
        let pairing = try SyncPairing(host: address, secret: secret).validated()
        let pairSecret = pairing.secret
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(address), port: NWEndpoint.Port(rawValue: pairing.port)!)
        let service = try NWListener(using: parameters)
        service.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                switch state {
                case .ready:
                    self.running = true; self.pairingCode = (try? pairing.code()) ?? ""
                    self.host = address; UserDefaults.standard.set(address, forKey: "vaani.sync.host")
                    self.message = "Ready on \(address):\(pairing.port). Android can Sync now."
                case .failed:
                    self.stop(); self.message = "Could not listen on Tailscale. Check that the address is connected and the port is available."
                default: break
                }
            }
        }
        service.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.generation == token, self.running, self.peers.count < 8 else { connection.cancel(); return }
                let id = UUID()
                let peer = SyncPeer(connection: connection, secret: pairSecret,
                    handle: { [weak self] request in
                        guard let self, self.generation == token else { throw VaaniError.message("Sync stopped.") }
                        return try self.handle(request)
                    }, closed: { [weak self] in self?.peers[id] = nil })
                self.peers[id] = peer; peer.start()
            }
        }
        listener = service; message = "Starting Tailscale sharing…"
        service.start(queue: .main)
    }
    func stop() {
        generation = UUID(); starting = false; listener?.cancel(); listener = nil
        let active = Array(peers.values); peers.removeAll(); active.forEach { $0.close() }
        running = false; pairingCode = ""; pending = nil; pendingRevision = nil; pendingCredentials = nil; pendingKeySummary = ""
        message = "Sharing stopped. Paired devices cannot connect until you start it again."
    }
    func revoke() {
        stop()
        do {
            if ephemeralSecret != nil { ephemeralSecret = "" }
            else { try Vault.save("", account: "settings-sync") }
            message = "Pairing revoked. Start sharing to create a new code."
        }
        catch { message = error.localizedDescription }
    }
    private func credentials() throws -> SyncCredentials {
        if ephemeralSecret != nil { return fixtureCredentials } // Isolated fixtures never open personal Keychain.
        return try SyncCredentials(sarvam: Vault.read("sarvam"), processing: Vault.read("processing")).validated()
    }
    private func handle(_ request: SyncRequest) throws -> SyncResponse {
        try replay.accept(request)
        guard !isBusy() else { return SyncResponse(id: request.id, status: "dictating", version: request.version) }
        let keys = request.version == 2 ? try credentials() : nil
        let revision = try SettingsSync.revision(store.shared, credentials: keys)
        if request.operation == "get" {
            return SyncResponse(id: request.id, status: "ok", revision: revision, settings: try store.shared.validated(), credentials: keys, version: request.version)
        }
        guard request.expectedRevision == revision else { return SyncResponse(id: request.id, status: "conflict", version: request.version) }
        guard pending == nil else { return SyncResponse(id: request.id, status: "pending", version: request.version) }
        pending = try request.settings?.validated(); pendingRevision = revision
        pendingCredentials = request.version == 2 ? try (request.credentials ?? SyncCredentials()).validated() : nil
        pendingKeySummary = pendingCredentials?.entries.map { $0.0 == "sarvam" ? "Sarvam" : "Polishing" }.joined(separator: ", ") ?? ""
        message = "Android sent settings. Review the provider destination below before applying."
        return SyncResponse(id: request.id, status: "review", version: request.version)
    }
    func applyPending() {
        do {
            guard !isBusy(), let incoming = pending, pendingRevision == (try SettingsSync.revision(store.shared, credentials: pendingCredentials == nil ? nil : credentials())) else {
                throw VaaniError.message("Mac settings changed or dictation is active. Discard this offer and Sync now again.")
            }
            let before = store.shared
            try (pendingCredentials ?? SyncCredentials()).apply(read: { account in
                if self.ephemeralSecret != nil { return self.fixtureCredentials.entries.first { $0.0 == account }?.1 ?? "" }
                return try Vault.read(account)
            }, save: { account, value in
                if self.ephemeralSecret != nil {
                    if account == "sarvam" { self.fixtureCredentials.sarvam = value }
                    if account == "processing" { self.fixtureCredentials.processing = value }
                    return
                }
                try Vault.save(value, account: account)
            }, persist: {
                store.shared = try incoming.validated()
                guard store.save() else { store.shared = before; throw VaaniError.message("Could not save incoming settings.") }
            })
            pending = nil; pendingRevision = nil; pendingCredentials = nil; pendingKeySummary = ""; message = "Settings and available API keys from Android applied. Microphone choices stayed on this Mac."
        } catch { message = error.localizedDescription }
    }
    func discardPending() { pending = nil; pendingRevision = nil; pendingCredentials = nil; pendingKeySummary = ""; message = "Incoming settings discarded." }
    func copyPairingCode() {
        guard !pairingCode.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(pairingCode, forType: .string)
        message = "Pairing code copied. Treat it like a password; share only with your Android."
    }
}

@MainActor private final class SyncPeer {
    private let connection: NWConnection
    private let secret: String
    private let handle: (SyncRequest) throws -> SyncResponse
    private let closed: () -> Void
    private var buffer = Data()
    private var expected: Int?
    private var deadline: Task<Void, Never>?
    private var finished = false
    init(connection: NWConnection, secret: String, handle: @escaping (SyncRequest) throws -> SyncResponse, closed: @escaping () -> Void) {
        self.connection = connection; self.secret = secret; self.handle = handle; self.closed = closed
    }
    func start() {
        connection.start(queue: .main)
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.close()
        }
        receive()
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(8192, SettingsSync.maximumFrame + 4 - buffer.count)) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.finished else { return }
                if let data { self.buffer.append(data) }
                do {
                    if self.expected == nil, self.buffer.count >= 4 {
                        let size = self.buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                        guard (28...SettingsSync.maximumFrame).contains(size) else { self.close(); return }
                        self.expected = size
                    }
                    if let size = self.expected, self.buffer.count >= size + 4 {
                        guard self.buffer.count == size + 4 else { self.close(); return }
                        let plain = try SettingsSync.open(Data(self.buffer.dropFirst(4)), secret: self.secret, direction: "request")
                        let request = try JSONDecoder().decode(SyncRequest.self, from: plain)
                        let response = try self.handle(request)
                        let encrypted = try SettingsSync.seal(JSONEncoder().encode(response), secret: self.secret, direction: "response")
                        let frame = try SettingsSync.frame(encrypted)
                        self.connection.send(content: frame, completion: .contentProcessed { [weak self] _ in Task { @MainActor in self?.close() } })
                        return
                    }
                    if complete || error != nil { self.close() } else { self.receive() }
                } catch { self.close() } // Authentication errors reveal no plaintext or key material.
            }
        }
    }
    func close() {
        guard !finished else { return }
        finished = true; deadline?.cancel(); connection.cancel(); closed()
    }
}
