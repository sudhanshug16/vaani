import Foundation

public struct TranscriptAccumulator {
    private var finals: [Int: String] = [:]
    private var partials: [Int: String] = [:]
    public init() {}
    public var finalText: String { finals.keys.sorted().compactMap { finals[$0] }.joined(separator: " ") }
    public var hasPendingPartial: Bool { partials.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    public var liveText: String {
        Set(finals.keys).union(partials.keys).sorted().compactMap { finals[$0] ?? partials[$0] }.joined(separator: " ")
    }
    public mutating func receive(_ event: SpeechEvent) {
        guard let index = event.utteranceIndex, let text = event.text else { return }
        if event.event == "transcript.final" { finals[index] = text; partials[index] = nil }
        else if event.event == "transcript.partial", finals[index] == nil { partials[index] = text }
    }
}

public struct SpeechEvent: Decodable {
    public let event: String
    public let utteranceIndex: Int?
    public let text: String?
    public let message: String?
    public let isFatal: Bool?
    enum CodingKeys: String, CodingKey {
        case event, text, message
        case utteranceIndex = "utterance_idx", isFatal = "is_fatal"
    }
}

public enum SarvamProtocol {
    public static func url(preferences: SharedPreferences) -> URL {
        let useHints = preferences.recognitionHintsEnabled && !preferences.dictionary.isEmpty
        var url = URLComponents(string: "wss://api.sarvam.ai/speech-to-text-realtime/ws")!
        url.queryItems = [
            .init(name: "model", value: useHints ? "saaras:v4" : preferences.sarvamModel),
            .init(name: "language_code", value: preferences.language),
            .init(name: "mode", value: preferences.mode),
            .init(name: "stream_type", value: "balanced"),
            .init(name: "encoding", value: "linear16"),
            .init(name: "sample_rate", value: "16000"),
            .init(name: "endpointing", value: "vad")
        ]
        if useHints {
            let terms = try! JSONEncoder().encode(preferences.dictionary)
            url.queryItems?.append(.init(name: "keyterms", value: String(decoding: terms, as: UTF8.self)))
        }
        return url.url!
    }
    public static func audioMessage(_ pcm: Data) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["event": "audio_input", "audio": pcm.base64EncodedString()])
        return String(decoding: data, as: UTF8.self)
    }
}
