import Foundation
import XCTest
import VaaniCore
@testable import Vaani

@MainActor private final class SocketFixture: SpeechSocket {
    var messages: [URLSessionWebSocketTask.Message] = []
    var pending: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    var sent: [String] = []
    var onSend: ((String) async throws -> Void)?
    func resume() {}
    func push(_ event: String) {
        if let pending { self.pending = nil; pending.resume(returning: .string(event)) }
        else { messages.append(.string(event)) }
    }
    func receive() async throws -> URLSessionWebSocketTask.Message {
        if !messages.isEmpty { return messages.removeFirst() }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        if case .string(let text) = message { sent.append(text); try await onSend?(text) }
    }
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        pending?.resume(throwing: CancellationError()); pending = nil
    }
}

final class SpeechConnectionTests: XCTestCase {
    @MainActor func testServerEndNotifiesOwnerAndFinishDoesNotSendAgain() async throws {
        let socket = SocketFixture()
        socket.push(#"{"event":"session.begin"}"#)
        let connection = SpeechConnection(makeSocket: { _ in socket })
        defer { connection.cancel() }
        var transcript = TranscriptAccumulator()
        var ended = false
        connection.onEvent = { transcript.receive($0) }
        connection.onEnded = { ended = true }
        connection.onFailure = { error in XCTFail("Normal server end failed: \(error)") }
        try await connection.connect(key: "fixture", preferences: SharedPreferences())
        socket.push(#"{"event":"transcript.final","utterance_idx":0,"text":"Kal Vaani ka demo hai."}"#)
        socket.push(#"{"event":"session.end"}"#)
        for _ in 0..<100 where !ended { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(ended)
        XCTAssertEqual(transcript.finalText, "Kal Vaani ka demo hai.")
        try await connection.finish()
        XCTAssertTrue(socket.sent.isEmpty, "Finishing an ended session must not send a second end event")
    }

    @MainActor func testServerEndBeforeReadyCannotStartCapture() async {
        let socket = SocketFixture()
        socket.push(#"{"event":"session.begin"}"#)
        socket.push(#"{"event":"session.end"}"#)
        let connection = SpeechConnection(makeSocket: { _ in socket })
        defer { connection.cancel() }
        do {
            try await connection.connect(key: "fixture", preferences: SharedPreferences())
            XCTFail("Ended connection must not be handed to capture")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("before recording began"))
        }
        XCTAssertTrue(socket.sent.isEmpty)
    }

    @MainActor func testExplicitFinishDrainsAudioBeforeEndAndRetainsFinal() async throws {
        let socket = SocketFixture()
        socket.push(#"{"event":"session.begin"}"#)
        socket.onSend = { text in
            if text == #"{"event":"end"}"# {
                socket.push(#"{"event":"transcript.final","utterance_idx":0,"text":"final text"}"#)
                socket.push(#"{"event":"session.end"}"#)
            }
        }
        let connection = SpeechConnection(makeSocket: { _ in socket })
        defer { connection.cancel() }
        var transcript = TranscriptAccumulator()
        connection.onEvent = { transcript.receive($0) }
        try await connection.connect(key: "fixture", preferences: SharedPreferences())
        let sink = connection.audioSink()
        sink(Data([1, 2])); sink(Data([3, 4]))
        try await connection.finish()
        XCTAssertEqual(socket.sent.count, 3)
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(socket.sent[0].utf8)) as? [String: String])
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(socket.sent[1].utf8)) as? [String: String])
        XCTAssertEqual(first["audio"], "AQI=")
        XCTAssertEqual(second["audio"], "AwQ=")
        XCTAssertEqual(socket.sent.last, #"{"event":"end"}"#)
        XCTAssertEqual(transcript.finalText, "final text")
    }

    @MainActor func testServerEndCancelsPendingAudioSendWithoutReportingFailure() async throws {
        let socket = SocketFixture()
        socket.push(#"{"event":"session.begin"}"#)
        socket.onSend = { _ in try await Task.sleep(for: .seconds(30)) }
        let connection = SpeechConnection(makeSocket: { _ in socket })
        defer { connection.cancel() }
        var ended = false
        connection.onEnded = { ended = true }
        connection.onFailure = { _ in XCTFail("Cancelling audio after server end is not a new failure") }
        try await connection.connect(key: "fixture", preferences: SharedPreferences())
        connection.audioSink()(Data([1, 2]))
        for _ in 0..<100 where socket.sent.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(socket.sent.count, 1)
        socket.push(#"{"event":"session.end"}"#)
        for _ in 0..<100 where !ended { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(ended)
        try await connection.finish()
        await Task.yield()
        XCTAssertEqual(socket.sent.count, 1)
    }
    @MainActor func testAudioCapturedBeforeReadyDrainsBeforeQuickFinish() async throws {
        let socket = SocketFixture()
        let connection = SpeechConnection(makeSocket: { _ in socket })
        defer { connection.cancel() }
        let startup = Task { try await connection.connect(key: "fixture", preferences: SharedPreferences()) }
        let sink = connection.audioSink()
        sink(Data([1, 2])); sink(Data([3, 4]))
        let finish = Task { try await startup.value; try await connection.finish() }
        await Task.yield()
        XCTAssertTrue(socket.sent.isEmpty, "Audio must wait for the server handshake")
        socket.onSend = { text in
            if text == #"{"event":"end"}"# { socket.push(#"{"event":"session.end"}"#) }
        }
        socket.push(#"{"event":"session.begin"}"#)
        try await finish.value
        XCTAssertEqual(socket.sent.count, 3)
        let messages = try socket.sent.prefix(2).map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String]) }
        XCTAssertEqual(messages.map { $0["audio"] }, ["AQI=", "AwQ="])
        XCTAssertEqual(socket.sent.last, #"{"event":"end"}"#)
    }
    @MainActor func testCancelledHandshakeDoesNotSendBufferedAudio() async {
        let socket = SocketFixture()
        let connection = SpeechConnection(makeSocket: { _ in socket })
        let startup = Task { try await connection.connect(key: "fixture", preferences: SharedPreferences()) }
        connection.audioSink()(Data([1, 2]))
        await Task.yield()
        startup.cancel(); connection.cancel()
        do { try await startup.value; XCTFail("Cancelled setup must not succeed") }
        catch { }
        XCTAssertTrue(socket.sent.isEmpty)
    }
    @MainActor func testStartupBufferOverflowFailsRatherThanDroppingWordsSilently() async {
        let connection = SpeechConnection(makeSocket: { _ in SocketFixture() })
        defer { connection.cancel() }
        var failed = false
        connection.onFailure = { _ in failed = true }
        let sink = connection.audioSink()
        for _ in 0..<161 { sink(Data([1, 2])) }
        for _ in 0..<100 where !failed { await Task.yield() }
        XCTAssertTrue(failed)
    }
}
