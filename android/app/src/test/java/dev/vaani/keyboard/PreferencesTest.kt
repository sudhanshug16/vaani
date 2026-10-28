package dev.vaani.keyboard

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PreferencesTest {
    @Test fun legacySettingsAndServiceTierRoundTrip() {
        val legacy = Preferences.defaults().apply { remove("serviceTier") }
        assertEquals("", Preferences.canonical(legacy).getString("serviceTier"))
        for (tier in Preferences.serviceTiers) {
            assertEquals(tier, Preferences.canonical(Preferences.defaults().put("serviceTier", tier)).getString("serviceTier"))
        }
        for (invalid in listOf("unknown", 42, JSONObject.NULL)) {
            assertThrows(IllegalArgumentException::class.java) { Preferences.canonical(Preferences.defaults().put("serviceTier", invalid)) }
        }
        assertEquals("https://example.com/v1/responses", Preferences.responsesUrl("https://example.com/v1/chat/completions/"))
    }
    @Test fun importedUnknownFieldsCannotLeakIntoAnExport() {
        val imported = Preferences.defaults().put("sarvamKey", "do-not-export").put("setups", JSONObject().put("mic", "private"))
        val exported = Preferences.canonical(imported)
        assertFalse(exported.has("sarvamKey")); assertFalse(exported.has("setups"))
        assertEquals("translit", exported.getString("mode"))
    }
    @Test fun rejectsFutureSchemaAndCoercedTypes() {
        assertThrows(IllegalArgumentException::class.java) { Preferences.validate(Preferences.defaults().put("schemaVersion", 2)) }
        assertThrows(IllegalArgumentException::class.java) { Preferences.validate(Preferences.defaults().put("schemaVersion", "1")) }
        assertThrows(IllegalArgumentException::class.java) { Preferences.validate(Preferences.defaults().put("processingEnabled", "true")) }
    }
    @Test fun validatesRemoteEndpointBeforeAKeyCanBeSent() {
        listOf("http://remote.example/v1", "https://user:secret@example.com/v1", "file:///tmp/data", "https://example.com?token=test").forEach { url ->
            assertThrows(IllegalArgumentException::class.java) { Preferences.responsesUrl(url) }
        }
        assertEquals("http://localhost:1234/v1/responses", Preferences.responsesUrl("http://localhost:1234/v1/"))
        assertEquals("https://example.com/v1/responses", Preferences.responsesUrl("https://example.com/v1/responses"))
    }
    @Test fun rejectsOversizedAndNonStringDictionary() {
        assertThrows(IllegalArgumentException::class.java) { Preferences.validate(Preferences.defaults().put("dictionary", JSONArray().put(42))) }
        assertThrows(IllegalArgumentException::class.java) { Preferences.validate(Preferences.defaults().put("dictionary", JSONArray(List(501) { "word" }))) }
    }
    @Test fun sharedSettingsRoundTripPreservesIndianLanguageAndPrompt() {
        val source = Preferences.defaults().put("language", "mr-IN").put("mode", "transcribe")
            .put("dictionary", JSONArray(listOf("Vaani", "Sarvam"))).put("prompt", "Preserve the original language.")
        val result = Preferences.canonical(JSONObject(source.toString()))
        assertEquals("mr-IN", result.getString("language"))
        assertEquals("transcribe", result.getString("mode"))
        assertEquals("Preserve the original language.", result.getString("prompt"))
        assertEquals("Sarvam", result.getJSONArray("dictionary").getString(1))
    }
}
