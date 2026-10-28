package dev.vaani.keyboard

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream

class SharedSettingsFileTest {
    @Test fun unicodeRoundTripDropsPrivateUnknownFields() {
        val original = Preferences.defaults().put("prompt", "Keep café, नमस्ते and 👨‍👩‍👧‍👦.")
            .put("dictionary", JSONArray(listOf("C++", "say \"hello\"", "हिंदी", "😀".repeat(120))))
            .put("sarvamKey", "fixture-only").put("setups", JSONObject().put("desk", "private"))
        val decoded = SharedSettingsFile.read(ByteArrayInputStream(SharedSettingsFile.encode(original)))
        assertEquals(Preferences.canonical(original).toString(), decoded.toString())
        assertFalse(decoded.has("sarvamKey")); assertFalse(decoded.has("setups"))
    }
    @Test fun limitsCountUnicodeCodePointsAcrossScripts() {
        for (word in listOf("😀".repeat(120), "e\u0301".repeat(60)))
            Preferences.validate(Preferences.defaults().put("dictionary", JSONArray(listOf(word))))
        for (word in listOf("😀".repeat(121), "e\u0301".repeat(61)))
            assertThrows(IllegalArgumentException::class.java) { Preferences.validate(Preferences.defaults().put("dictionary", JSONArray(listOf(word)))) }
    }
    @Test fun rejectsOversizedInputAndOversizedExports() {
        assertThrows(IllegalArgumentException::class.java) { SharedSettingsFile.read(ByteArrayInputStream(ByteArray(256001) { 32 })) }
        val large = Preferences.defaults().put("prompt", "😀".repeat(16000))
            .put("dictionary", JSONArray(List(500) { "😀".repeat(120) }))
        Preferences.validate(large)
        assertThrows(IllegalArgumentException::class.java) { SharedSettingsFile.encode(large) }
    }
    @Test fun rejectsInvalidEncodingSchemaAndJSON() {
        for (bytes in listOf(byteArrayOf(0xc3.toByte(), 0x28), "not-json".toByteArray(), Preferences.defaults().put("schemaVersion", 2).toString().toByteArray()))
            assertThrows(Exception::class.java) { SharedSettingsFile.read(ByteArrayInputStream(bytes)) }
    }
}
