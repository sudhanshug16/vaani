package dev.vaani.keyboard

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.ByteBuffer

internal object SharedSettingsFile {
    const val maximumBytes = 256000
    fun read(input: InputStream): JSONObject {
        val bytes = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        while (true) {
            val count = input.read(chunk)
            if (count < 0) break
            require(bytes.size() + count <= maximumBytes) { "Settings file too large" }
            bytes.write(chunk, 0, count)
        }
        val text = Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes.toByteArray())).toString()
        return Preferences.canonical(JSONObject(text))
    }
    fun encode(settings: JSONObject): ByteArray {
        val bytes = Preferences.canonical(settings).toString(2).toByteArray(Charsets.UTF_8)
        require(bytes.size <= maximumBytes) { "Settings file too large. Shorten the prompt or dictionary before exporting." }
        return bytes
    }
}
