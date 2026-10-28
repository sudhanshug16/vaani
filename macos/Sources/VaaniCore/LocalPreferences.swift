import Foundation

/// Local routing state is deliberately separate from SharedPreferences exports.
public struct LocalPreferences: Codable, Equatable {
    public var shared: SharedPreferences
    public var setups: [String: SetupPreference]
    public var shortcut: DictationShortcut
    public var autoPaste: Bool
    public var manualProfiles: [String: SetupPreference]
    public var manualProfileID: String?

    public init(shared: SharedPreferences = .init(), setups: [String: SetupPreference] = [:],
                autoPaste: Bool = false, manualProfiles: [String: SetupPreference] = [:], manualProfileID: String? = nil, shortcut: DictationShortcut = .controlOptionSpace) {
        self.shortcut = shortcut
        self.shared = shared; self.setups = setups; self.autoPaste = autoPaste
        self.manualProfiles = manualProfiles; self.manualProfileID = manualProfileID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        shared = try values.decode(SharedPreferences.self, forKey: .shared)
        setups = try values.decode([String: SetupPreference].self, forKey: .setups)
        autoPaste = try values.decode(Bool.self, forKey: .autoPaste)
        shortcut = try values.decodeIfPresent(DictationShortcut.self, forKey: .shortcut) ?? .controlOptionSpace
        // The first app build predates manual profiles. Preserve its settings.
        manualProfiles = try values.decodeIfPresent([String: SetupPreference].self, forKey: .manualProfiles) ?? [:]
        manualProfileID = try values.decodeIfPresent(String.self, forKey: .manualProfileID)
    }

    public func preference(for hardware: String) -> SetupPreference? {
        if let manualProfileID {
            // A dangling explicit profile must not fall through to another mic.
            return manualProfiles[manualProfileID] ?? SetupPreference(name: "Missing profile", microphoneUID: "")
        }
        return setups[hardware]
    }
}
