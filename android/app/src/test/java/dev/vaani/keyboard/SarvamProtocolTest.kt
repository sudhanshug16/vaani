package dev.vaani.keyboard

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class SarvamProtocolTest {
    @Test fun dictionaryUsesJsonArrayRatherThanCommaSeparatedText() {
        val words = listOf("Vaani", "New Delhi", "ACME, Inc.", "say \"hello\"", "हिंदी", "C++")
        val settings = Preferences.defaults().put("dictionary", JSONArray(words)).put("recognitionHintsEnabled", true)
        val url = SarvamProtocol.url(settings, 16000)
        val decoded = JSONArray(url.queryParameter("keyterms"))
        assertEquals(words, (0 until decoded.length()).map { decoded.getString(it) })
        assertEquals("/speech-to-text-realtime/ws", url.encodedPath)
        assertEquals("16000", url.queryParameter("sample_rate"))
        assertEquals("saaras:v4", url.queryParameter("model"))
    }
    @Test fun dictionaryDoesNotBiasSpeechWithoutExplicitOptIn() {
        val settings = Preferences.defaults().put("sarvamModel", "saaras:v4").put("dictionary", JSONArray(listOf("Acme", "Nova")))
        val url = SarvamProtocol.url(settings, 16000)
        assertNull(url.queryParameter("keyterms"))
        assertEquals("saaras:v4", url.queryParameter("model"))
        settings.remove("recognitionHintsEnabled")
        settings.put("prompt", Preferences.legacyDefaultPrompt.replace(" ", "\n") + " ")
        val migrated = Preferences.canonical(settings)
        assertFalse(migrated.getBoolean("recognitionHintsEnabled"))
        assertEquals(Preferences.defaultPrompt, migrated.getString("prompt"))
        assertEquals(2, migrated.getJSONArray("dictionary").length())
        assertEquals("Custom prompt.", Preferences.canonical(settings.put("prompt", "Custom prompt.")).getString("prompt"))
        assertThrows(IllegalArgumentException::class.java) { Preferences.canonical(settings.put("recognitionHintsEnabled", "true")) }
    }
    @Test fun emptyDictionaryOmitsHintsAndBluetoothRetainsSampleRate() {
        val url = SarvamProtocol.url(Preferences.defaults(), 8000)
        assertNull(url.queryParameter("keyterms"))
        assertEquals("8000", url.queryParameter("sample_rate"))
        assertEquals("saaras:v3-realtime", url.queryParameter("model"))
        val selectedV4 = SarvamProtocol.url(Preferences.defaults().put("sarvamModel", "saaras:v4"), 16000)
        assertEquals("saaras:v4", selectedV4.queryParameter("model"))
    }
}
