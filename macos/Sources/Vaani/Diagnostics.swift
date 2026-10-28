import Foundation
import VaaniCore

enum Diagnostics {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vaani/diagnostics", isDirectory: true)
    }
    static let log: DiagnosticLog? = {
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--") }),
              Bundle.main.object(forInfoDictionaryKey: "VaaniSyncUIFixtureDirectory") == nil,
              !ProcessInfo.processInfo.arguments.contains(where: { $0.contains(".xctest") }),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              Bundle.main.bundleIdentifier == "dev.vaani.mac" else { return nil }
        let log = DiagnosticLog(directory: directory)
        log.record(.launch)
        return log
    }()
    static func record(_ event: DiagnosticLog.Event, _ detail: DiagnosticLog.Detail? = nil, session: UUID? = nil, count: Int? = nil) {
        log?.record(event, detail, session: session, count: count)
    }
}
