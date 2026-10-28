package dev.vaani.keyboard

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.util.Base64
import okhttp3.*
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.locks.ReentrantLock
import kotlin.math.max

internal data class DictationConfiguration(val settings: JSONObject, val speechKey: String, val processingKey: String)

class DictationSession internal constructor(private val context: Context, private val input: MicrophoneOption, private val onState: (String) -> Unit,
    private val onText: (String) -> Unit, private val onResult: (String, String?) -> Unit,
    private val configuration: () -> DictationConfiguration = {
        val prefs = Preferences(context)
        val settings = prefs.shared
        DictationConfiguration(settings, prefs.key("sarvam"), if (settings.getBoolean("processingEnabled")) prefs.key("processing") else "")
    }, private val socketFactory: WebSocket.Factory? = null,
    private val onLevel: (Int) -> Unit = {}) {
    private val executor = Executors.newSingleThreadExecutor()
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .connectTimeout(15, TimeUnit.SECONDS).readTimeout(45, TimeUnit.SECONDS).callTimeout(50, TimeUnit.SECONDS).build()
    private val cancelled = AtomicBoolean(false)
    private val stopping = AtomicBoolean(false)
    private val serverEnded = AtomicBoolean(false)
    private val serverEndedUnexpectedly = AtomicBoolean(false)
    private val ready = CountDownLatch(1)
    private val ended = CountDownLatch(1)
    private val failure = AtomicReference<String?>(null)
    private val transcript = SpeechTranscript()
    @Volatile private var socket: WebSocket? = null
    @Volatile private var call: Call? = null
    private var recorder: AudioRecord? = null
    private var route: BluetoothRoute? = null
    private var ownsCapture = false
    // AudioManager routes are app-scoped: an old session must finish restoring
    // its route before a rapidly restarted session can request another one.
    private companion object { val captureLock = ReentrantLock() }

    fun start() { executor.execute {
        var result: Pair<String, String?>? = null
        try { result = perform() }
        catch (error: Exception) { result = transcript.text() to (error.message ?: "Dictation failed") }
        finally {
            try { stopCapture() } catch (_: Exception) { result = (result?.first ?: transcript.text()) to "Could not restore the audio route. Check Android audio settings." }
            socket?.cancel(); call?.cancel(); client.connectionPool.evictAll(); executor.shutdown()
        }
        if (!cancelled.get()) result?.let { onResult(it.first, it.second) }
    } }
    private fun perform(): Pair<String, String?>? {
        if (cancelled.get()) return null
        check(context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) { "Open Vaani and allow microphone access first." }
        val config = configuration()
        val settings = config.settings
        val key = config.speechKey; check(key.isNotBlank()) { "Add a Sarvam key in Vaani settings." }
        val processingKey = config.processingKey
        if (cancelled.get()) return null
        if (stopping.get()) return "" to "Stopped before recording began."
        check(captureLock.tryLock(2, TimeUnit.SECONDS)) { "Previous recording is still stopping. Try dictation again." }
        ownsCapture = true
        if (cancelled.get()) return null
        val bluetooth = MicrophoneRouter.isBluetooth(input.type)
        // The legacy SCO contract only guarantees 8 kHz mono capture.
        val sampleRate = if (bluetooth && Build.VERSION.SDK_INT < 31) 8000 else 16000
        MicrophoneRouter(context).resolve(input.uid) // Revalidate the UID before contacting Sarvam.
        onState("Connecting…")
        socket = (socketFactory ?: client).newWebSocket(Request.Builder().url(SarvamProtocol.url(settings, sampleRate)).header("Api-Subscription-Key", key).build(), object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                if (cancelled.get()) return
                try {
                    val event = JSONObject(text)
                    when (event.getString("event")) {
                        "session.begin" -> ready.countDown()
                        "transcript.partial", "transcript.final" -> { transcript.receive(event); onText(transcript.text()) }
                        "session.end" -> {
                            if (!stopping.getAndSet(true)) serverEndedUnexpectedly.set(true)
                            serverEnded.set(true); ready.countDown(); ended.countDown()
                        }
                        "error" -> fail(event.optString("message", "Sarvam session failed"))
                    }
                } catch (_: Exception) { fail("Invalid speech response") }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (!cancelled.get() && !serverEnded.get()) fail("Speech connection failed${response?.let { " (HTTP ${it.code})" } ?: ""}.")
            }
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) { webSocket.close(code, reason) }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (!serverEnded.get() && !cancelled.get()) fail("Speech connection closed before finalization ($code).")
            }
        })
        check(ready.await(15, TimeUnit.SECONDS)) { "Speech session timed out." }
        failure.get()?.let { error(it) }
        if (cancelled.get()) return null
        if (stopping.get()) return transcript.text() to if (serverEnded.get()) "Speech session ended before recording began. Review available text." else "Stopped before recording began."
        if (bluetooth) {
            onState("Connecting Bluetooth microphone…")
            route = BluetoothRoute.open(context, input) { cancelled.get() || stopping.get() }
        }
        if (cancelled.get()) return null
        val selected = MicrophoneRouter(context).resolve(input.uid) // SCO can recreate input port IDs.
        val minimum = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0) { "Microphone format unavailable" }
        val capture = AudioRecord.Builder().setAudioSource(if (bluetooth) MediaRecorder.AudioSource.VOICE_COMMUNICATION else MediaRecorder.AudioSource.VOICE_RECOGNITION)
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(sampleRate).setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
            .setBufferSizeInBytes(max(minimum * 2, 8192)).build()
        recorder = capture
        check(capture.state == AudioRecord.STATE_INITIALIZED) { "Could not initialize microphone" }
        check(capture.setPreferredDevice(selected)) { "Android refused the selected microphone." }
        if (cancelled.get()) return null
        if (stopping.get()) return transcript.text() to "Stopped before recording began."
        capture.startRecording()
        check(capture.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Microphone did not start" }
        onState("Confirming microphone…")
        val verifier = RecordingRouteVerifier(selected.id, System.nanoTime() / 1_000_000 + 2000)
        var confirmed = false
        var lastFrames = System.nanoTime()
        var lastLevelAt = 0L
        val chunk = ByteArray(sampleRate / 5)
        while (!cancelled.get() && !stopping.get()) {
            val count = capture.read(chunk, 0, chunk.size, AudioRecord.READ_NON_BLOCKING)
            if (cancelled.get() || stopping.get()) break
            check(count >= 0) { "Microphone read failed ($count)" }
            val verified = verifier.accept(capture.routedDevice?.id, System.nanoTime() / 1_000_000)
            if (count == 0) {
                check(System.nanoTime() - lastFrames < TimeUnit.SECONDS.toNanos(3)) { "No audio frames reached Vaani. Check microphone privacy and competing recording apps." }
                Thread.sleep(15); continue
            }
            lastFrames = System.nanoTime()
            if (!verified) continue
            if (Build.VERSION.SDK_INT >= 29) check(capture.activeRecordingConfiguration?.isClientSilenced != true) { "Android silenced this microphone. Check privacy settings or competing recording apps." }
            if (!confirmed) { confirmed = true; onState("Listening · ${input.label}") }
            val now = System.nanoTime()
            if (now - lastLevelAt >= TimeUnit.MILLISECONDS.toNanos(100)) {
                onLevel(AudioLevel.pcm16(chunk, count)); lastLevelAt = now
            }
            check((socket?.queueSize() ?: 0) < 512_000) { "Network too slow; partial text preserved." }
            val encoded = Base64.encodeToString(chunk, 0, count, Base64.NO_WRAP)
            check(socket?.send(JSONObject().put("event", "audio_input").put("audio", encoded).toString()) == true) { "Speech connection unavailable" }
        }
        stopCapture() // Release Bluetooth and microphone before waiting on network or polishing.
        if (cancelled.get()) return null
        failure.get()?.let { error(it) }
        onState("Finishing…")
        if (!serverEnded.get()) check(socket?.send("{\"event\":\"end\"}") == true) { "Could not finalize speech" }
        check(ended.await(15, TimeUnit.SECONDS)) { "Final transcript timed out; partial text preserved." }
        failure.get()?.let { error(it) }
        // Keep unfinished words visible for review when the server ends early.
        // A partial left after explicit Finish also must not silently disappear.
        val hasPartial = transcript.hasPendingPartial()
        val raw = transcript.text()
        socket?.close(1000, null)
        if (cancelled.get()) return null
        if (serverEndedUnexpectedly.get() || hasPartial) return raw to "Speech session ended. Review available text${if (hasPartial) "; the last words were not finalized" else ""}."
        if (settings.getBoolean("processingEnabled") && raw.isNotBlank()) {
            onState("Polishing…")
            return try { PostProcessor.process(raw, settings, processingKey, client, { requestCall ->
                call = requestCall
                if (cancelled.get()) { requestCall.cancel(); error("Dictation cancelled.") }
            }) to null }
            catch (_: Exception) { raw to "Polishing failed. Raw text preserved." }
        }
        return raw to null
    }
    private fun stopCapture() {
        try {
            recorder?.let { capture ->
                recorder = null
                try { if (capture.recordingState == AudioRecord.RECORDSTATE_RECORDING) capture.stop() }
                finally { capture.release() }
            }
        } finally {
            try { route?.let { route = null; it.close() } }
            finally { if (ownsCapture) { ownsCapture = false; captureLock.unlock() } }
        }
    }
    private fun fail(message: String) { failure.compareAndSet(null, message); stopping.set(true); ready.countDown(); ended.countDown() }
    fun finish() { stopping.set(true); ready.countDown() }
    fun cancel() { cancelled.set(true); stopping.set(true); socket?.cancel(); call?.cancel(); ready.countDown(); ended.countDown() }
}
