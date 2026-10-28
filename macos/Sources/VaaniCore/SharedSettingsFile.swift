import Foundation

/// The portable file boundary; credentials and local microphone preferences are absent.
public enum SharedSettingsFile {
    public static let maximumBytes = 256_000
    public static func decode(_ data: Data) throws -> SharedPreferences {
        guard data.count <= maximumBytes else { throw VaaniError.message("Settings file is too large.") }
        return try JSONDecoder().decode(SharedPreferences.self, from: data).validated()
    }
    public static func read(from url: URL) throws -> SharedPreferences {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while data.count <= maximumBytes {
            guard let chunk = try file.read(upToCount: min(8192, maximumBytes + 1 - data.count)), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return try decode(data)
    }
    public static func encode(_ preferences: SharedPreferences) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences.validated())
        guard data.count <= maximumBytes else { throw VaaniError.message("Settings file is too large. Shorten the prompt or dictionary before exporting.") }
        return data
    }
}
