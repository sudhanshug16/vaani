import Foundation
import XCTest
import VaaniCore
@testable import Vaani

final class TranscriptRecoveryTests: XCTestCase {
    private var files: [URL] = []
    override func tearDown() {
        for url in files { try? FileManager.default.removeItem(at: url) }
        files = []; super.tearDown()
    }
    @MainActor private func model() -> AppModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vaani-transcript-\(UUID()).json")
        files.append(url)
        let store = PreferenceStore(url: url)
        store.autoPaste = true
        return AppModel(store: store, inventory: {
            ([Microphone(id: "builtin", name: "Built-in", deviceID: 1)], ConnectedSetup(fingerprint: "fixture", summary: "Fixture"))
        }, observeDevices: false)
    }
    private func event(_ type: String, _ index: Int, _ text: String) throws -> SpeechEvent {
        let data = try JSONSerialization.data(withJSONObject: ["event": "transcript.\(type)", "utterance_idx": index, "text": text])
        return try JSONDecoder().decode(SpeechEvent.self, from: data)
    }
    @MainActor private func settle(_ model: AppModel) async throws {
        for _ in 0..<100 where model.active { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.phase, .idle)
    }

    @MainActor func testUnexpectedEndKeepsFinalAndPartialWithoutAttemptingPaste() async throws {
        let model = model()
        model.receiveSpeechEvent(try event("final", 0, "Kal office mein"))
        model.receiveSpeechEvent(try event("partial", 1, "Sarvam aur Vaani"))
        model.phase = .listening
        model.speechSessionEnded()
        try await settle(model)
        XCTAssertEqual(model.rawText, "Kal office mein Sarvam aur Vaani")
        XCTAssertEqual(model.output, model.rawText)
        XCTAssertTrue(model.notice?.contains("not finalized") == true)
        XCTAssertNil(model.error, "Automatic paste must not run on a review result")
    }

    @MainActor func testExplicitFinishWithUnfinishedWordsAlsoRequiresReview() async throws {
        let model = model()
        model.receiveSpeechEvent(try event("partial", 0, "Kal demo"))
        model.phase = .listening
        model.stop()
        try await settle(model)
        XCTAssertEqual(model.output, "Kal demo")
        XCTAssertTrue(model.notice?.contains("not finalized") == true)
        XCTAssertNil(model.error)
    }

    @MainActor func testUnexpectedEndWithOnlyFinalsStillRequiresReview() async throws {
        let model = model()
        model.receiveSpeechEvent(try event("final", 0, "Kal demo hai."))
        model.phase = .listening
        model.speechSessionEnded()
        try await settle(model)
        XCTAssertEqual(model.output, "Kal demo hai.")
        XCTAssertTrue(model.notice?.contains("speech session ended") == true)
        XCTAssertNil(model.error)
    }

    @MainActor func testNormalFinishReplacesPartialAndDoesNotShowReviewNotice() async throws {
        let model = model()
        model.receiveSpeechEvent(try event("partial", 0, "Kal demo"))
        model.receiveSpeechEvent(try event("final", 0, "Kal demo hai."))
        model.phase = .listening
        model.stop(automaticallyPaste: false)
        // A session.end arriving during explicit Finish must not start another stop.
        model.speechSessionEnded()
        try await settle(model)
        XCTAssertEqual(model.output, "Kal demo hai.")
        XCTAssertNil(model.notice)
        XCTAssertNil(model.error)
    }
}
