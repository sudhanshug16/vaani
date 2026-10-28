import Foundation
import CryptoKit

private final class ProcessingNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public enum PostProcessor {
    public static func process(_ text: String, preferences: SharedPreferences, key: String) async throws -> String {
        try await process(text, preferences: preferences, key: key, configuration: .ephemeral)
    }
    static func process(_ text: String, preferences: SharedPreferences, key: String, configuration: URLSessionConfiguration) async throws -> String {
        guard preferences.processingEnabled, !text.isEmpty else { return text }
        guard !preferences.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VaaniError.message("Set a post-processing model first.") }
        _ = try preferences.validated()
        try Task.checkCancellation()
        var request = URLRequest(url: try SharedPreferences.responsesURL(preferences.endpoint))
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let dictionary = String(decoding: try JSONEncoder().encode(preferences.dictionary), as: UTF8.self)
        let instructions = preferences.prompt + "\nPreferred spellings as JSON: " + dictionary
        let input = String(decoding: try JSONEncoder().encode(["transcript": text]), as: UTF8.self)
        // Stable developer prefix before the changing transcript. No transcript
        // or per-request identifier enters the cache routing key.
        let digest = SHA256.hash(data: Data(instructions.utf8)).map { String(format: "%02x", $0) }.joined()
        var body: [String: Any] = ["model": preferences.model,
            "input": [["role": "developer", "content": instructions], ["role": "user", "content": input]],
            "prompt_cache_key": "vaani-polish-v1-" + digest.prefix(48), "store": false, "stream": false]
        if !preferences.serviceTier.isEmpty { body["service_tier"] = preferences.serviceTier }
        if !preferences.reasoningEffort.isEmpty { body["reasoning"] = ["effort": preferences.reasoningEffort] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let session = URLSession(configuration: configuration, delegate: ProcessingNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw VaaniError.message("Post-processing failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Raw text is preserved.")
        }
        guard data.count <= 256_000 else { throw VaaniError.message("The processing response is too large. Raw text is preserved.") }
        struct Response: Decodable {
            struct Item: Decodable {
                struct Content: Decodable { let type: String; let text: String? }
                let type: String; let role: String?; let status: String?; let content: [Content]?
            }
            let status: String; let output: [Item]
        }
        let responseBody = try JSONDecoder().decode(Response.self, from: data)
        guard responseBody.status == "completed" else { throw VaaniError.message("Polishing did not complete. Raw text is preserved.") }
        var parts: [String] = []
        for item in responseBody.output where item.type != "reasoning" {
            guard item.type == "message", item.role == "assistant", item.status == "completed", let content = item.content else {
                throw VaaniError.message("Unexpected polishing output. Raw text is preserved.")
            }
            for block in content {
                guard block.type == "output_text", let text = block.text else {
                    throw VaaniError.message("The model returned no text or refused polishing. Raw text is preserved.")
                }
                parts.append(text)
            }
        }
        let output = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw VaaniError.message("The model returned no text. Raw text is preserved.") }
        return output
    }
}
