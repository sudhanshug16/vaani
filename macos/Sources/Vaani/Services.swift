import Foundation
import VaaniCore

// Redirects are refused so an API key cannot follow an endpoint redirect.
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

// Injectable at the transport boundary so lifecycle tests exercise the real
// receiver/sender without a microphone, saved credential or external provider.
@MainActor protocol SpeechSocket: AnyObject {
    func resume()
    func receive() async throws -> URLSessionWebSocketTask.Message
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}
extension URLSessionWebSocketTask: SpeechSocket {}

@MainActor final class SpeechConnection {
    private let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    private var socket: (any SpeechSocket)?
    private let makeSocket: ((URLRequest) -> any SpeechSocket)?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var continuation: AsyncStream<Data>.Continuation?
    private let audio: AsyncStream<Data>
    private var ready = false
    private var ended = false
    private var failure: Error?
    var onEvent: ((SpeechEvent) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onEnded: (() -> Void)?

    init(makeSocket: ((URLRequest) -> any SpeechSocket)? = nil) {
        self.makeSocket = makeSocket
        // Capture can begin while the socket opens. Bound the in-memory queue
        // to ~16 seconds of 100 ms chunks, just above the connection deadline.
        var sink: AsyncStream<Data>.Continuation?
        audio = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(160)) { sink = $0 }
        continuation = sink
    }

    func connect(key: String, preferences: SharedPreferences) async throws {
        var request = URLRequest(url: SarvamProtocol.url(preferences: preferences))
        request.setValue(key, forHTTPHeaderField: "Api-Subscription-Key")
        let socket: any SpeechSocket = makeSocket?(request) ?? session.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    let data: Data
                    switch message { case .data(let bytes): data = bytes; case .string(let text): data = Data(text.utf8); @unknown default: continue }
                    let event = try JSONDecoder().decode(SpeechEvent.self, from: data)
                    guard let self else { return }
                    if event.event == "session.begin" { self.ready = true }
                    if event.event == "error" { throw VaaniError.message(event.message ?? "Sarvam rejected the session.") }
                    if event.event == "session.end" {
                        self.ended = true
                        self.continuation?.finish(); self.sender?.cancel()
                        self.onEvent?(event); self.onEnded?()
                        break
                    }
                    self.onEvent?(event)
                }
            } catch {
                guard let self, !Task.isCancelled, !self.ended else { return }
                self.failure = error; self.onFailure?(error)
            }
        }
        for _ in 0..<150 {
            if let failure { throw failure }
            if ready { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard ready else { throw VaaniError.message("Sarvam did not begin a session within 15 seconds.") }
        guard !ended else { throw VaaniError.message("Sarvam ended the session before recording began. Try again.") }
        let stream = audio
        sender = Task { [weak self] in
            do {
                for await chunk in stream {
                    try Task.checkCancellation()
                    try await socket.send(.string(SarvamProtocol.audioMessage(chunk)))
                }
            } catch {
                guard let self, !Task.isCancelled, !self.ended else { return }
                self.failure = error; self.onFailure?(error)
            }
        }
    }
    func audioSink() -> (Data) -> Void {
        let sink = continuation
        // AsyncStream.Continuation is thread-safe: queue PCM directly from the
        // audio callback, so a MainActor hop cannot put trailing audio after end.
        return { [weak self] data in
            if let sink, case .dropped = sink.yield(data) {
                Task { @MainActor in
                    guard let self, self.failure == nil else { return }
                    let error = VaaniError.message("Connection is too slow for live audio. Recording stopped; retry on a stable connection.")
                    self.failure = error; self.onFailure?(error)
                }
            }
        }
    }
    func finish() async throws {
        if let failure { throw failure }
        if ended { return }
        let deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, !self.ended else { return }
            let error = VaaniError.message("Final transcript timed out. Partial text has been kept below.")
            self.failure = error
            self.sender?.cancel(); self.socket?.cancel(with: .goingAway, reason: nil)
        }
        defer { deadline.cancel() }
        continuation?.finish(); await sender?.value
        if let failure { throw failure }
        if ended { return }
        try await socket?.send(.string("{\"event\":\"end\"}"))
        for _ in 0..<150 {
            if let failure { throw failure }
            if ended { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw VaaniError.message("Final transcript timed out. Partial text has been kept below.")
    }
    func cancel() {
        continuation?.finish(); sender?.cancel(); receiver?.cancel()
        socket?.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel()
    }
}
