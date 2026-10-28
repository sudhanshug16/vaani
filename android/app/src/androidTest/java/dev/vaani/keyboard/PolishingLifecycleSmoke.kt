package dev.vaani.keyboard

import android.content.Context
import android.media.AudioManager
import org.json.JSONObject
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Production capture + completion with device-local HTTP and a scripted speech socket. */
internal object PolishingLifecycleSmoke {
    fun run(context: Context): String {
        val input = (MicrophoneRouter(context).snapshot().decision as? MicrophoneDecision.Selected)?.microphone
            ?: error("Remember a microphone first")
        check(!MicrophoneRouter.isBluetooth(input.type)) { "Fixture expects built-in or USB microphone" }
        val audio = context.getSystemService(AudioManager::class.java)
        check(audio.activeRecordingConfigurations.isEmpty()) { "Another recorder is active; stop it before this check" }
        for (scenario in listOf("success", "http-error", "cancel")) {
            ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { server ->
                server.soTimeout = 10000
                val requestReceived = CountDownLatch(1)
                val respond = CountDownLatch(1)
                val served = CompletableFuture.runAsync {
                    server.accept().use { socket ->
                        socket.soTimeout = 8000
                        val stream = socket.getInputStream().buffered()
                        val header = StringBuilder()
                        while (!header.endsWith("\r\n\r\n")) {
                            val byte = stream.read(); check(byte >= 0 && header.length < 32768) { "Invalid HTTP fixture header" }
                            header.append(byte.toChar())
                        }
                        val lines = header.toString().split("\r\n")
                        check(lines.first() == "POST /v1/chat/completions HTTP/1.1") { "Wrong completion destination" }
                        val headers = lines.drop(1).filter { it.contains(':') }.associate { it.substringBefore(':').lowercase() to it.substringAfter(':').trim() }
                        check(headers["authorization"] == "Bearer fixture-processing-key") { "Wrong fixture credential" }
                        val body = ByteArray(headers.getValue("content-length").toInt())
                        var offset = 0
                        while (offset < body.size) { val n = stream.read(body, offset, body.size - offset); check(n > 0); offset += n }
                        check(JSONObject(String(body, Charsets.UTF_8)).getJSONArray("messages").getJSONObject(1).getString("content") == "Kal office mein demo hai.") { "Wrong raw transcript" }
                        requestReceived.countDown()
                        check(respond.await(8, TimeUnit.SECONDS)) { "Response was not released" }
                        if (scenario == "cancel") check(stream.read() == -1) { "Cancel did not abort HTTP socket" }
                        else {
                            val status = if (scenario == "success") 200 else 429
                            val response = if (scenario == "success") """{"choices":[{"message":{"content":"Kal office mein Vaani ka demo hai."}}]}""" else "{}"
                            val bytes = response.toByteArray()
                            socket.getOutputStream().apply {
                                write("HTTP/1.1 $status Fixture\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray())
                                write(bytes); flush()
                            }
                        }
                    }
                }
                val ready = CountDownLatch(1)
                val done = CountDownLatch(1)
                val callbacks = AtomicInteger()
                val outcome = AtomicReference<Pair<String, String?>?>()
                val settings = Preferences.defaults().put("processingEnabled", true).put("model", "fixture-model")
                    .put("endpoint", "http://127.0.0.1:${server.localPort}/v1")
                val session = DictationSession(context, input,
                    onState = { if (it.startsWith("Listening")) ready.countDown() }, onText = {},
                    onResult = { text, error -> callbacks.incrementAndGet(); outcome.set(text to error); done.countDown() },
                    configuration = { DictationConfiguration(settings, "fixture-speech-key", "fixture-processing-key") },
                    socketFactory = DictationLifecycleSmoke.ScriptedSocket("finish-final"))
                try {
                    session.start()
                    check(ready.await(8, TimeUnit.SECONDS)) { "$scenario capture did not start" }
                    session.finish()
                    check(requestReceived.await(8, TimeUnit.SECONDS)) { "$scenario completion did not arrive" }
                    // Poll the OS capture inventory, not just the app's state label.
                    for (attempt in 0..<40) {
                        if (audio.activeRecordingConfigurations.isEmpty()) break
                        Thread.sleep(25)
                    }
                    check(audio.activeRecordingConfigurations.isEmpty()) { "Microphone remained active during polishing" }
                    if (scenario == "cancel") {
                        checkRestart(context, input)
                        session.cancel()
                    }
                    respond.countDown()
                    served.get(8, TimeUnit.SECONDS)
                    if (scenario == "cancel") check(!done.await(500, TimeUnit.MILLISECONDS) && callbacks.get() == 0) { "Cancelled polishing published a late result" }
                    else {
                        check(done.await(5, TimeUnit.SECONDS) && callbacks.get() == 1) { "$scenario completion callback missing or repeated" }
                        val expected = if (scenario == "success") "Kal office mein Vaani ka demo hai." to null else "Kal office mein demo hai." to "Polishing failed. Raw text preserved."
                        check(outcome.get() == expected) { "$scenario recovery/output mismatch" }
                    }
                } finally { session.cancel(); respond.countDown() }
            }
        }
        return "Success, HTTP failure/raw recovery, microphone release before polishing, restart during polishing and Cancel/socket-abort/late-result suppression passed. Local HTTP and dummy keys only."
    }

    private fun checkRestart(context: Context, input: MicrophoneOption) {
        val ready = CountDownLatch(1); val done = CountDownLatch(1)
        val result = AtomicReference<Pair<String, String?>?>()
        val session = DictationSession(context, input,
            onState = { if (it.startsWith("Listening")) ready.countDown() }, onText = {},
            onResult = { text, error -> result.set(text to error); done.countDown() },
            configuration = { DictationConfiguration(Preferences.defaults(), "fixture-key", "") },
            socketFactory = DictationLifecycleSmoke.ScriptedSocket("finish-final"))
        try {
            session.start(); check(ready.await(5, TimeUnit.SECONDS)) { "Polishing retained the capture lock" }
            session.finish(); check(done.await(5, TimeUnit.SECONDS)) { "Restart did not finish" }
            check(result.get() == ("Kal office mein demo hai." to null)) { "Restart failed during polishing" }
        } finally { session.cancel() }
    }
}
