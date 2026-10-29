package dev.vaani.keyboard

import org.json.JSONObject
import java.util.Base64
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class SyncPairing(val host: String, val port: Int, val secret: String) {
    fun validated(): SyncPairing {
        require(isTailnetAddress(host) && port in 1024..65535 && Base64.getDecoder().decode(secret).size == 32) {
            "Use a Vaani pairing code with a Tailscale IPv4 address."
        }
        return this
    }
    fun json() = JSONObject().put("version", 1).put("host", host).put("port", port).put("secret", secret)
    companion object {
        fun parse(text: String): SyncPairing {
            require(text.length in 1..4096) { "Pairing code too large or empty" }
            val data = JSONObject(text)
            require(data.get("version") is Int && data.getInt("version") == 1 && data.get("port") is Int) { "Unsupported pairing version" }
            require(data.get("host") is String && data.get("secret") is String) { "Invalid pairing code" }
            return SyncPairing(data.getString("host"), data.getInt("port"), data.getString("secret")).validated()
        }
        fun isTailnetAddress(host: String): Boolean {
            val parts = host.split('.')
            if (parts.size != 4 || parts.any { it.toIntOrNull() !in 0..255 || it.toIntOrNull().toString() != it }) return false
            return parts[0] == "100" && parts[1].toInt() in 64..127
        }
    }
}

/** Only provider credentials; never pairing secrets or arbitrary preference fields. */
class SyncCredentials(val sarvam: String? = null, val processing: String? = null) {
    init { require(listOfNotNull(sarvam, processing).all { it.toByteArray(Charsets.UTF_8).size <= 16384 }) { "Sync credential exceeds size limit" } }
    fun entries() = listOf("sarvam" to sarvam, "processing" to processing).mapNotNull { (account, value) ->
        value?.takeIf { it.isNotBlank() }?.let { account to it }
    }
    fun json() = JSONObject().also { result -> entries().forEach { (account, value) -> result.put(account, value) } }
    fun summary() = entries().joinToString(", ") { if (it.first == "sarvam") "Sarvam" else "Polishing" }.ifBlank { "None (saved keys stay unchanged)" }
    override fun toString() = "SyncCredentials(<redacted>)"
    companion object {
        fun parse(value: JSONObject): SyncCredentials {
            fun key(name: String): String? {
                if (!value.has(name) || value.isNull(name)) return null
                require(value.get(name) is String) { "Invalid sync credential" }
                return value.getString(name)
            }
            return SyncCredentials(key("sarvam"), key("processing"))
        }
    }
}

object SyncProtocol {
    const val maximumFrame = 256000
    private fun aad(direction: String) = "dev.vaani.settings.v1.$direction".toByteArray(Charsets.UTF_8)
    fun seal(data: ByteArray, secret: String, direction: String): ByteArray {
        require(data.size <= maximumFrame - 28) { "Settings exceed sync size limit" }
        val key = Base64.getDecoder().decode(secret)
        require(key.size == 32)
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad(direction))
        return nonce + cipher.doFinal(data)
    }
    fun open(data: ByteArray, secret: String, direction: String): ByteArray {
        require(data.size in 28..maximumFrame) { "Invalid sync frame" }
        val key = Base64.getDecoder().decode(secret)
        require(key.size == 32)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, data.copyOfRange(0, 12)))
        cipher.updateAAD(aad(direction))
        return cipher.doFinal(data, 12, data.size - 12)
    }
    fun request(operation: String, revision: String? = null, settings: JSONObject? = null, credentials: SyncCredentials? = null): JSONObject {
        require(operation in listOf("get", "offer"))
        val result = JSONObject().put("version", 2).put("id", UUID.randomUUID().toString())
            .put("timestamp", System.currentTimeMillis() / 1000).put("operation", operation)
        if (operation == "offer") {
            require(revision?.matches(Regex("[0-9a-f]{64}")) == true) { "Refresh settings before sending" }
            result.put("expectedRevision", revision).put("settings", Preferences.canonical(settings ?: error("Missing settings")))
            result.put("credentials", (credentials ?: SyncCredentials()).json())
        }
        return result
    }
}
