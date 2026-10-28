import XCTest
@testable import VaaniCore

final class VaaniCoreTests: XCTestCase {
    let laptop = Microphone(id: "builtin", name: "Mac microphone", deviceID: 1)
    let usb = Microphone(id: "usb-stable", name: "USB microphone", deviceID: 2)
    func testRememberedMicrophoneWinsDespiteEnumerationOrder() {
        let preference = SetupPreference(name: "Office", microphoneUID: usb.id)
        XCTAssertEqual(MicrophonePolicy.decide(available: [laptop, usb], preference: preference), .remembered(usb))
        XCTAssertEqual(MicrophonePolicy.decide(available: [usb, laptop], preference: preference), .remembered(usb))
    }
    func testMissingPreferredMicNeverSilentlyFallsBack() {
        XCTAssertEqual(MicrophonePolicy.decide(available: [laptop], preference: .init(name: "Office", microphoneUID: usb.id)), .missingRemembered)
    }
    func testUnknownSetupAsksOnlyWhenAmbiguous() {
        XCTAssertEqual(MicrophonePolicy.decide(available: [laptop, usb], preference: nil), .ask)
        XCTAssertEqual(MicrophonePolicy.decide(available: [laptop], preference: nil), .onlyAvailable(laptop))
        XCTAssertEqual(MicrophonePolicy.decide(available: [], preference: nil), .unavailable)
    }
    func testSetupFingerprintIgnoresEnumerationOrder() {
        XCTAssertEqual(MicrophonePolicy.fingerprint(displays: ["a", "b"], peripherals: ["hub", "mic"]), MicrophonePolicy.fingerprint(displays: ["b", "a"], peripherals: ["mic", "hub"]))
        XCTAssertNotEqual(MicrophonePolicy.fingerprint(displays: ["a"], peripherals: ["hub"]), MicrophonePolicy.fingerprint(displays: ["a"], peripherals: []))
    }
    func event(_ json: String) throws -> SpeechEvent { try JSONDecoder().decode(SpeechEvent.self, from: Data(json.utf8)) }
    func testPartialsReplaceAndFinalsDeduplicate() throws {
        var transcript = TranscriptAccumulator()
        transcript.receive(try event(#"{"event":"transcript.partial","utterance_idx":0,"text":"kal"}"#))
        transcript.receive(try event(#"{"event":"transcript.partial","utterance_idx":0,"text":"kal office"}"#))
        XCTAssertEqual(transcript.liveText, "kal office")
        let final = try event(#"{"event":"transcript.final","utterance_idx":0,"text":"Kal office jaana hai."}"#)
        transcript.receive(final); transcript.receive(final)
        transcript.receive(try event(#"{"event":"transcript.partial","utterance_idx":0,"text":"late partial"}"#))
        XCTAssertEqual(transcript.liveText, "Kal office jaana hai.")
        XCTAssertEqual(transcript.finalText, "Kal office jaana hai.")
    }
    func testOutOfOrderFinalsPreserveUtteranceOrder() throws {
        var transcript = TranscriptAccumulator()
        transcript.receive(try event(#"{"event":"transcript.final","utterance_idx":1,"text":"second"}"#))
        transcript.receive(try event(#"{"event":"transcript.final","utterance_idx":0,"text":"first"}"#))
        XCTAssertEqual(transcript.finalText, "first second")
    }
    func testPostProcessingURLValidation() throws {
        XCTAssertEqual(try SharedPreferences.responsesURL("https://example.com/v1/").absoluteString, "https://example.com/v1/responses")
        XCTAssertEqual(try SharedPreferences.responsesURL("http://localhost:1234/v1/responses").path, "/v1/responses")
        for invalid in ["http://remote.test/v1", "https://user:secret@example.com", "file:///tmp/x", "https://example.com?token=abc"] {
            XCTAssertThrowsError(try SharedPreferences.responsesURL(invalid))
        }
    }
    func testSharedExportHasNoCredentialsOrDeviceIdentity() throws {
        let preferences = SharedPreferences()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
        XCTAssertNil(object["sarvamKey"]); XCTAssertNil(object["processingKey"]); XCTAssertNil(object["setups"])
        XCTAssertEqual(try preferences.validated().mode, "translit")
    }
    func testRejectsFutureSchemaAndOversizedDictionary() {
        var preferences = SharedPreferences(); preferences.schemaVersion = 2
        XCTAssertThrowsError(try preferences.validated())
        preferences.schemaVersion = 1; preferences.dictionary = Array(repeating: "word", count: 501)
        XCTAssertThrowsError(try preferences.validated())
    }
    func testSarvamWireFormatUsesCurrentRealtimeProtocol() throws {
        let url = SarvamProtocol.url(preferences: SharedPreferences())
        XCTAssertEqual(url.path, "/speech-to-text-realtime/ws")
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(params.first { $0.name == "sample_rate" }?.value, "16000")
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SarvamProtocol.audioMessage(Data([1, 2, 3])).utf8)) as? [String: String])
        XCTAssertEqual(wire["event"], "audio_input"); XCTAssertEqual(wire["audio"], "AQID")
    }
    func testDictionaryHintsAreAJSONEncodedArray() throws {
        var preferences = SharedPreferences()
        preferences.recognitionHintsEnabled = true
        preferences.dictionary = ["Vaani", "New Delhi", "ACME, Inc.", "say \"hello\"", "हिंदी", "C++"]
        let url = SarvamProtocol.url(preferences: preferences)
        let params = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let hints = try XCTUnwrap(params.first { $0.name == "keyterms" }?.value)
        XCTAssertEqual(params.first { $0.name == "model" }?.value, "saaras:v4")
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: Data(hints.utf8)), preferences.dictionary)
        let empty = URLComponents(url: SarvamProtocol.url(preferences: SharedPreferences()), resolvingAgainstBaseURL: false)!
        XCTAssertFalse(empty.queryItems!.contains { $0.name == "keyterms" })
        XCTAssertEqual(empty.queryItems!.first { $0.name == "model" }?.value, "saaras:v3-realtime")
    }
    func testDictionaryDoesNotBiasSpeechWithoutExplicitOptIn() throws {
        var prefs = SharedPreferences(); prefs.sarvamModel = "saaras:v4"; prefs.dictionary = ["Acme", "Nova"]
        let url = try XCTUnwrap(URLComponents(url: SarvamProtocol.url(preferences: prefs), resolvingAgainstBaseURL: false))
        XCTAssertFalse(url.queryItems!.contains { $0.name == "keyterms" })
        XCTAssertEqual(url.queryItems!.first { $0.name == "model" }?.value, "saaras:v4")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(prefs)) as? [String: Any])
        object.removeValue(forKey: "recognitionHintsEnabled")
        object["prompt"] = SharedPreferences.legacyDefaultPrompt + " "
        let legacy = try JSONDecoder().decode(SharedPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(legacy.recognitionHintsEnabled)
        XCTAssertEqual(legacy.dictionary, prefs.dictionary)
        XCTAssertEqual(legacy.prompt, SharedPreferences.defaultPrompt)
        object["prompt"] = "My custom punctuation rules."
        XCTAssertEqual(try JSONDecoder().decode(SharedPreferences.self, from: JSONSerialization.data(withJSONObject: object)).prompt, "My custom punctuation rules.")
        object["recognitionHintsEnabled"] = "true"
        XCTAssertThrowsError(try JSONDecoder().decode(SharedPreferences.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    func testSharedExampleImportsAndStripsUnknownFieldsOnReexport() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("shared/preferences.example.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["sarvamKey"] = "must-not-be-exported"
        let preferences = try JSONDecoder().decode(SharedPreferences.self, from: JSONSerialization.data(withJSONObject: object)).validated()
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
        XCTAssertEqual(preferences.dictionary, ["Vaani", "Sarvam", "Tailscale"])
        XCTAssertNil(exported["sarvamKey"])
    }
}
