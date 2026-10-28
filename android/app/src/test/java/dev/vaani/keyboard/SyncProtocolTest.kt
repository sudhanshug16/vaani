package dev.vaani.keyboard

import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

class SyncProtocolTest {
    private val secret = Base64.getEncoder().encodeToString(ByteArray(32) { 7 })
    @Test fun pairingRejectsNonTailnetDestinationsAndBadSecrets() {
        for (host in listOf("100.64.0.1", "100.127.255.254")) assertEquals(host, SyncPairing.parse(SyncPairing(host, 47831, secret).json().toString()).host)
        for (host in listOf("127.0.0.1", "192.168.1.1", "100.63.1.1", "100.128.1.1", "100.064.0.1", "example.com", "100.64.0.256")) {
            assertThrows(IllegalArgumentException::class.java) { SyncPairing(host, 47831, secret).validated() }
        }
        assertThrows(IllegalArgumentException::class.java) { SyncPairing("100.64.0.1", 47831, "weak").validated() }
    }
    @Test fun ciphertextRejectsWrongKeyTamperingAndReflection() {
        val source = "private dictionary".toByteArray()
        val frame = SyncProtocol.seal(source, secret, "request")
        assertArrayEquals(source, SyncProtocol.open(frame, secret, "request"))
        assertThrows(Exception::class.java) { SyncProtocol.open(frame, secret, "response") }
        assertThrows(Exception::class.java) { SyncProtocol.open(frame, Base64.getEncoder().encodeToString(ByteArray(32) { 8 }), "request") }
        val changed = frame.copyOf(); changed[15] = (changed[15].toInt() xor 1).toByte()
        assertThrows(Exception::class.java) { SyncProtocol.open(changed, secret, "request") }
        assertFalse(frame.contentEquals(SyncProtocol.seal(source, secret, "request")))
    }
    @Test fun offersRequireRevisionAndExcludeUnknownSettings() {
        assertThrows(IllegalArgumentException::class.java) { SyncProtocol.request("offer") }
        val settings = Preferences.defaults().put("sarvamKey", "secret").put("microphone", "built-in")
        val offer = SyncProtocol.request("offer", "a".repeat(64), settings).getJSONObject("settings")
        assertFalse(offer.has("sarvamKey")); assertFalse(offer.has("microphone"))
        assertThrows(IllegalArgumentException::class.java) { SyncProtocol.seal(ByteArray(256000), secret, "request") }
    }
}
