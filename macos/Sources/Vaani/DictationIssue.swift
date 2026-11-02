import Foundation
import VaaniCore

/// UI recovery copy and allowlisted diagnostic codes; never persist provider bodies.
struct DictationIssue: Equatable {
    let title: String
    let recovery: String
    let detail: String
    let diagnostic: DiagnosticLog.Detail
    let dashboard: Bool
    var actionLabel: String { dashboard ? "Open Sarvam dashboard" : "Open settings" }
    static let dashboardURL = URL(string: "https://indus.sarvam.ai/")!
    init(_ message: String) {
        detail = message
        let text = message.lowercased()
        dashboard = text.contains("credits exhausted") || text.contains("insufficient credits") || text.contains("credit balance")
        if dashboard {
            title = "Sarvam credits exhausted"
            recovery = "Add credits in your Sarvam dashboard, then try again."
            diagnostic = .creditsExhausted
        } else if text.contains("keychain") {
            title = "Saved keys need approval"
            recovery = "Open Voice → Unlock saved keys and approve the macOS prompt."
            diagnostic = .keychainApproval
        } else if text.contains("processing") || text.contains("polishing") {
            title = "Polishing failed"
            recovery = "Your captured text is preserved. Check the provider in Polish settings."
            diagnostic = .processing
        } else if text.contains("401") || text.contains("unauthorized") || text.contains("invalid api key") || text.contains("invalid subscription") {
            title = "Sarvam API key rejected"
            recovery = "Check or replace your Sarvam API key in Voice settings."
            diagnostic = .providerAuthentication
        } else if text.contains("429") || text.contains("rate limit") || text.contains("too many requests") {
            title = "Sarvam rate limit reached"
            recovery = "Wait a moment, then try dictation again."
            diagnostic = .providerRateLimited
        } else if text.contains("timed out") || text.contains("timeout") || text.contains("within 15 seconds") {
            title = "Speech connection timed out"
            recovery = "Check your connection and try again. Full details are in Settings."
            diagnostic = .networkTimeout
        } else if text.contains("network") || text.contains("internet") || text.contains("could not connect") || text.contains("cannot connect") || text.contains("server could not be found") {
            title = "Couldn’t connect to speech service"
            recovery = "Check your internet connection, then try again."
            diagnostic = .networkUnavailable
        } else if text.contains("microphone access") || text.contains("microphone permission") {
            title = "Microphone access is off"
            recovery = "Open Voice settings and allow microphone access."
            diagnostic = .microphonePermission
        } else if text.contains("microphone") || text.contains("input") && text.contains("disconnected") {
            title = "Microphone needs attention"
            recovery = message
            diagnostic = .microphoneChoice
        } else {
            title = "Dictation failed"
            recovery = message
            diagnostic = .unknownFailure
        }
    }
}
