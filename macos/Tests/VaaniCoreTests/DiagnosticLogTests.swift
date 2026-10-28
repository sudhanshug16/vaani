import XCTest
@testable import VaaniCore

final class DiagnosticLogTests: XCTestCase {
    func testBoundedPrivateMetadataLog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory, limit: 1024)
        let session = UUID()
        for _ in 0..<50 { log.record(.command, .shortcut, session: session) }
        log.flush()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), ["events.jsonl", "events.previous.jsonl"])
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        for file in files {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            let data = try Data(contentsOf: file)
            XCTAssertLessThanOrEqual(data.count, 1024)
            for line in data.split(separator: 10) {
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
                XCTAssertEqual(Set(object.keys), ["timestamp", "process", "run", "event", "detail", "session"])
                XCTAssertEqual(object["event"] as? String, "command")
                XCTAssertEqual(object["detail"] as? String, "shortcut")
                XCTAssertEqual(object["session"] as? String, session.uuidString)
            }
        }
    }
}
