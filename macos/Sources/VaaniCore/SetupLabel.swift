import Foundation

public enum SetupLabel {
    /// Readable names only. Hardware IDs/serials remain in the routing fingerprint.
    public static func make(displays: [String], peripherals: [String]) -> String {
        func names(_ values: [String]) -> [String] {
            let cleaned = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let counts = Dictionary(grouping: cleaned, by: { $0 }).mapValues(\.count)
            return counts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map {
                counts[$0] == 1 ? $0 : "\($0) × \(counts[$0]!)"
            }
        }
        let parts = names(displays) + names(peripherals)
        return parts.isEmpty ? "This Mac" : parts.joined(separator: " + ")
    }
}
