package dev.vaani.keyboard

import okhttp3.OkHttpClient
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.net.ServerSocket
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

class PostProcessorTest {
    private fun settings(port: Int) = Preferences.defaults().put("processingEnabled", true)
        .put("endpoint", "http://127.0.0.1:$port/v1/").put("model", "fixture-model")
        .put("prompt", "Preserve Hinglish.").put("dictionary", org.json.JSONArray(listOf("Sarvam", "Vaani")))
    private fun reply(status: Int = 200, body: String, checkRequest: (String, Map<String, String>, String) -> Unit = { _, _, _ -> }) {
        ServerSocket(0).use { server ->
            server.soTimeout = 5000
            val served = CompletableFuture.runAsync {
                server.accept().use { socket ->
                    socket.soTimeout = 5000
                    val input = socket.getInputStream().bufferedReader()
                    val path = input.readLine()
                    val headers = linkedMapOf<String, String>()
                    while (true) {
                        val line = input.readLine()
                        if (line.isEmpty()) break
                        headers[line.substringBefore(':').lowercase()] = line.substringAfter(':').trim()
                    }
                    val requestBody = CharArray(headers.getValue("content-length").toInt())
                    var offset = 0
                    while (offset < requestBody.size) { val count = input.read(requestBody, offset, requestBody.size - offset); check(count > 0); offset += count }
                    checkRequest(path, headers, String(requestBody))
                    val bytes = body.toByteArray()
                    socket.getOutputStream().apply {
                        write("HTTP/1.1 $status Fixture\r\nContent-Length: ${bytes.size}\r\nContent-Type: application/json\r\nLocation: http://127.0.0.1:1/leak\r\nConnection: close\r\n\r\n".toByteArray())
                        write(bytes); flush()
                    }
                }
            }
            try { action(settings(server.localPort)) } finally { served.get(8, TimeUnit.SECONDS) }
        }
    }
    private var action: (JSONObject) -> Unit = {}
    @Test fun requestPreservesHinglishPromptDictionaryAndAuth() {
        action = { assertEquals("Kal Sarvam aur Vaani ka demo hai.", PostProcessor.process("kal sarvam aur vani ka demo hai", it, "fixture-key", OkHttpClient())) }
        reply(body = """{"status":"completed","output":[{"type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":"  Kal Sarvam aur Vaani ka demo hai.  "}]}]}""") { path, headers, body ->
            assertEquals("POST /v1/responses HTTP/1.1", path)
            assertEquals("Bearer fixture-key", headers["authorization"])
            val request = JSONObject(body)
            assertEquals("fixture-model", request.getString("model")); assertFalse(request.getBoolean("stream"))
            val messages = request.getJSONArray("input")
            assertEquals("Preserve Hinglish.\nDictionary: Sarvam, Vaani", messages.getJSONObject(0).getString("content"))
            assertEquals("kal sarvam aur vani ka demo hai", messages.getJSONObject(1).getString("content"))
        }
    }
    @Test fun tiersAndStableCachePrefixAcrossTranscripts() {
        val keys = mutableSetOf<String>()
        for (tier in Preferences.serviceTiers) {
            action = { prefs ->
                prefs.put("serviceTier", tier)
                assertEquals("Kal office.", PostProcessor.process("different transcript $tier", prefs, "", OkHttpClient()))
            }
            reply(body = """{"status":"completed","output":[{"type":"reasoning"},{"type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":"Kal "},{"type":"output_text","text":"office."}]}]}""") { _, _, body ->
                val request = JSONObject(body)
                if (tier.isEmpty()) assertFalse(request.has("service_tier")) else assertEquals(tier, request.getString("service_tier"))
                assertFalse(request.getBoolean("store")); assertFalse(request.has("messages"))
                assertEquals("developer", request.getJSONArray("input").getJSONObject(0).getString("role"))
                keys.add(request.getString("prompt_cache_key"))
            }
        }
        assertEquals(1, keys.size)
        assertTrue(keys.first().length <= 64)
        action = { prefs ->
            prefs.put("prompt", "Changed prompt")
            PostProcessor.process("raw", prefs, "", OkHttpClient())
        }
        reply(body = """{"status":"completed","output":[{"type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":"Done."}]}]}""") { _, _, body ->
            assertFalse(keys.contains(JSONObject(body).getString("prompt_cache_key")))
        }
    }
    @Test fun incompleteAndRefusalAreRejectedEvenWithText() {
        for (body in listOf(
            """{"status":"incomplete","output":[{"type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":"partial"}]}]}""",
            """{"status":"completed","output":[{"type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":"partial"},{"type":"refusal","refusal":"no"}]}]}""")) {
            action = { prefs -> assertThrows(Exception::class.java) { PostProcessor.process("raw", prefs, "", OkHttpClient()) } }
            reply(body = body)
        }
    }
    @Test fun nullBlankAndNonTextContentAreRejected() {
        for (content in listOf("null", "\" \"", "42", "[]")) {
            action = { prefs -> assertThrows(Exception::class.java) { PostProcessor.process("raw", prefs, "", OkHttpClient()) } }
            reply(body = """{"status":"completed","output":[{"type":"message","role":"assistant","status":"completed","content":[{"type":"output_text","text":$content}]}]}""")
        }
    }
    @Test fun httpErrorsRedirectsAndMalformedBodiesFail() {
        for ((status, body) in listOf(429 to "private provider error", 302 to "", 200 to "not json", 200 to "{\"choices\":[]}")) {
            action = { prefs ->
                val failure = assertThrows(Exception::class.java) { PostProcessor.process("raw", prefs, "fixture-key", OkHttpClient()) }
                if (status != 200) assertEquals("Processing failed (HTTP $status)", failure.message)
            }
            reply(status, body)
        }
    }
    @Test fun oversizedResponseIsRejected() {
        action = { prefs ->
            val failure = assertThrows(Exception::class.java) { PostProcessor.process("raw", prefs, "", OkHttpClient()) }
            assertEquals("Processing response is too large", failure.message)
        }
        reply(body = "x".repeat(256_001))
    }
    @Test fun disabledDoesNotContactProvider() {
        assertEquals("raw", PostProcessor.process("raw", Preferences.defaults(), "", OkHttpClient()))
    }
}
