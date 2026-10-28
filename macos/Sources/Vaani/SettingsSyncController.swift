import AppKit
import CryptoKit
import Darwin
import Network
import SwiftUI
import VaaniCore

@MainActor final class SettingsSyncController: ObservableObject {
    @Published var host: String
    @Published private(set) var running = false
    @Published private(set) var message = "Start sharing on your Tailscale address, then pair Android."
    @Published private(set) var pending: SharedPreferences?
    @Published private(set) var pairingCode = ""
    private var ephemeralSecret: String?
    private let store: PreferenceStore
    private let isBusy: () -> Bool
    private var listener: NWListener?
    private var peers: [UUID: SyncPeer] = [:]
    private var replay = SyncReplayGuard()
    private var pendingRevision: String?
    private var generation = UUID()

    init(store: PreferenceStore, isBusy: @escaping () -> Bool, ephemeralSecret: String? = nil) {
        self.store = store; self.isBusy = isBusy; self.ephemeralSecret = ephemeralSecret
        host = UserDefaults.standard.string(forKey: "vaani.sync.host") ?? Self.tailnetAddresses().first ?? ""
    }
    static func tailnetAddresses() -> [String] {
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
        guard !running, listener == nil else { return }
        do {
            let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.tailnetAddresses().contains(address) else { throw VaaniError.message("Choose a Tailscale IPv4 address currently assigned to this Mac. Connect Tailscale first.") }
            var secret = try fixtureSecret ?? ephemeralSecret ?? Vault.read("settings-sync")
            if secret.isEmpty {
                secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
                if ephemeralSecret != nil { ephemeralSecret = secret }
                else { try Vault.save(secret, account: "settings-sync") }
            }
            let pairing = try SyncPairing(host: address, secret: secret).validated()
            let pairSecret = pairing.secret
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(address), port: NWEndpoint.Port(rawValue: pairing.port)!)
            let service = try NWListener(using: parameters)
            let token = UUID(); generation = token
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
        } catch { message = error.localizedDescription }
    }
    func stop() {
        generation = UUID(); listener?.cancel(); listener = nil
        let active = Array(peers.values); peers.removeAll(); active.forEach { $0.close() }
        running = false; pairingCode = ""; pending = nil; pendingRevision = nil
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
    private func handle(_ request: SyncRequest) throws -> SyncResponse {
        try replay.accept(request)
        guard !isBusy() else { return SyncResponse(id: request.id, status: "dictating") }
        let revision = try SettingsSync.revision(store.shared)
        if request.operation == "get" {
            return SyncResponse(id: request.id, status: "ok", revision: revision, settings: try store.shared.validated())
        }
        guard request.expectedRevision == revision else { return SyncResponse(id: request.id, status: "conflict") }
        guard pending == nil else { return SyncResponse(id: request.id, status: "pending") }
        pending = try request.settings?.validated(); pendingRevision = revision
        message = "Android sent settings. Review the provider destination below before applying."
        return SyncResponse(id: request.id, status: "review")
    }
    func applyPending() {
        do {
            guard !isBusy(), let incoming = pending, pendingRevision == (try SettingsSync.revision(store.shared)) else {
                throw VaaniError.message("Mac settings changed or dictation is active. Discard this offer and Sync now again.")
            }
            let before = store.shared; store.shared = try incoming.validated()
            guard store.save() else { store.shared = before; throw VaaniError.message("Could not save incoming settings.") }
            pending = nil; pendingRevision = nil; message = "Settings from Android applied. Keys and microphones stayed on this Mac."
        } catch { message = error.localizedDescription }
    }
    func discardPending() { pending = nil; pendingRevision = nil; message = "Incoming settings discarded." }
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
