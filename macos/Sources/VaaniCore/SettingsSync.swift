import Foundation
import CryptoKit

/// A pairing code is a credential. Never include it in shared settings or logs.
public struct SyncPairing: Codable, Equatable {
    public var version: Int
    public var host: String
    public var port: UInt16
    public var secret: String
    public init(host: String, port: UInt16 = 47831, secret: String) {
        self.version = 1; self.host = host; self.port = port; self.secret = secret
    }
    public func validated() throws -> Self {
        guard version == 1, Self.isTailnetAddress(host), port > 1023,
              let key = Data(base64Encoded: secret), key.count == 32 else {
            throw VaaniError.message("Use a Vaani v1 pairing code with a Tailscale IPv4 address and a 256-bit secret.")
        }
        return self
    }
    public static func isTailnetAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ part in
            guard let number = UInt8(part) else { return false }
            return String(number) == part
        }) else { return false }
        return parts[0] == "100" && (64...127).contains(Int(parts[1])!)
    }
    public func code() throws -> String { String(decoding: try JSONEncoder().encode(validated()), as: UTF8.self) }
}

public struct SyncRequest: Codable {
    public var version = 1
    public var id: String
    public var timestamp: Int64
    public var operation: String
    public var expectedRevision: String?
    public var settings: SharedPreferences?
    public init(id: String = UUID().uuidString, timestamp: Int64 = Int64(Date().timeIntervalSince1970),
                operation: String, expectedRevision: String? = nil, settings: SharedPreferences? = nil) {
        self.id = id; self.timestamp = timestamp; self.operation = operation
        self.expectedRevision = expectedRevision; self.settings = settings
    }
    public func validated(now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> Self {
        guard version == 1, UUID(uuidString: id) != nil, timestamp >= now - 120, timestamp <= now + 120,
              ["get", "offer"].contains(operation) else { throw VaaniError.message("Invalid or expired sync request. Check device clocks.") }
        if operation == "offer" {
            guard expectedRevision?.count == 64, let settings else { throw VaaniError.message("Sync offer is missing settings or revision.") }
            _ = try settings.validated()
        }
        return self
    }
}

public struct SyncResponse: Codable {
    public var version = 1
    public var id: String
    public var status: String
    public var revision: String?
    public var settings: SharedPreferences?
    public init(id: String, status: String, revision: String? = nil, settings: SharedPreferences? = nil) {
        self.id = id; self.status = status; self.revision = revision; self.settings = settings
    }
}

public enum SettingsSync {
    public static let maximumFrame = 256_000
    // Domain and direction bind the ciphertext to this protocol. A request
    // cannot be reflected as a response, even with a valid authentication tag.
    private static func aad(_ direction: String) -> Data { Data("dev.vaani.settings.v1.\(direction)".utf8) }
    public static func seal(_ data: Data, secret: String, direction: String) throws -> Data {
        guard let bytes = Data(base64Encoded: secret), bytes.count == 32, data.count <= maximumFrame - 28 else {
            throw VaaniError.message("Invalid sync key or oversized settings.")
        }
        return try AES.GCM.seal(data, using: SymmetricKey(data: bytes), authenticating: aad(direction)).combined!
    }
    public static func open(_ data: Data, secret: String, direction: String) throws -> Data {
        guard let bytes = Data(base64Encoded: secret), bytes.count == 32, (28...maximumFrame).contains(data.count) else {
            throw VaaniError.message("Invalid sync envelope.")
        }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: bytes), authenticating: aad(direction))
    }
    public static func revision(_ settings: SharedPreferences) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(settings.validated())).map { String(format: "%02x", $0) }.joined()
    }
    public static func frame(_ data: Data) throws -> Data {
        guard (28...maximumFrame).contains(data.count) else { throw VaaniError.message("Invalid sync frame size.") }
        var length = UInt32(data.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + data
    }
}

/// Bounded, process-local replay protection. Old packets also expire by time.
public struct SyncReplayGuard {
    private var requests: [String: Int64] = [:]
    public init() {}
    public mutating func accept(_ request: SyncRequest, now: Int64 = Int64(Date().timeIntervalSince1970)) throws {
        _ = try request.validated(now: now)
        requests = requests.filter { $0.value >= now - 120 }
        guard requests[request.id] == nil, requests.count < 1024 else { throw VaaniError.message("Repeated sync request or sync rate limit reached.") }
        requests[request.id] = request.timestamp
    }
}
