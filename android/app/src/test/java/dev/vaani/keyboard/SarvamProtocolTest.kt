package dev.vaani.keyboard

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class SarvamProtocolTest {
    @Test fun dictionaryUsesJsonArrayRatherThanCommaSeparatedText() {
        val words = listOf("Vaani", "New Delhi", "ACME, Inc.", "say \"hello\"", "हिंदी", "C++")
        val settings = Preferences.defaults().put("dictionary", JSONArray(words))
        val url = SarvamProtocol.url(settings, 16000)
        val decoded = JSONArray(url.queryParameter("keyterms"))
        assertEquals(words, (0 until decoded.length()).map { decoded.getString(it) })
        assertEquals("/speech-to-text-realtime/ws", url.encodedPath)
        assertEquals("16000", url.queryParameter("sample_rate"))
        assertEquals("saaras:v4", url.queryParameter("model"))
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
