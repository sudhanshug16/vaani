package dev.vaani.keyboard

import android.content.Context
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Uses real microphone capture with a scripted socket, dummy keys and isolated settings. */
internal object DictationLifecycleSmoke {
    fun run(context: Context): String {
        val input = (MicrophoneRouter(context).snapshot().decision as? MicrophoneDecision.Selected)?.microphone
            ?: error("Remember a microphone first")
        check(!MicrophoneRouter.isBluetooth(input.type)) { "Lifecycle fixture expects a built-in or USB microphone" }
        for (scenario in listOf("early-end", "server-end", "failure", "malformed", "finish-partial", "finish-final", "cancel", "restart")) {
            val listening = CountDownLatch(1)
            val done = CountDownLatch(1)
            val outcome = AtomicReference<Pair<String, String?>?>()
            val callbacks = AtomicInteger()
            val socket = ScriptedSocket(scenario)
            val session = DictationSession(context, input,
                onState = { if (it.startsWith("Listening")) listening.countDown() }, onText = {},
                onResult = { text, error -> callbacks.incrementAndGet(); outcome.set(text to error); done.countDown() },
                configuration = { DictationConfiguration(Preferences.defaults().put("processingEnabled", false), "fixture-key", "") },
                socketFactory = socket)
            try {
                session.start()
                if (scenario != "early-end") {
                    check(listening.await(8, TimeUnit.SECONDS)) { "$scenario microphone did not become ready" }
                    socket.event("""{"event":"transcript.partial","utterance_idx":0,"text":"Kal office mein"}""")
                    when (scenario) {
                        "server-end" -> socket.event("""{"event":"session.end"}""")
                        "failure" -> socket.fail()
                        "malformed" -> socket.event("not-json")
                        "cancel" -> session.cancel()
                        else -> session.finish()
                    }
                }
                if (scenario == "cancel") {
                    // Late events from the cancelled transport cannot resurrect a result.
                    socket.event("""{"event":"transcript.final","utterance_idx":0,"text":"late text"}""")
                    check(!done.await(350, TimeUnit.MILLISECONDS) && callbacks.get() == 0) { "Cancelled session published a result" }
                } else {
                    check(done.await(8, TimeUnit.SECONDS)) { "$scenario did not finish" }
                    val (text, error) = outcome.get() ?: error("Missing outcome")
                    when (scenario) {
                        "early-end" -> check(text.isEmpty() && error?.contains("before recording") == true && socket.audio.get() == 0) { "Early end started capture or lost its notice" }
                        "server-end", "finish-partial" -> check(text == "Kal office mein" && error?.contains("not finalized") == true) { "$scenario lost partial text or review notice" }
                        "failure" -> check(text == "Kal office mein" && error?.contains("connection failed") == true) { "Connection failure lost partial text" }
                        "malformed" -> check(text == "Kal office mein" && error == "Invalid speech response") { "Malformed event lost partial text" }
                        else -> check(text == "Kal office mein demo hai." && error == null) { "Normal Finish regressed" }
                    }
                    check(callbacks.get() == 1 && socket.cancelled) { "$scenario result count or socket cleanup failed" }
                    check(socket.endMessages.get() == if (scenario.startsWith("finish") || scenario == "restart") 1 else 0) { "$scenario sent an unexpected end event" }
                }
            } finally { session.cancel() }
        }
        return "8 real-capture lifecycle scenarios passed: early end, partial server end, disconnect, malformed event, partial/final Finish, cancel and restart. No provider network or saved-key access."
    }

    internal class ScriptedSocket(private val scenario: String) : WebSocket, WebSocket.Factory {
        private lateinit var request: Request
        private lateinit var listener: WebSocketListener
        val audio = AtomicInteger()
        val endMessages = AtomicInteger()
        @Volatile var cancelled = false
        override fun newWebSocket(request: Request, listener: WebSocketListener): WebSocket {
            this.request = request; this.listener = listener
            event("""{"event":"session.begin"}""")
            if (scenario == "early-end") event("""{"event":"session.end"}""")
            return this
        }
        fun event(text: String) { listener.onMessage(this, text) }
        fun fail() { listener.onFailure(this, IOException("fixture disconnect"), null as Response?) }
        override fun request() = request
        override fun queueSize() = 0L
        override fun send(text: String): Boolean {
            if (cancelled) return false
            if (text.contains("audio_input")) audio.incrementAndGet()
            if (text == "{\"event\":\"end\"}") {
                endMessages.incrementAndGet()
                if (scenario != "finish-partial") event("""{"event":"transcript.final","utterance_idx":0,"text":"Kal office mein demo hai."}""")
                event("""{"event":"session.end"}""")
            }
            return true
        }
        override fun send(bytes: ByteString) = false
        override fun close(code: Int, reason: String?) = true
        override fun cancel() { cancelled = true }
    }
}
