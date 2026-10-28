import Foundation

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
        var request = URLRequest(url: try SharedPreferences.completionsURL(preferences.endpoint))
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": preferences.model,
            "messages": [["role": "system", "content": preferences.prompt + "\nDictionary: " + preferences.dictionary.joined(separator: ", ")],
                         ["role": "user", "content": text]], "stream": false])
        let session = URLSession(configuration: configuration, delegate: ProcessingNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw VaaniError.message("Post-processing failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Raw text is preserved.")
        }
        guard data.count <= 256_000 else { throw VaaniError.message("The processing response is too large. Raw text is preserved.") }
        struct Completion: Decodable { struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }; let choices: [Choice] }
        guard let output = try JSONDecoder().decode(Completion.self, from: data).choices.first?.message.content,
              !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VaaniError.message("The model returned no text. Raw text is preserved.") }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
