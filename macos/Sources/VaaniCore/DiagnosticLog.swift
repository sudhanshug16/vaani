import Foundation

/// Metadata only: callers cannot attach text, credentials, device names, or provider bodies.
public final class DiagnosticLog: @unchecked Sendable {
    public enum Event: String, Codable {
        case launch, command, phase, startup, failure, speechEnded, speechEvent, audioFirstBuffer
        case audioFirstSignal, finish, emptyTranscript, reviewRequired, cancel, pasteAttempt, pasteDispatched, pasteFailed
        case shortcutTriggered, shortcutRegistered, shortcutTapDisabled, commandRejected, deviceChange, deviceSettled, microphoneInventory, microphoneSelection, privateAggregatesFiltered
    }
    public enum Detail: String, Codable {
        case idle, connecting, listening, finishing, processing
        case destination, preferences, credentials, microphonePermission, speechConnection, microphoneStart
        case shortcut, panel, controls, dismiss, sessionEnded, requested, startupFailure, streamFailure, audioFailure, inputChanged
        case devicesSettling, microphoneChoice, busy, fixture
        case remembered, onlyAvailable, ask, missingRemembered, unavailable, selected, unselected
    }
    public struct Entry: Codable {
        public let timestamp: Date
        public let process: Int32
        public let run: UUID
        public let event: Event
        public let detail: Detail?
        public let session: UUID?
        public let count: Int?
    }
    private let queue = DispatchQueue(label: "dev.vaani.diagnostics")
    private let directory: URL
    private let limit: Int
    private let run = UUID()
    public init(directory: URL, limit: Int = 262_144) {
        self.directory = directory; self.limit = max(1024, limit)
    }
    public func record(_ event: Event, _ detail: Detail? = nil, session: UUID? = nil, count: Int? = nil) {
        let entry = Entry(timestamp: Date(), process: ProcessInfo.processInfo.processIdentifier,
                          run: run, event: event, detail: detail, session: session, count: count)
        queue.async { [self] in
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                var data = try encoder.encode(entry); data.append(0x0a)
                let current = directory.appendingPathComponent("events.jsonl")
                let previous = directory.appendingPathComponent("events.previous.jsonl")
                let size = (try? fm.attributesOfItem(atPath: current.path)[.size] as? NSNumber)?.intValue ?? 0
                if size + data.count > limit {
                    if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
                    if fm.fileExists(atPath: current.path) { try fm.moveItem(at: current, to: previous) }
                }
                if !fm.fileExists(atPath: current.path) {
                    guard fm.createFile(atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return }
                }
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
                let handle = try FileHandle(forWritingTo: current)
                defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: data)
            } catch { /* Diagnostics must never interrupt dictation. */ }
        }
    }
    public func flush() { queue.sync {} }
}
