package dev.vaani.keyboard

import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

/** One completion request; callers retain raw text until this succeeds. */
object PostProcessor {
    fun process(text: String, settings: JSONObject, key: String, client: OkHttpClient,
                onCall: (Call) -> Unit = {}): String {
        if (!settings.getBoolean("processingEnabled") || text.isBlank()) return text
        Preferences.validate(settings)
        check(settings.getString("model").isNotBlank()) { "Set a processing model" }
        val dictionary = settings.getJSONArray("dictionary")
        val body = JSONObject().put("model", settings.getString("model")).put("stream", false)
            .put("messages", JSONArray().put(JSONObject().put("role", "system").put("content", settings.getString("prompt") + "\nDictionary: " +
                (0 until dictionary.length()).joinToString(", ") { dictionary.getString(it) }))
                .put(JSONObject().put("role", "user").put("content", text)))
        val request = Request.Builder().url(Preferences.completionUrl(settings.getString("endpoint")))
            .post(body.toString().toRequestBody("application/json".toMediaType()))
        if (key.isNotBlank()) request.header("Authorization", "Bearer $key")
        // Keep this boundary safe even if another caller supplies a redirecting client.
        val safeClient = client.newBuilder().followRedirects(false).followSslRedirects(false).build()
        val requestCall = safeClient.newCall(request.build())
        onCall(requestCall)
        requestCall.execute().use { response ->
            check(response.isSuccessful) { "Processing failed (HTTP ${response.code})" }
            val source = response.body?.source() ?: error("Model returned no text")
            source.request(256_001)
            check(source.buffer.size <= 256_000) { "Processing response is too large" }
            val bytes = source.readByteArray()
            val message = JSONObject(String(bytes, Charsets.UTF_8)).getJSONArray("choices").getJSONObject(0).getJSONObject("message")
            val content = message.opt("content")
            check(content is String && content.isNotBlank()) { "Model returned no text" }
            return content.trim()
        }
    }
}
