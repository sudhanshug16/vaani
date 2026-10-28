import AVFoundation
import Foundation
import VaaniCore

/// Explicit short acoustic loopback test, using the production capture and STT
/// implementations. No recordings are written; only the supplied fixture plays.
@MainActor enum CaptureSmoke {
    static func run(arguments: [String], model: AppModel) async throws {
        func value(_ flag: String) throws -> String {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                throw VaaniError.message("Provide \(flag) and its fixture path.")
            }
            return arguments[index + 1]
        }
        let fixture = URL(fileURLWithPath: try value("--capture-fixture"))
        let player = try AVAudioPlayer(contentsOf: fixture)
        guard player.duration > 0, player.duration <= 10 else { throw VaaniError.message("Use a synthetic audio fixture of at most ten seconds.") }
        let privateFile = URL(fileURLWithPath: try value("--fixture-key-file"))
        guard (try privateFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4096 else { throw VaaniError.message("Private key fixture too large.") }
        let key = try String(contentsOf: privateFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw VaaniError.message("Private key fixture is empty.") }
        guard let input = DeviceInventory.microphones().first(where: { $0.id == model.selectedUID }) else {
            throw VaaniError.message("Choose and remember the built-in microphone before the acoustic test.")
        }
        print("Requesting microphone access for a short intentional fixture test."); fflush(stdout)
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw VaaniError.message("Microphone permission was denied.") }
        let connection = SpeechConnection(); let capture = AudioCapture()
        defer { player.stop(); capture.stop(); connection.cancel() }
        var transcript = TranscriptAccumulator()
        var failure: String?
        connection.onEvent = { transcript.receive($0) }
        connection.onFailure = { failure = $0.localizedDescription }
        try await connection.connect(key: key, preferences: model.store.shared.validated())
        let sink = connection.audioSink()
        try capture.start(deviceID: input.deviceID, onChunk: { chunk, _ in sink(chunk) }, onFailure: { message in
            Task { @MainActor in failure = message }
        })
        print("Confirmed capture route: \(input.name). Playing synthetic fixture."); fflush(stdout)
        guard player.play() else { throw VaaniError.message("Could not play the fixture.") }
        try await Task.sleep(for: .milliseconds(Int64((player.duration + 1.5) * 1000)))
        guard capture.isUsing(deviceID: input.deviceID) else { throw VaaniError.message("Microphone route changed during the test.") }
        capture.stop()
        if let failure { throw VaaniError.message(failure) }
        try await connection.finish()
        guard !transcript.finalText.isEmpty else { throw VaaniError.message("No speech recognized. Check speaker audibility and microphone route.") }
        print("Microphone final: \(transcript.finalText)")
    }
}
