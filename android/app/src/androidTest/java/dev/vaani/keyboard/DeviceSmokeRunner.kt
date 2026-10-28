package dev.vaani.keyboard

import android.app.Activity
import android.app.Instrumentation
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Bundle
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Opt-in, physical-device smoke test. Never packaged in the release app.
 * Credentials enter through run-as stdin into app-private storage, never intent
 * extras, command arguments or logs. Only the non-secret outcome is reported. */
class DeviceSmokeRunner : Instrumentation() {
    private var mode = "none"
    override fun onCreate(arguments: Bundle?) {
        mode = arguments?.getString("mode") ?: "none"
        start()
    }
    override fun onStart() {
        Thread {
            val result = Bundle()
            try {
                when (mode) {
                    "import-key" -> importKey()
                    "capture" -> result.putString("transcript", capture())
                    "capture-timing" -> result.putString("transcript", capture(timings = result))
                    "capture-dictionary" -> result.putString("dictionary", capture(dictionaryHints = true))
                    "sync" -> result.putString("sync", sync())
                    "processing" -> result.putString("processing", processing())
                    "editing" -> result.putString("editing", editing())
                    "lifecycle" -> result.putString("lifecycle", DictationLifecycleSmoke.run(targetContext))
                    "polishing-lifecycle" -> result.putString("polishing", PolishingLifecycleSmoke.run(targetContext))
                    else -> error("Unknown smoke-test mode")
                }
                result.putString("result", "passed")
                finish(Activity.RESULT_OK, result)
            } catch (error: Exception) {
                result.putString("result", "failed")
                // Test failures never include credential contents or server bodies.
                result.putString("error", error.message ?: error.javaClass.simpleName)
                finish(Activity.RESULT_CANCELED, result)
            }
        }.start()
    }
    private fun editing(): String {
        // Real Android ICU and EditableInputConnection; no saved text, network or keys.
        var failure: Throwable? = null
        var checks = 0
        runOnMainSync {
            try {
                val editor = android.widget.EditText(targetContext)
                editor.inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE
                val connection = editor.onCreateInputConnection(android.view.inputmethod.EditorInfo())
                    ?: error("Editor did not expose an input connection")
                for (cluster in listOf("a", "😀", "👍🏽", "👨‍👩‍👧‍👦", "🇮🇳", "1️⃣", "e\u0301", "क\u093f", "நி")) {
                    editor.setText("A${cluster}Z")
                    editor.setSelection(1 + cluster.length)
                    check(EditorActions.backspace(connection)) { "Deletion refused fixture $checks" }
                    check(editor.text.toString() == "AZ" && editor.selectionStart == 1) { "Cluster or cursor damaged in fixture $checks" }
                    checks++
                }
                editor.setText("left👍🏽 selected👨‍👩‍👧‍👦right")
                editor.setSelection(4, editor.length() - 5)
                check(EditorActions.backspace(connection)) { "Selection deletion refused" }
                check(editor.text.toString() == "leftright" && editor.selectionStart == 4) { "Selection deletion damaged adjacent text" }
                checks++
                editor.setText("A😀")
                editor.setSelection(0)
                EditorActions.backspace(connection)
                check(editor.text.toString() == "A😀") { "Start-of-field deletion changed text" }
                checks++
                val oversized = "a" + "\u0301".repeat(4095)
                editor.setText(oversized)
                editor.setSelection(editor.length())
                check(!EditorActions.backspace(connection) && editor.text.toString() == oversized) { "Truncated cluster was split" }
                checks++
            } catch (error: Throwable) { failure = error }
        }
        failure?.let { throw IllegalStateException(it.message ?: "Editor action check failed", it) }
        return "$checks real Android editor checks passed: graphemes, selection, middle cursor, field start and bounded-context refusal."
    }
    private fun processing(): String {
        // Device-local HTTP fixture: no personal settings, saved keys or external API.
        val client = okhttp3.OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build()
        try {
            for ((status, body, expected) in listOf(
                Triple(200, "{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[{\"type\":\"output_text\",\"text\":\"Kal Sarvam aur Vaani ka demo hai.\"}]}]}", "Kal Sarvam aur Vaani ka demo hai."),
                Triple(200, "{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[{\"type\":\"output_text\",\"text\":null}]}]}", null),
                Triple(429, "{}", null), Triple(302, "{}", null))) {
                java.net.ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1")).use { server ->
                    server.soTimeout = 5000
                    val served = java.util.concurrent.CompletableFuture.runAsync {
                        server.accept().use { socket ->
                            socket.soTimeout = 5000
                            val input = socket.getInputStream().bufferedReader()
                            check(input.readLine() == "POST /v1/responses HTTP/1.1") { "Completion path mismatch" }
                            val headers = mutableMapOf<String, String>()
                            while (true) {
                                val line = input.readLine()
                                if (line.isEmpty()) break
                                headers[line.substringBefore(':').lowercase()] = line.substringAfter(':').trim()
                            }
                            check(headers["authorization"] == "Bearer fixture-key") { "Completion auth header mismatch" }
                            val chars = CharArray(headers.getValue("content-length").toInt())
                            var offset = 0
                            while (offset < chars.size) { val count = input.read(chars, offset, chars.size - offset); check(count > 0); offset += count }
                            val request = org.json.JSONObject(String(chars))
                            check(request.getJSONArray("input").getJSONObject(1).getString("content") == "kal sarvam aur vani ka demo hai") { "Transcript payload mismatch" }
                            val bytes = body.toByteArray()
                            socket.getOutputStream().apply {
                                write("HTTP/1.1 $status Fixture\r\nContent-Length: ${bytes.size}\r\nLocation: http://127.0.0.1:1/leak\r\nConnection: close\r\n\r\n".toByteArray())
                                write(bytes); flush()
                            }
                        }
                    }
                    val prefs = Preferences.defaults().put("processingEnabled", true).put("model", "fixture-model")
                        .put("endpoint", "http://127.0.0.1:${server.localPort}/v1")
                    var output: String? = null
                    try { output = PostProcessor.process("kal sarvam aur vani ka demo hai", prefs, "fixture-key", client) }
                    catch (error: Exception) {
                        check(expected == null) { "Valid completion failed" }
                        check(error.message == if (status == 200) "Model returned no text" else "Processing failed (HTTP $status)") { "Unexpected completion failure" }
                    }
                    finally { served.get(8, TimeUnit.SECONDS) }
                    check(output == expected) { "Completion response acceptance mismatch" }
                }
            }
            return "Device-local completion success, null rejection, HTTP error and redirect rejection passed."
        } finally { client.connectionPool.evictAll(); client.dispatcher.executorService.shutdown() }
    }
    private fun importKey() {
        val file = File(targetContext.filesDir, ".stt-test-key")
        try {
            check(file.length() in 1..4096) { "Private key fixture missing or invalid" }
            val key = file.readText().trim()
            check(key.isNotBlank()) { "Private key fixture empty" }
            val prefs = Preferences(targetContext)
            prefs.saveKey("sarvam", key)
            check(prefs.key("sarvam") == key) { "Credential round-trip failed" }
        } finally { check(!file.exists() || file.delete()) { "Could not remove private key fixture" } }
    }
    private fun capture(dictionaryHints: Boolean = false, timings: Bundle? = null): String {
        val prefs = Preferences(targetContext)
        val saved = prefs.shared
        val snapshot = MicrophoneRouter(targetContext).snapshot()
        val input = (snapshot.decision as? MicrophoneDecision.Selected)?.microphone
            ?: error("Choose and remember a microphone in Vaani first")
        check(!MicrophoneRouter.isBluetooth(input.type)) { "This speaker fixture expects a built-in or USB microphone" }
        val fixture = File(targetContext.filesDir, "hinglish-fixture.pcm").readBytes()
        check(fixture.size in 2..1_920_000 && fixture.size % 2 == 0) { "PCM fixture invalid" }
        val listening = CountDownLatch(1)
        val done = CountDownLatch(1)
        val startedAt = java.util.concurrent.atomic.AtomicLong()
        val listeningAt = java.util.concurrent.atomic.AtomicLong()
        val firstTextAt = java.util.concurrent.atomic.AtomicLong()
        val resultAt = java.util.concurrent.atomic.AtomicLong()
        val peakLevel = java.util.concurrent.atomic.AtomicInteger()
        val levelSamples = java.util.concurrent.atomic.AtomicInteger()
        val outcome = AtomicReference<Pair<String, String?>?>(null)
        val session = DictationSession(targetContext, input,
            onState = { if (it.startsWith("Listening")) { listeningAt.compareAndSet(0, System.nanoTime()); listening.countDown() } },
            onText = { if (it.isNotBlank()) firstTextAt.compareAndSet(0, System.nanoTime()) },
            onResult = { text, error -> resultAt.set(System.nanoTime()); outcome.set(text to error); done.countDown(); listening.countDown() },
            onLevel = { level -> peakLevel.accumulateAndGet(level, ::maxOf); levelSamples.incrementAndGet() })
        var track: AudioTrack? = null
        try {
            val testSettings = org.json.JSONObject(saved.toString()).put("processingEnabled", false)
            if (dictionaryHints) testSettings.put("dictionary", org.json.JSONArray(listOf("Sarvam", "Vaani")))
            prefs.shared = testSettings
            startedAt.set(System.nanoTime())
            session.start()
            check(listening.await(25, TimeUnit.SECONDS)) { "Microphone did not become ready" }
            outcome.get()?.let { error(it.second ?: "Capture ended before playback") }
            track = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(16000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(AudioTrack.MODE_STATIC).setBufferSizeInBytes(fixture.size).build()
            check(track.write(fixture, 0, fixture.size) == fixture.size) { "Fixture playback write failed" }
            check(track.state == AudioTrack.STATE_INITIALIZED) { "Could not initialize fixture playback" }
            val playbackAt = System.nanoTime()
            track.play()
            Thread.sleep(fixture.size.toLong() * 1000 / 32000 + 1500)
            val finishAt = System.nanoTime()
            session.finish()
            check(done.await(25, TimeUnit.SECONDS)) { "Dictation did not finish" }
            val (text, failure) = outcome.get() ?: error("No dictation outcome")
            check(failure == null) { failure ?: "Dictation failed" }
            check(text.isNotBlank()) { "No speech detected; check speaker audibility and microphone route" }
            timings?.apply {
                putLong("start_to_listening_ms", TimeUnit.NANOSECONDS.toMillis(listeningAt.get() - startedAt.get()))
                putLong("playback_to_first_text_ms", if (firstTextAt.get() == 0L) -1 else TimeUnit.NANOSECONDS.toMillis(firstTextAt.get() - playbackAt))
                putLong("finish_to_result_ms", TimeUnit.NANOSECONDS.toMillis(resultAt.get() - finishAt))
                putLong("start_to_result_ms", TimeUnit.NANOSECONDS.toMillis(resultAt.get() - startedAt.get()))
                putLong("clip_duration_ms", fixture.size.toLong() * 1000 / 32000)
                putInt("max_input_level", peakLevel.get())
                putInt("input_level_samples", levelSamples.get())
            }
            return text
        } finally {
            session.cancel()
            track?.release()
            prefs.shared = saved
        }
    }
    private fun sync(): String {
        val file = File(targetContext.filesDir, ".sync-pairing")
        val peer = try { SyncPairing.parse(file.readText()) } finally { file.delete() }
        val client = SettingsSyncClient(peer)
        val snapshot = client.fetch()
        check(snapshot.settings.getJSONArray("dictionary").toString().contains("sync-smoke")) { "Unexpected Mac fixture settings" }
        val incoming = org.json.JSONObject(snapshot.settings.toString())
            .put("dictionary", org.json.JSONArray().put("Android sync smoke"))
        client.offer(snapshot, incoming)
        var applied = false
        for (attempt in 0 until 30) {
            if (client.fetch().settings.getJSONArray("dictionary").toString().contains("Android sync smoke")) { applied = true; break }
            Thread.sleep(100)
        }
        check(applied) { "Mac fixture did not apply offer" }
        try { client.offer(snapshot, incoming); error("Stale revision was accepted") }
        catch (error: IllegalStateException) { check(error.message?.contains("Mac settings changed") == true) { "Unexpected conflict outcome" } }
        val wrongKey = java.util.Base64.getEncoder().encodeToString(ByteArray(32) { 99 })
        var rejected = false
        try { SettingsSyncClient(peer.copy(secret = wrongKey)).fetch() } catch (_: Exception) { rejected = true }
        check(rejected) { "Wrong pairing key was accepted" }
        return "Mac fetch, Android offer, Mac fixture apply, stale-revision conflict and wrong-key rejection passed over Tailscale."
    }
}
