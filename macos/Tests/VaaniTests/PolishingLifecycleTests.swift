import Foundation
import XCTest
import VaaniCore
@testable import Vaani

/// Exercises the production Finish/cancel/result path without microphone, Keychain or paste access.
final class PolishingLifecycleTests: XCTestCase {
    @MainActor private final class PendingCompletion {
        var continuation: CheckedContinuation<String, Error>?
        func process(_ text: String, _ preferences: SharedPreferences, _ key: String) async throws -> String {
            XCTAssertEqual(text, "Kal demo hai.")
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }
    private var files: [URL] = []
    override func tearDown() {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        files = []; super.tearDown()
    }
    @MainActor private func model(_ pending: PendingCompletion) throws -> AppModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vaani-polishing-\(UUID()).json")
        files.append(url)
        let store = PreferenceStore(url: url)
        // Success explicitly disables paste; error and cancellation must never attempt it even when enabled.
        store.autoPaste = true
        let model = AppModel(store: store, inventory: {
            ([], ConnectedSetup(fingerprint: "fixture", summary: "Fixture"))
        }, observeDevices: false, process: pending.process)
        let data = Data(#"{"event":"transcript.final","utterance_idx":0,"text":"Kal demo hai."}"#.utf8)
        model.receiveSpeechEvent(try JSONDecoder().decode(SpeechEvent.self, from: data))
        model.phase = .listening
        return model
    }
    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Lifecycle did not reach expected state")
    }
    @MainActor func testSuccessReplacesOutputOnlyAfterCompletion() async throws {
        let pending = PendingCompletion(), model = try model(pending)
        model.stop(automaticallyPaste: false)
        try await waitUntil { pending.continuation != nil }
        XCTAssertEqual(model.phase, .processing)
        XCTAssertEqual(model.output, "Kal demo hai.")
        pending.continuation?.resume(returning: "Kal Vaani ka demo hai.")
        try await waitUntil { !model.active }
        XCTAssertEqual(model.output, "Kal Vaani ka demo hai.")
        XCTAssertEqual(model.rawText, "Kal demo hai.")
        XCTAssertNil(model.error)
    }
    @MainActor func testProviderFailureKeepsRawAndDoesNotAttemptPaste() async throws {
        let pending = PendingCompletion(), model = try model(pending)
        model.stop()
        try await waitUntil { pending.continuation != nil }
        pending.continuation?.resume(throwing: VaaniError.message("Provider unavailable. Raw text is preserved."))
        try await waitUntil { !model.active }
        XCTAssertEqual(model.output, "Kal demo hai.")
        XCTAssertEqual(model.rawText, model.output)
        XCTAssertEqual(model.error, "Provider unavailable. Raw text is preserved.")
    }
    @MainActor func testCancelledLateSuccessCannotReplaceCapturedTextOrNotice() async throws {
        let pending = PendingCompletion(), model = try model(pending)
        model.stop()
        try await waitUntil { pending.continuation != nil }
        model.cancel()
        let notice = model.notice
        XCTAssertEqual(model.phase, .idle)
        // Simulate a provider that ignores cancellation and delivers a late success.
        pending.continuation?.resume(returning: "Late result must not appear")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.output, "Kal demo hai.")
        XCTAssertEqual(model.notice, notice)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.phase, .idle)
    }
    @MainActor func testCancelledLateFailureCannotReplaceCancellationState() async throws {
        let pending = PendingCompletion(), model = try model(pending)
        model.stop()
        try await waitUntil { pending.continuation != nil }
        model.cancel()
        let notice = model.notice
        pending.continuation?.resume(throwing: VaaniError.message("Late provider failure"))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.output, "Kal demo hai.")
        XCTAssertEqual(model.notice, notice)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.phase, .idle)
    }
}
